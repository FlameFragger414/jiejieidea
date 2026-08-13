-- Development-only sample data. These fictional users and tokens must never be
-- copied to a production environment.

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
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'mia.owner@example.invalid',
    '',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Mia Chen"}',
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'leo.giver@example.invalid',
    '',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Leo Park"}',
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'ana.giver@example.invalid',
    '',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Ana Silva"}',
    now(),
    now()
  )
on conflict (id) do nothing;

update public.profiles
set onboarding_completed = true
where id in (
  '10000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000003'
);

insert into public.wishlists (
  id,
  public_slug,
  owner_id,
  name,
  description,
  type,
  event_date,
  visibility,
  position
) values
  (
    '20000000-0000-0000-0000-000000000001',
    '200000000000000000000001',
    '10000000-0000-0000-0000-000000000001',
    'Thirty & thriving',
    'A few things for a cosy birthday weekend.',
    'birthday',
    current_date + 45,
    'link_only',
    0
  ),
  (
    '20000000-0000-0000-0000-000000000002',
    '200000000000000000000002',
    '10000000-0000-0000-0000-000000000001',
    'Things I want',
    'An always-on list of considered favourites.',
    'ongoing',
    null,
    'public',
    1
  )
on conflict (id) do nothing;

insert into public.wishlist_members (wishlist_id, user_id, role, invited_by)
values (
  '20000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002',
  'viewer',
  '10000000-0000-0000-0000-000000000001'
)
on conflict (wishlist_id, user_id) do nothing;

insert into public.wishlist_share_links (
  id,
  wishlist_id,
  token_hash,
  label,
  expires_at,
  created_by
) values (
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  extensions.digest('development-share-token-do-not-use', 'sha256'),
  'Development preview',
  now() + interval '90 days',
  '10000000-0000-0000-0000-000000000001'
)
on conflict (id) do nothing;

insert into public.wishlist_items (
  id,
  wishlist_id,
  product_name,
  description,
  product_url,
  retailer_name,
  estimated_price,
  currency,
  desired_quantity,
  variant,
  priority,
  category,
  position
) values
  (
    '40000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    'Hand-thrown ramen bowls',
    'A pair in the deep ocean glaze.',
    'https://example.invalid/products/ramen-bowls',
    'Sample Ceramics',
    88.00,
    'AUD',
    2,
    'Ocean glaze',
    'high',
    'Home',
    0
  ),
  (
    '40000000-0000-0000-0000-000000000002',
    '20000000-0000-0000-0000-000000000001',
    'Linen picnic blanket',
    'Large enough for four people.',
    'https://example.invalid/products/picnic-blanket',
    'Sample Outdoors',
    149.00,
    'AUD',
    1,
    'Sage stripe',
    'normal',
    'Outdoors',
    1
  ),
  (
    '40000000-0000-0000-0000-000000000003',
    '20000000-0000-0000-0000-000000000002',
    'Compact instant camera',
    'For weekends away; any neutral colour.',
    'https://example.invalid/products/instant-camera',
    'Sample Camera Shop',
    179.95,
    'AUD',
    1,
    null,
    'must_have',
    'Tech',
    0
  )
on conflict (id) do nothing;

insert into public.gift_reservations (
  id,
  wishlist_item_id,
  reserver_id,
  quantity,
  private_note,
  idempotency_key
) values (
  '50000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002',
  1,
  'Pair this with the cookbook I found.',
  '60000000-0000-0000-0000-000000000001'
)
on conflict (id) do nothing;
