begin;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated;

create extension if not exists pgcrypto with schema extensions;

create type public.wishlist_type as enum (
  'birthday',
  'wedding',
  'christmas',
  'baby_shower',
  'graduation',
  'ongoing',
  'other'
);

create type public.wishlist_visibility as enum ('private', 'link_only', 'public');
create type public.wishlist_state as enum ('active', 'archived', 'closed');
create type public.wishlist_member_role as enum ('viewer', 'editor');
create type public.wishlist_item_status as enum (
  'wanted',
  'purchased_by_owner',
  'received',
  'no_longer_wanted'
);
create type public.wishlist_item_priority as enum ('low', 'normal', 'high', 'must_have');
create type public.gift_reservation_status as enum ('reserved', 'purchased', 'cancelled', 'unavailable');
create type public.notification_kind as enum (
  'wishlist_shared',
  'wishlist_updated',
  'reservation_unavailable',
  'event_approaching',
  'price_changed'
);
create type public.device_platform as enum ('ios', 'macos');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  avatar_path text,
  onboarding_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length check (char_length(btrim(display_name)) between 1 and 80),
  constraint profiles_avatar_path_length check (avatar_path is null or char_length(avatar_path) <= 500)
);

create table public.wishlists (
  id uuid primary key default gen_random_uuid(),
  public_slug text not null unique default lower(encode(extensions.gen_random_bytes(12), 'hex')),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text not null default '',
  type public.wishlist_type not null default 'ongoing',
  event_date date,
  cover_image_path text,
  visibility public.wishlist_visibility not null default 'private',
  state public.wishlist_state not null default 'active',
  position bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wishlists_name_length check (char_length(btrim(name)) between 1 and 120),
  constraint wishlists_description_length check (char_length(description) <= 2000),
  constraint wishlists_cover_path_length check (cover_image_path is null or char_length(cover_image_path) <= 500),
  constraint wishlists_public_slug_format check (public_slug ~ '^[a-f0-9]{24}$')
);

create table public.wishlist_members (
  wishlist_id uuid not null references public.wishlists(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.wishlist_member_role not null default 'viewer',
  invited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (wishlist_id, user_id)
);

create table public.wishlist_share_links (
  id uuid primary key default gen_random_uuid(),
  wishlist_id uuid not null references public.wishlists(id) on delete cascade,
  token_hash bytea not null unique,
  label text,
  expires_at timestamptz,
  revoked_at timestamptz,
  last_used_at timestamptz,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint share_links_label_length check (label is null or char_length(btrim(label)) between 1 and 80),
  constraint share_links_expiry_after_creation check (expires_at is null or expires_at > created_at)
);

create table public.wishlist_items (
  id uuid primary key default gen_random_uuid(),
  wishlist_id uuid not null references public.wishlists(id) on delete cascade,
  product_name text not null,
  description text not null default '',
  image_path text,
  product_url text,
  retailer_name text,
  estimated_price numeric(12, 2),
  currency text,
  desired_quantity integer not null default 1,
  variant text,
  priority public.wishlist_item_priority not null default 'normal',
  category text,
  position bigint not null default 0,
  status public.wishlist_item_status not null default 'wanted',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wishlist_items_name_length check (char_length(btrim(product_name)) between 1 and 200),
  constraint wishlist_items_description_length check (char_length(description) <= 4000),
  constraint wishlist_items_image_path_length check (image_path is null or char_length(image_path) <= 500),
  constraint wishlist_items_url_length check (
    product_url is null or (char_length(product_url) <= 2048 and product_url ~* '^https?://')
  ),
  constraint wishlist_items_retailer_length check (retailer_name is null or char_length(btrim(retailer_name)) between 1 and 120),
  constraint wishlist_items_price_nonnegative check (estimated_price is null or estimated_price >= 0),
  constraint wishlist_items_currency_format check (currency is null or currency ~ '^[A-Z]{3}$'),
  constraint wishlist_items_quantity_positive check (desired_quantity between 1 and 999),
  constraint wishlist_items_variant_length check (variant is null or char_length(variant) <= 500),
  constraint wishlist_items_category_length check (category is null or char_length(category) <= 80),
  constraint wishlist_items_price_currency_pair check (
    (estimated_price is null and currency is null) or (estimated_price is not null and currency is not null)
  )
);

create table public.gift_reservations (
  id uuid primary key default gen_random_uuid(),
  wishlist_item_id uuid not null references public.wishlist_items(id) on delete cascade,
  reserver_id uuid not null references auth.users(id) on delete cascade,
  quantity integer not null,
  status public.gift_reservation_status not null default 'reserved',
  private_note text,
  idempotency_key uuid not null,
  purchased_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint gift_reservations_quantity_positive check (quantity between 1 and 999),
  constraint gift_reservations_note_length check (private_note is null or char_length(private_note) <= 1000),
  constraint gift_reservations_purchase_timestamp check (
    (status = 'purchased' and purchased_at is not null) or status <> 'purchased'
  ),
  constraint gift_reservations_cancel_timestamp check (
    (status = 'cancelled' and cancelled_at is not null) or status <> 'cancelled'
  ),
  unique (reserver_id, idempotency_key)
);

create table public.wishlist_item_status_events (
  id uuid primary key default gen_random_uuid(),
  wishlist_item_id uuid not null references public.wishlist_items(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  previous_status public.wishlist_item_status not null,
  new_status public.wishlist_item_status not null,
  created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  kind public.notification_kind not null,
  title text not null,
  body text not null,
  payload jsonb not null default '{}'::jsonb,
  deduplication_key text,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint notifications_title_length check (char_length(btrim(title)) between 1 and 120),
  constraint notifications_body_length check (char_length(body) between 1 and 500),
  constraint notifications_payload_object check (jsonb_typeof(payload) = 'object'),
  constraint notifications_deduplication_length check (
    deduplication_key is null or char_length(deduplication_key) <= 200
  ),
  unique (recipient_id, deduplication_key)
);

create table public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  wishlist_shared boolean not null default true,
  wishlist_updated boolean not null default true,
  reservation_unavailable boolean not null default true,
  event_approaching boolean not null default true,
  price_changed boolean not null default false,
  push_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform public.device_platform not null,
  token text not null unique,
  environment text not null,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint device_tokens_token_length check (char_length(token) between 32 and 512),
  constraint device_tokens_environment check (environment in ('development', 'production'))
);

create index wishlists_owner_position_idx on public.wishlists(owner_id, state, position);
create index wishlists_public_browse_idx on public.wishlists(visibility, state, updated_at desc);
create index wishlist_members_user_idx on public.wishlist_members(user_id, wishlist_id);
create index wishlist_share_links_wishlist_idx on public.wishlist_share_links(wishlist_id, created_at desc);
create index wishlist_share_links_active_idx on public.wishlist_share_links(wishlist_id, expires_at)
  where revoked_at is null;
create index wishlist_items_wishlist_position_idx on public.wishlist_items(wishlist_id, position);
create index gift_reservations_item_active_idx on public.gift_reservations(wishlist_item_id, status)
  where status in ('reserved', 'purchased');
create index gift_reservations_reserver_history_idx on public.gift_reservations(reserver_id, created_at desc);
create index wishlist_item_status_events_item_idx on public.wishlist_item_status_events(wishlist_item_id, created_at desc);
create index notifications_recipient_unread_idx on public.notifications(recipient_id, created_at desc)
  where read_at is null;
create index device_tokens_user_idx on public.device_tokens(user_id);

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create trigger wishlists_set_updated_at
before update on public.wishlists
for each row execute function private.set_updated_at();

create trigger wishlist_items_set_updated_at
before update on public.wishlist_items
for each row execute function private.set_updated_at();

create trigger gift_reservations_set_updated_at
before update on public.gift_reservations
for each row execute function private.set_updated_at();

create trigger notification_preferences_set_updated_at
before update on public.notification_preferences
for each row execute function private.set_updated_at();

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
      'New member'
    )
  );

  insert into public.notification_preferences (user_id)
  values (new.id);

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

create or replace function private.is_wishlist_owner(p_wishlist_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.wishlists w
    where w.id = p_wishlist_id
      and w.owner_id = (select auth.uid())
  );
$$;

create or replace function private.can_view_wishlist(p_wishlist_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.wishlists w
    where w.id = p_wishlist_id
      and (
        w.owner_id = (select auth.uid())
        or (
          w.state = 'active'
          and (
            w.visibility = 'public'
            or exists (
              select 1
              from public.wishlist_members wm
              where wm.wishlist_id = w.id
                and wm.user_id = (select auth.uid())
            )
          )
        )
      )
  );
$$;

create or replace function private.can_edit_wishlist_items(p_wishlist_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.wishlists w
    where w.id = p_wishlist_id
      and (
        w.owner_id = (select auth.uid())
        or (
          w.state = 'active'
          and exists (
            select 1
            from public.wishlist_members wm
            where wm.wishlist_id = w.id
              and wm.user_id = (select auth.uid())
              and wm.role = 'editor'
          )
        )
      )
  );
$$;

create or replace function private.has_valid_share_token(p_wishlist_id uuid, p_share_token text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, extensions
as $$
  select p_share_token is not null
    and char_length(p_share_token) between 32 and 256
    and exists (
      select 1
      from public.wishlist_share_links sl
      join public.wishlists w on w.id = sl.wishlist_id
      where sl.wishlist_id = p_wishlist_id
        and sl.token_hash = extensions.digest(p_share_token, 'sha256')
        and sl.revoked_at is null
        and (sl.expires_at is null or sl.expires_at > now())
        and w.visibility = 'link_only'
        and w.state = 'active'
    );
$$;

create or replace function private.is_gift_viewer(p_wishlist_id uuid, p_share_token text default null)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select (select auth.uid()) is not null
    and not private.is_wishlist_owner(p_wishlist_id)
    and exists (
      select 1
      from public.wishlists w
      where w.id = p_wishlist_id
        and w.state = 'active'
        and (
          w.visibility = 'public'
          or exists (
            select 1
            from public.wishlist_members wm
            where wm.wishlist_id = w.id
              and wm.user_id = (select auth.uid())
          )
          or private.has_valid_share_token(w.id, p_share_token)
        )
    );
$$;

revoke all on function private.set_updated_at() from public;
revoke all on function private.handle_new_user() from public;
revoke all on function private.is_wishlist_owner(uuid) from public;
revoke all on function private.can_view_wishlist(uuid) from public;
revoke all on function private.can_edit_wishlist_items(uuid) from public;
revoke all on function private.has_valid_share_token(uuid, text) from public;
revoke all on function private.is_gift_viewer(uuid, text) from public;
grant execute on function private.is_wishlist_owner(uuid) to authenticated;
grant execute on function private.can_view_wishlist(uuid) to authenticated;
grant execute on function private.can_edit_wishlist_items(uuid) to authenticated;
grant execute on function private.has_valid_share_token(uuid, text) to authenticated;
grant execute on function private.is_gift_viewer(uuid, text) to authenticated;

alter table public.profiles enable row level security;
alter table public.wishlists enable row level security;
alter table public.wishlist_members enable row level security;
alter table public.wishlist_share_links enable row level security;
alter table public.wishlist_items enable row level security;
alter table public.gift_reservations enable row level security;
alter table public.wishlist_item_status_events enable row level security;
alter table public.notifications enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.device_tokens enable row level security;

create policy profiles_select_self on public.profiles
for select to authenticated
using (id = (select auth.uid()));

create policy profiles_update_self on public.profiles
for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy wishlists_select_authorized on public.wishlists
for select to authenticated
using (private.can_view_wishlist(id));

create policy wishlists_insert_owner on public.wishlists
for insert to authenticated
with check (owner_id = (select auth.uid()));

create policy wishlists_update_owner on public.wishlists
for update to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

create policy wishlists_delete_owner on public.wishlists
for delete to authenticated
using (owner_id = (select auth.uid()));

create policy wishlist_members_select_owner_or_self on public.wishlist_members
for select to authenticated
using (user_id = (select auth.uid()) or private.is_wishlist_owner(wishlist_id));

create policy wishlist_members_insert_owner on public.wishlist_members
for insert to authenticated
with check (
  private.is_wishlist_owner(wishlist_id)
  and invited_by = (select auth.uid())
  and user_id <> (select auth.uid())
);

create policy wishlist_members_update_owner on public.wishlist_members
for update to authenticated
using (private.is_wishlist_owner(wishlist_id))
with check (private.is_wishlist_owner(wishlist_id) and user_id <> (select auth.uid()));

create policy wishlist_members_delete_owner on public.wishlist_members
for delete to authenticated
using (private.is_wishlist_owner(wishlist_id));

create policy wishlist_share_links_select_owner on public.wishlist_share_links
for select to authenticated
using (private.is_wishlist_owner(wishlist_id));

create policy wishlist_items_select_authorized on public.wishlist_items
for select to authenticated
using (private.can_view_wishlist(wishlist_id));

create policy wishlist_items_insert_editor on public.wishlist_items
for insert to authenticated
with check (private.can_edit_wishlist_items(wishlist_id));

create policy wishlist_items_update_editor on public.wishlist_items
for update to authenticated
using (private.can_edit_wishlist_items(wishlist_id))
with check (private.can_edit_wishlist_items(wishlist_id));

create policy wishlist_items_delete_editor on public.wishlist_items
for delete to authenticated
using (private.can_edit_wishlist_items(wishlist_id));

create policy gift_reservations_select_self on public.gift_reservations
for select to authenticated
using (reserver_id = (select auth.uid()));

create policy wishlist_item_status_events_select_owner on public.wishlist_item_status_events
for select to authenticated
using (
  exists (
    select 1
    from public.wishlist_items wi
    where wi.id = wishlist_item_status_events.wishlist_item_id
      and private.is_wishlist_owner(wi.wishlist_id)
  )
);

create policy notifications_select_self on public.notifications
for select to authenticated
using (recipient_id = (select auth.uid()));

create policy notifications_update_self on public.notifications
for update to authenticated
using (recipient_id = (select auth.uid()))
with check (recipient_id = (select auth.uid()));

create policy notifications_delete_self on public.notifications
for delete to authenticated
using (recipient_id = (select auth.uid()));

create policy notification_preferences_select_self on public.notification_preferences
for select to authenticated
using (user_id = (select auth.uid()));

create policy notification_preferences_insert_self on public.notification_preferences
for insert to authenticated
with check (user_id = (select auth.uid()));

create policy notification_preferences_update_self on public.notification_preferences
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy device_tokens_select_self on public.device_tokens
for select to authenticated
using (user_id = (select auth.uid()));

create policy device_tokens_insert_self on public.device_tokens
for insert to authenticated
with check (user_id = (select auth.uid()));

create policy device_tokens_update_self on public.device_tokens
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy device_tokens_delete_self on public.device_tokens
for delete to authenticated
using (user_id = (select auth.uid()));

revoke all on all tables in schema public from anon, authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.wishlists to authenticated;
grant select, insert, update, delete on public.wishlist_members to authenticated;
grant select on public.wishlist_share_links to authenticated;
grant select, insert, update, delete on public.wishlist_items to authenticated;
grant select on public.gift_reservations to authenticated;
grant select on public.wishlist_item_status_events to authenticated;
grant select, delete on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;
grant select, insert, update on public.notification_preferences to authenticated;
grant select, insert, update, delete on public.device_tokens to authenticated;

create or replace function public.browse_public_wishlists()
returns table (
  public_slug text,
  name text,
  description text,
  type public.wishlist_type,
  event_date date,
  cover_image_path text,
  owner_display_name text,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    w.public_slug,
    w.name,
    w.description,
    w.type,
    w.event_date,
    w.cover_image_path,
    p.display_name,
    w.updated_at
  from public.wishlists w
  join public.profiles p on p.id = w.owner_id
  where w.visibility = 'public'
    and w.state = 'active'
  order by w.updated_at desc;
$$;

create or replace function public.get_public_wishlist_items(p_public_slug text)
returns table (
  item_id uuid,
  product_name text,
  description text,
  image_path text,
  product_url text,
  retailer_name text,
  estimated_price numeric,
  currency text,
  desired_quantity integer,
  variant text,
  priority public.wishlist_item_priority,
  category text,
  sort_position bigint,
  status public.wishlist_item_status
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    wi.id,
    wi.product_name,
    wi.description,
    wi.image_path,
    wi.product_url,
    wi.retailer_name,
    wi.estimated_price,
    wi.currency,
    wi.desired_quantity,
    wi.variant,
    wi.priority,
    wi.category,
    wi.position,
    wi.status
  from public.wishlist_items wi
  join public.wishlists w on w.id = wi.wishlist_id
  where w.public_slug = p_public_slug
    and w.visibility = 'public'
    and w.state = 'active'
  order by wi.position, wi.created_at;
$$;

create or replace function public.get_gift_wishlist_items(
  p_wishlist_id uuid,
  p_share_token text default null
)
returns table (
  item_id uuid,
  product_name text,
  description text,
  image_path text,
  product_url text,
  retailer_name text,
  estimated_price numeric,
  currency text,
  desired_quantity integer,
  available_quantity integer,
  variant text,
  priority public.wishlist_item_priority,
  category text,
  sort_position bigint,
  status public.wishlist_item_status
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not private.is_gift_viewer(p_wishlist_id, p_share_token) then
    raise exception using errcode = 'P0001', message = 'wishlist_access_denied';
  end if;

  return query
  select
    wi.id,
    wi.product_name,
    wi.description,
    wi.image_path,
    wi.product_url,
    wi.retailer_name,
    wi.estimated_price,
    wi.currency,
    wi.desired_quantity,
    case
      when wi.status <> 'wanted' then 0
      else greatest(
        wi.desired_quantity - coalesce(sum(gr.quantity) filter (
          where gr.status in ('reserved', 'purchased')
        ), 0)::integer,
        0
      )
    end as available_quantity,
    wi.variant,
    wi.priority,
    wi.category,
    wi.position,
    wi.status
  from public.wishlist_items wi
  left join public.gift_reservations gr on gr.wishlist_item_id = wi.id
  where wi.wishlist_id = p_wishlist_id
  group by wi.id
  order by wi.position, wi.created_at;
end;
$$;

create or replace function public.create_wishlist_share_link(
  p_wishlist_id uuid,
  p_expires_at timestamptz default null,
  p_label text default null
)
returns table (link_id uuid, token text, expires_at timestamptz)
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_token text;
  v_link_id uuid;
begin
  if (select auth.uid()) is null or not private.is_wishlist_owner(p_wishlist_id) then
    raise exception using errcode = 'P0001', message = 'wishlist_access_denied';
  end if;

  if not exists (
    select 1 from public.wishlists
    where id = p_wishlist_id and visibility = 'link_only' and state = 'active'
  ) then
    raise exception using errcode = 'P0001', message = 'wishlist_not_link_shareable';
  end if;

  if p_expires_at is not null and p_expires_at <= now() then
    raise exception using errcode = '22023', message = 'share_link_expiry_must_be_future';
  end if;

  if p_label is not null and char_length(btrim(p_label)) not between 1 and 80 then
    raise exception using errcode = '22023', message = 'invalid_share_link_label';
  end if;

  v_token := lower(encode(extensions.gen_random_bytes(32), 'hex'));

  insert into public.wishlist_share_links (
    wishlist_id,
    token_hash,
    label,
    expires_at,
    created_by
  ) values (
    p_wishlist_id,
    extensions.digest(v_token, 'sha256'),
    nullif(btrim(p_label), ''),
    p_expires_at,
    (select auth.uid())
  )
  returning id into v_link_id;

  return query select v_link_id, v_token, p_expires_at;
end;
$$;

create or replace function public.revoke_wishlist_share_link(p_link_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $$
begin
  update public.wishlist_share_links sl
  set revoked_at = coalesce(sl.revoked_at, now())
  where sl.id = p_link_id
    and private.is_wishlist_owner(sl.wishlist_id);

  if not found then
    raise exception using errcode = 'P0001', message = 'share_link_not_found';
  end if;
end;
$$;

create or replace function public.reserve_wishlist_item(
  p_item_id uuid,
  p_quantity integer,
  p_private_note text,
  p_idempotency_key uuid,
  p_share_token text default null
)
returns table (
  reservation_id uuid,
  item_id uuid,
  quantity integer,
  status public.gift_reservation_status,
  private_note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $$
declare
  v_item public.wishlist_items%rowtype;
  v_existing public.gift_reservations%rowtype;
  v_reserved integer;
  v_reservation public.gift_reservations%rowtype;
begin
  if (select auth.uid()) is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  if p_quantity is null or p_quantity not between 1 and 999 then
    raise exception using errcode = '22023', message = 'invalid_reservation_quantity';
  end if;

  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'idempotency_key_required';
  end if;

  if p_private_note is not null and char_length(p_private_note) > 1000 then
    raise exception using errcode = '22023', message = 'private_note_too_long';
  end if;

  select * into v_item
  from public.wishlist_items wi
  where wi.id = p_item_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'wishlist_item_not_found';
  end if;

  if not private.is_gift_viewer(v_item.wishlist_id, p_share_token) then
    raise exception using errcode = 'P0001', message = 'wishlist_access_denied';
  end if;

  select * into v_existing
  from public.gift_reservations gr
  where gr.reserver_id = (select auth.uid())
    and gr.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.wishlist_item_id <> p_item_id or v_existing.quantity <> p_quantity then
      raise exception using errcode = 'P0001', message = 'idempotency_conflict';
    end if;

    return query
    select
      v_existing.id,
      v_existing.wishlist_item_id,
      v_existing.quantity,
      v_existing.status,
      v_existing.private_note,
      v_existing.created_at,
      v_existing.updated_at;
    return;
  end if;

  if v_item.status <> 'wanted' then
    raise exception using errcode = 'P0001', message = 'wishlist_item_unavailable';
  end if;

  select coalesce(sum(gr.quantity), 0)::integer into v_reserved
  from public.gift_reservations gr
  where gr.wishlist_item_id = p_item_id
    and gr.status in ('reserved', 'purchased');

  if v_reserved + p_quantity > v_item.desired_quantity then
    raise exception using errcode = 'P0001', message = 'insufficient_quantity';
  end if;

  insert into public.gift_reservations (
    wishlist_item_id,
    reserver_id,
    quantity,
    private_note,
    idempotency_key
  ) values (
    p_item_id,
    (select auth.uid()),
    p_quantity,
    nullif(btrim(p_private_note), ''),
    p_idempotency_key
  )
  returning * into v_reservation;

  return query
  select
    v_reservation.id,
    v_reservation.wishlist_item_id,
    v_reservation.quantity,
    v_reservation.status,
    v_reservation.private_note,
    v_reservation.created_at,
    v_reservation.updated_at;
end;
$$;

create or replace function public.cancel_gift_reservation(p_reservation_id uuid)
returns table (
  reservation_id uuid,
  item_id uuid,
  quantity integer,
  status public.gift_reservation_status,
  private_note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $$
declare
  v_reservation public.gift_reservations%rowtype;
begin
  select * into v_reservation
  from public.gift_reservations gr
  where gr.id = p_reservation_id
    and gr.reserver_id = (select auth.uid())
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'reservation_not_found';
  end if;

  if v_reservation.status in ('reserved', 'purchased') then
    update public.gift_reservations gr
    set status = 'cancelled',
        cancelled_at = now(),
        purchased_at = case when gr.status = 'purchased' then gr.purchased_at else null end
    where gr.id = p_reservation_id
    returning * into v_reservation;
  end if;

  return query
  select
    v_reservation.id,
    v_reservation.wishlist_item_id,
    v_reservation.quantity,
    v_reservation.status,
    v_reservation.private_note,
    v_reservation.created_at,
    v_reservation.updated_at;
end;
$$;

create or replace function public.mark_reservation_purchased(p_reservation_id uuid)
returns table (
  reservation_id uuid,
  item_id uuid,
  quantity integer,
  status public.gift_reservation_status,
  private_note text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $$
declare
  v_reservation public.gift_reservations%rowtype;
begin
  select * into v_reservation
  from public.gift_reservations gr
  where gr.id = p_reservation_id
    and gr.reserver_id = (select auth.uid())
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'reservation_not_found';
  end if;

  if v_reservation.status = 'reserved' then
    update public.gift_reservations
    set status = 'purchased', purchased_at = now()
    where id = p_reservation_id
    returning * into v_reservation;
  elsif v_reservation.status <> 'purchased' then
    raise exception using errcode = 'P0001', message = 'reservation_not_active';
  end if;

  return query
  select
    v_reservation.id,
    v_reservation.wishlist_item_id,
    v_reservation.quantity,
    v_reservation.status,
    v_reservation.private_note,
    v_reservation.created_at,
    v_reservation.updated_at;
end;
$$;

create or replace function public.get_my_gift_reservations()
returns table (
  reservation_id uuid,
  wishlist_name text,
  item_id uuid,
  product_name text,
  image_path text,
  retailer_name text,
  quantity integer,
  status public.gift_reservation_status,
  private_note text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    gr.id,
    w.name,
    wi.id,
    wi.product_name,
    wi.image_path,
    wi.retailer_name,
    gr.quantity,
    gr.status,
    gr.private_note,
    gr.created_at,
    gr.updated_at
  from public.gift_reservations gr
  join public.wishlist_items wi on wi.id = gr.wishlist_item_id
  join public.wishlists w on w.id = wi.wishlist_id
  where gr.reserver_id = (select auth.uid())
  order by gr.created_at desc;
$$;

create or replace function private.reconcile_item_reservations()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_reservation record;
begin
  if new.status is distinct from old.status then
    insert into public.wishlist_item_status_events (
      wishlist_item_id,
      actor_id,
      previous_status,
      new_status
    ) values (
      new.id,
      (select auth.uid()),
      old.status,
      new.status
    );
  end if;

  if new.status <> 'wanted' then
    for v_reservation in
      update public.gift_reservations gr
      set status = 'unavailable'
      where gr.wishlist_item_id = new.id
        and gr.status in ('reserved', 'purchased')
      returning gr.id, gr.reserver_id
    loop
      insert into public.notifications (
        recipient_id,
        kind,
        title,
        body,
        payload,
        deduplication_key
      ) values (
        v_reservation.reserver_id,
        'reservation_unavailable',
        'A reserved gift changed',
        'The wishlist owner changed an item you reserved. Open My gifts for details.',
        jsonb_build_object('reservation_id', v_reservation.id),
        'reservation-unavailable:' || v_reservation.id::text
      )
      on conflict (recipient_id, deduplication_key) do nothing;
    end loop;
  elsif new.desired_quantity < old.desired_quantity then
    for v_reservation in
      with ranked as (
        select
          gr.id,
          sum(gr.quantity) over (order by gr.created_at, gr.id) as running_quantity
        from public.gift_reservations gr
        where gr.wishlist_item_id = new.id
          and gr.status in ('reserved', 'purchased')
      )
      update public.gift_reservations gr
      set status = 'unavailable'
      from ranked r
      where gr.id = r.id
        and r.running_quantity > new.desired_quantity
      returning gr.id, gr.reserver_id
    loop
      insert into public.notifications (
        recipient_id,
        kind,
        title,
        body,
        payload,
        deduplication_key
      ) values (
        v_reservation.reserver_id,
        'reservation_unavailable',
        'A reserved gift changed',
        'The requested quantity changed and your reservation is no longer active.',
        jsonb_build_object('reservation_id', v_reservation.id),
        'reservation-unavailable:' || v_reservation.id::text
      )
      on conflict (recipient_id, deduplication_key) do nothing;
    end loop;
  end if;

  return new;
end;
$$;

create trigger wishlist_items_reconcile_reservations
after update of status, desired_quantity on public.wishlist_items
for each row
when (
  old.status is distinct from new.status
  or old.desired_quantity is distinct from new.desired_quantity
)
execute function private.reconcile_item_reservations();

revoke all on function public.browse_public_wishlists() from public;
revoke all on function public.get_public_wishlist_items(text) from public;
revoke all on function public.get_gift_wishlist_items(uuid, text) from public;
revoke all on function public.create_wishlist_share_link(uuid, timestamptz, text) from public;
revoke all on function public.revoke_wishlist_share_link(uuid) from public;
revoke all on function public.reserve_wishlist_item(uuid, integer, text, uuid, text) from public;
revoke all on function public.cancel_gift_reservation(uuid) from public;
revoke all on function public.mark_reservation_purchased(uuid) from public;
revoke all on function public.get_my_gift_reservations() from public;
revoke all on function private.reconcile_item_reservations() from public;

grant execute on function public.browse_public_wishlists() to anon, authenticated;
grant execute on function public.get_public_wishlist_items(text) to anon, authenticated;
grant execute on function public.get_gift_wishlist_items(uuid, text) to authenticated;
grant execute on function public.create_wishlist_share_link(uuid, timestamptz, text) to authenticated;
grant execute on function public.revoke_wishlist_share_link(uuid) to authenticated;
grant execute on function public.reserve_wishlist_item(uuid, integer, text, uuid, text) to authenticated;
grant execute on function public.cancel_gift_reservation(uuid) to authenticated;
grant execute on function public.mark_reservation_purchased(uuid) to authenticated;
grant execute on function public.get_my_gift_reservations() to authenticated;

alter default privileges in schema public revoke execute on functions from public;

-- Reservation rows are deliberately excluded from Realtime publication.
-- Safe item/wishlist changes can be observed and followed by an authoritative refresh.
alter publication supabase_realtime add table public.wishlists, public.wishlist_items, public.notifications;

commit;
