begin;

create extension if not exists pgtap with schema extensions;
select plan(34);

select has_table('public', 'profiles', 'profiles table exists');
select has_table('public', 'gift_reservations', 'gift reservations table exists');
select is(
  (select relrowsecurity from pg_class where oid = 'public.gift_reservations'::regclass),
  true,
  'gift reservations have RLS enabled'
);
select ok(
  position(
    'for update' in lower(pg_get_functiondef(
      'public.reserve_wishlist_item(uuid,integer,text,uuid,text)'::regprocedure
    ))
  ) > 0,
  'reservation function locks the item row'
);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '71000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'owner@test.invalid', '', now(), '{}', '{"display_name":"Owner"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '71000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'giver-one@test.invalid', '', now(), '{}', '{"display_name":"Giver One"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '71000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'giver-two@test.invalid', '', now(), '{}', '{"display_name":"Giver Two"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '71000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'stranger@test.invalid', '', now(), '{}', '{"display_name":"Stranger"}', now(), now());

insert into public.wishlists (
  id, public_slug, owner_id, name, visibility
) values
  ('72000000-0000-0000-0000-000000000001', '720000000000000000000001', '71000000-0000-0000-0000-000000000001', 'Private test list', 'private'),
  ('72000000-0000-0000-0000-000000000002', '720000000000000000000002', '71000000-0000-0000-0000-000000000001', 'Link test list', 'link_only'),
  ('72000000-0000-0000-0000-000000000003', '720000000000000000000003', '71000000-0000-0000-0000-000000000001', 'Public test list', 'public');

insert into public.wishlist_members (wishlist_id, user_id, role, invited_by)
values
  ('72000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000002', 'viewer', '71000000-0000-0000-0000-000000000001'),
  ('72000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000003', 'viewer', '71000000-0000-0000-0000-000000000001');

insert into public.wishlist_items (
  id, wishlist_id, product_name, desired_quantity
) values (
  '73000000-0000-0000-0000-000000000001',
  '72000000-0000-0000-0000-000000000001',
  'Final unit',
  1
);

insert into public.wishlist_share_links (
  id, wishlist_id, token_hash, label, expires_at, created_by, created_at
) values
  (
    '74000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000002',
    extensions.digest('valid-test-share-token-1234567890', 'sha256'),
    'Valid test token',
    now() + interval '1 day',
    '71000000-0000-0000-0000-000000000001',
    now()
  ),
  (
    '74000000-0000-0000-0000-000000000002',
    '72000000-0000-0000-0000-000000000002',
    extensions.digest('expired-test-share-token-123456', 'sha256'),
    'Expired test token',
    now() - interval '1 day',
    '71000000-0000-0000-0000-000000000001',
    now() - interval '2 days'
  );

select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select is((select count(*) from public.wishlists where id = '72000000-0000-0000-0000-000000000001'), 1::bigint, 'owner reads own private wishlist');
select throws_like(
  $$insert into public.wishlists (owner_id, name) values ('71000000-0000-0000-0000-000000000002', 'Forged owner')$$,
  '%row-level security%',
  'client cannot forge wishlist ownership'
);
select lives_ok(
  $$select * from public.create_wishlist_share_link('72000000-0000-0000-0000-000000000002', now() + interval '1 hour', 'Party')$$,
  'owner can create a link-only share link'
);
select throws_like(
  $$select * from public.reserve_wishlist_item('73000000-0000-0000-0000-000000000001', 1, null, '75000000-0000-0000-0000-000000000001', null)$$,
  '%wishlist_access_denied%',
  'owner cannot call the reservation function'
);
select throws_like(
  $$select * from public.get_gift_wishlist_items('72000000-0000-0000-0000-000000000001', null)$$,
  '%wishlist_access_denied%',
  'owner cannot call aggregate availability function'
);

reset role;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000004', true);
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000004","role":"authenticated"}', true);
set local role authenticated;

select is((select count(*) from public.wishlists where id = '72000000-0000-0000-0000-000000000001'), 0::bigint, 'stranger cannot read private wishlist');

reset role;
set local role anon;
select is((select count(*) from public.browse_public_wishlists() where public_slug = '720000000000000000000003'), 1::bigint, 'anonymous caller sees only public catalog projection');
-- Publishing a wishlist publishes the owner's display name with it. That is intentional, and the
-- onboarding copy says so, so it is pinned here rather than left as an accident of the projection.
select is(
  (select owner_display_name from public.browse_public_wishlists() where public_slug = '720000000000000000000003'),
  'Owner',
  'a public wishlist exposes its owner display name to anonymous callers'
);
select is(
  (select count(*) from public.browse_public_wishlists() where public_slug in ('720000000000000000000001', '720000000000000000000002')),
  0::bigint,
  'a private or link-only wishlist never exposes its owner display name'
);
select throws_like(
  $$select count(*) from public.profiles$$,
  '%permission denied%',
  'the profiles table itself stays unreachable to anonymous callers'
);

reset role;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;

select is((select count(*) from public.wishlists where id = '72000000-0000-0000-0000-000000000001'), 1::bigint, 'selected member can read private wishlist');
select ok(
  private.has_valid_share_token('72000000-0000-0000-0000-000000000002', 'valid-test-share-token-1234567890'),
  'unexpired share token validates'
);
select ok(
  not private.has_valid_share_token('72000000-0000-0000-0000-000000000002', 'expired-test-share-token-123456'),
  'expired share token is rejected'
);

reset role;
update public.wishlist_share_links
set revoked_at = now()
where id = '74000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select ok(
  not private.has_valid_share_token('72000000-0000-0000-0000-000000000002', 'valid-test-share-token-1234567890'),
  'revoked share token is rejected'
);

select lives_ok(
  $$select * from public.reserve_wishlist_item('73000000-0000-0000-0000-000000000001', 1, 'Keep it secret', '75000000-0000-0000-0000-000000000002', null)$$,
  'gift-giver reserves the available unit'
);
select lives_ok(
  $$select * from public.reserve_wishlist_item('73000000-0000-0000-0000-000000000001', 1, 'Keep it secret', '75000000-0000-0000-0000-000000000002', null)$$,
  'idempotent reservation retry returns existing result'
);
select is((select count(*) from public.gift_reservations), 1::bigint, 'idempotent retry does not duplicate reservation');
select is((select count(*) from public.gift_reservations where reserver_id = '71000000-0000-0000-0000-000000000002'), 1::bigint, 'gift-giver sees own reservation');
select throws_like(
  $$insert into public.gift_reservations (wishlist_item_id, reserver_id, quantity, idempotency_key) values ('73000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000002', 1, '75000000-0000-0000-0000-000000000099')$$,
  '%permission denied%',
  'direct client reservation insert is denied'
);
select throws_like(
  $$select * from public.reserve_wishlist_item('73000000-0000-0000-0000-000000000001', 1, repeat('x', 1001), '75000000-0000-0000-0000-000000000098', null)$$,
  '%private_note_too_long%',
  'oversized private note is rejected'
);

reset role;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
set local role authenticated;

select is((select count(*) from public.gift_reservations), 0::bigint, 'another gift-giver cannot read reservation identity or note');
select throws_like(
  $$select * from public.reserve_wishlist_item('73000000-0000-0000-0000-000000000001', 1, null, '75000000-0000-0000-0000-000000000003', null)$$,
  '%insufficient_quantity%',
  'second gift-giver cannot reserve the final unit'
);

reset role;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*) from public.gift_reservations), 0::bigint, 'wishlist owner cannot select reservation rows');

reset role;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select lives_ok(
  $$select * from public.cancel_gift_reservation((select id from public.gift_reservations limit 1))$$,
  'gift-giver can cancel own reservation'
);

reset role;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select lives_ok(
  $$select * from public.reserve_wishlist_item('73000000-0000-0000-0000-000000000001', 1, null, '75000000-0000-0000-0000-000000000004', null)$$,
  'cancellation releases capacity for another gift-giver'
);
select lives_ok(
  $$select * from public.mark_reservation_purchased((select id from public.gift_reservations where status = 'reserved' limit 1))$$,
  'gift-giver marks own reservation purchased'
);

reset role;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select lives_ok(
  $$update public.wishlist_items set status = 'purchased_by_owner' where id = '73000000-0000-0000-0000-000000000001'$$,
  'owner status change succeeds without reading reservations'
);

reset role;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select is((select status::text from public.gift_reservations where id is not null), 'unavailable', 'owner status change privately invalidates affected reservation');
select is((select count(*) from public.notifications where kind = 'reservation_unavailable'), 1::bigint, 'affected gift-giver receives private notification');

reset role;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*) from public.notifications), 0::bigint, 'owner receives no reservation notification');

reset role;
select * from finish();
rollback;
