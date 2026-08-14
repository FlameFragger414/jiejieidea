begin;

-- Corrective migration for the authentication and profile-onboarding slice.
--
-- 20260813020000 created the private `profile-images` bucket with `on conflict (id) do nothing`.
-- That is only correct for a project where the bucket did not already exist. A project that had
-- created `profile-images` by hand, or through an earlier configuration, kept whatever settings it
-- had: possibly public, possibly with no size ceiling, possibly accepting any MIME type. The
-- migration history is append-only, so the earlier file is left untouched and the settings are
-- forced here instead.
--
-- This runs the same way on both paths. On a fresh database the insert wins; on a database that
-- already has the bucket the conflict clause overwrites the three settings that matter.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-images',
  'profile-images',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- The four owner-scoped policies are re-declared so this file alone establishes the intended access
-- rules, and so re-running it is not an error. `private.is_own_profile_image` is unchanged: it
-- remains the single definition of a legitimate object name.

drop policy if exists profile_images_select_own on storage.objects;
create policy profile_images_select_own on storage.objects
for select to authenticated
using (bucket_id = 'profile-images' and private.is_own_profile_image(name));

drop policy if exists profile_images_insert_own on storage.objects;
create policy profile_images_insert_own on storage.objects
for insert to authenticated
with check (bucket_id = 'profile-images' and private.is_own_profile_image(name));

drop policy if exists profile_images_update_own on storage.objects;
create policy profile_images_update_own on storage.objects
for update to authenticated
using (bucket_id = 'profile-images' and private.is_own_profile_image(name))
with check (bucket_id = 'profile-images' and private.is_own_profile_image(name));

drop policy if exists profile_images_delete_own on storage.objects;
create policy profile_images_delete_own on storage.objects
for delete to authenticated
using (bucket_id = 'profile-images' and private.is_own_profile_image(name));

commit;
