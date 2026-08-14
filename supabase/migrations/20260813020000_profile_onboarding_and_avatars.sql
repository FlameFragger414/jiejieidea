begin;

-- Profile onboarding, editing, and private profile-image storage.
--
-- Direct client updates to public.profiles are withdrawn. Every write goes through a
-- security definer function so display names are normalized once, onboarding cannot be
-- silently reverted, and avatar paths can never point at another person's storage folder.

revoke update on public.profiles from authenticated;

create or replace function private.normalized_display_name(p_display_name text)
returns text
language sql
immutable
set search_path = pg_catalog, public
as $$
  select nullif(btrim(regexp_replace(coalesce(p_display_name, ''), '[[:space:]]+', ' ', 'g')), '');
$$;

-- The single definition of a legitimate profile-image object name:
-- "<caller uuid>/<uuid>.<supported extension>", with no nested folders and no traversal.
-- The caller identity always comes from the verified JWT, never from an argument.
create or replace function private.is_own_profile_image(p_object_name text)
returns boolean
language sql
stable
set search_path = pg_catalog, public
as $$
  select (select auth.uid()) is not null
    and p_object_name is not null
    and p_object_name ~ (
      '^' || (select auth.uid())::text
      || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|heic|webp)$'
    );
$$;

revoke all on function private.normalized_display_name(text) from public;
revoke all on function private.is_own_profile_image(text) from public;
grant execute on function private.is_own_profile_image(text) to authenticated;

-- The bucket is created here as well as in supabase/config.toml so a hosted deployment gets the
-- same private bucket, size ceiling, and MIME allow list from migrations alone.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-images',
  'profile-images',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
)
on conflict (id) do nothing;

-- storage.objects has RLS enabled with no policies, so every bucket is unreachable until a policy
-- names it. These four policies scope access to the caller's own folder inside profile-images and
-- leave every other bucket, including wishlist-images, unreadable.
create policy profile_images_select_own on storage.objects
for select to authenticated
using (bucket_id = 'profile-images' and private.is_own_profile_image(name));

create policy profile_images_insert_own on storage.objects
for insert to authenticated
with check (bucket_id = 'profile-images' and private.is_own_profile_image(name));

create policy profile_images_update_own on storage.objects
for update to authenticated
using (bucket_id = 'profile-images' and private.is_own_profile_image(name))
with check (bucket_id = 'profile-images' and private.is_own_profile_image(name));

create policy profile_images_delete_own on storage.objects
for delete to authenticated
using (bucket_id = 'profile-images' and private.is_own_profile_image(name));

create or replace function public.save_my_profile(
  p_display_name text,
  p_complete_onboarding boolean default false
)
returns table (
  id uuid,
  display_name text,
  avatar_path text,
  onboarding_completed boolean,
  created_at timestamptz,
  updated_at timestamptz,
  replaced_avatar_path text
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_display_name text;
  v_profile public.profiles%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  v_display_name := private.normalized_display_name(p_display_name);

  if v_display_name is null then
    raise exception using errcode = '22023', message = 'display_name_required';
  end if;

  if char_length(v_display_name) > 80 then
    raise exception using errcode = '22023', message = 'display_name_too_long';
  end if;

  update public.profiles p
  set display_name = v_display_name,
      onboarding_completed = p.onboarding_completed or coalesce(p_complete_onboarding, false)
  where p.id = v_user_id
  returning p.* into v_profile;

  if not found then
    raise exception using errcode = 'P0001', message = 'profile_not_found';
  end if;

  return query
  select
    v_profile.id,
    v_profile.display_name,
    v_profile.avatar_path,
    v_profile.onboarding_completed,
    v_profile.created_at,
    v_profile.updated_at,
    null::text;
end;
$$;

create or replace function public.set_my_profile_avatar(p_object_name text)
returns table (
  id uuid,
  display_name text,
  avatar_path text,
  onboarding_completed boolean,
  created_at timestamptz,
  updated_at timestamptz,
  replaced_avatar_path text
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_previous_path text;
  v_profile public.profiles%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  if not private.is_own_profile_image(p_object_name) then
    raise exception using errcode = '42501', message = 'avatar_not_owned';
  end if;

  -- Refuse to record a path that was never uploaded, so the profile can never advertise an
  -- object the caller does not actually own.
  if not exists (
    select 1
    from storage.objects o
    where o.bucket_id = 'profile-images'
      and o.name = p_object_name
  ) then
    raise exception using errcode = 'P0001', message = 'avatar_object_missing';
  end if;

  select p.avatar_path into v_previous_path
  from public.profiles p
  where p.id = v_user_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'profile_not_found';
  end if;

  update public.profiles p
  set avatar_path = p_object_name
  where p.id = v_user_id
  returning p.* into v_profile;

  return query
  select
    v_profile.id,
    v_profile.display_name,
    v_profile.avatar_path,
    v_profile.onboarding_completed,
    v_profile.created_at,
    v_profile.updated_at,
    case
      when v_previous_path is distinct from p_object_name then v_previous_path
      else null
    end;
end;
$$;

create or replace function public.clear_my_profile_avatar()
returns table (
  id uuid,
  display_name text,
  avatar_path text,
  onboarding_completed boolean,
  created_at timestamptz,
  updated_at timestamptz,
  replaced_avatar_path text
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_previous_path text;
  v_profile public.profiles%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  select p.avatar_path into v_previous_path
  from public.profiles p
  where p.id = v_user_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'profile_not_found';
  end if;

  update public.profiles p
  set avatar_path = null
  where p.id = v_user_id
  returning p.* into v_profile;

  return query
  select
    v_profile.id,
    v_profile.display_name,
    v_profile.avatar_path,
    v_profile.onboarding_completed,
    v_profile.created_at,
    v_profile.updated_at,
    v_previous_path;
end;
$$;

revoke all on function public.save_my_profile(text, boolean) from public;
revoke all on function public.set_my_profile_avatar(text) from public;
revoke all on function public.clear_my_profile_avatar() from public;
grant execute on function public.save_my_profile(text, boolean) to authenticated;
grant execute on function public.set_my_profile_avatar(text) to authenticated;
grant execute on function public.clear_my_profile_avatar() to authenticated;

commit;
