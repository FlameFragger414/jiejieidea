begin;

create extension if not exists pgtap with schema extensions;
select plan(44);

select has_function('public', 'save_my_profile', 'profile save function exists');
select has_function('public', 'set_my_profile_avatar', 'avatar assignment function exists');
select has_function('public', 'clear_my_profile_avatar', 'avatar removal function exists');
select is(
  (select relrowsecurity from pg_class where oid = 'storage.objects'::regclass),
  true,
  'storage objects have RLS enabled'
);
select is(
  (select public from storage.buckets where id = 'profile-images'),
  false,
  'profile image bucket is private'
);
select is(
  (select allowed_mime_types from storage.buckets where id = 'profile-images'),
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp'],
  'profile image bucket restricts uploads to supported image types'
);
select is(
  (select file_size_limit from storage.buckets where id = 'profile-images'),
  5242880::bigint,
  'profile image bucket caps object size'
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
  ('00000000-0000-0000-0000-000000000000', '81000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'profile-owner@test.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '81000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'profile-stranger@test.invalid', '', now(), '{}', '{"display_name":"Stranger"}', now(), now());

-- The new-user trigger seeds a placeholder name until onboarding replaces it.
select is(
  (select display_name from public.profiles where id = '81000000-0000-0000-0000-000000000001'),
  'New member',
  'a new account starts with the seeded placeholder name'
);
select is(
  (select onboarding_completed from public.profiles where id = '81000000-0000-0000-0000-000000000001'),
  false,
  'a new account starts with onboarding incomplete'
);

select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"81000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select is(
  (select count(*) from public.profiles),
  1::bigint,
  'a signed-in person reads only their own profile'
);
select throws_like(
  $$update public.profiles set display_name = 'Forged' where id = '81000000-0000-0000-0000-000000000001'$$,
  '%permission denied%',
  'direct profile updates are denied so writes stay behind functions'
);

select is(
  (select display_name from public.save_my_profile('  Mia   Chen  ')),
  'Mia Chen',
  'saving a profile trims and collapses whitespace'
);
select is(
  (select onboarding_completed from public.save_my_profile('Mia Chen')),
  false,
  'saving a name does not silently complete onboarding'
);
select throws_like(
  $$select * from public.save_my_profile('   ')$$,
  '%display_name_required%',
  'a blank display name is rejected'
);
select throws_like(
  $$select * from public.save_my_profile(repeat('m', 81))$$,
  '%display_name_too_long%',
  'an overlong display name is rejected'
);
select is(
  (select onboarding_completed from public.save_my_profile('Mia Chen', true)),
  true,
  'completing onboarding is recorded'
);
select is(
  (select onboarding_completed from public.save_my_profile('Mia C', false)),
  true,
  'a later edit cannot revert completed onboarding'
);

select ok(
  private.is_own_profile_image('81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-000000000001.jpg'),
  'an object inside the caller folder is owned'
);
select ok(
  not private.is_own_profile_image('81000000-0000-0000-0000-000000000002/a1b2c3d4-0000-4000-8000-000000000001.jpg'),
  'an object inside another folder is not owned'
);
select ok(
  not private.is_own_profile_image('81000000-0000-0000-0000-000000000001/nested/a1b2c3d4-0000-4000-8000-000000000001.jpg'),
  'a nested object path is rejected'
);
select ok(
  not private.is_own_profile_image('81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-000000000001.svg'),
  'an unsupported extension is rejected'
);
select ok(
  not private.is_own_profile_image('81000000-0000-0000-0000-000000000001/avatar.jpg'),
  'a non-random object name is rejected'
);

select lives_ok(
  $$insert into storage.objects (bucket_id, name, owner_id)
    values ('profile-images', '81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-000000000001.jpg', '81000000-0000-0000-0000-000000000001')$$,
  'a signed-in person uploads into their own profile folder'
);
select throws_like(
  $$insert into storage.objects (bucket_id, name, owner_id)
    values ('profile-images', '81000000-0000-0000-0000-000000000002/a1b2c3d4-0000-4000-8000-000000000009.jpg', '81000000-0000-0000-0000-000000000001')$$,
  '%row-level security%',
  'uploading into another person folder is denied'
);
-- Claiming ownership in the row itself must not grant access to somebody else's folder.
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"81000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select throws_like(
  $$insert into storage.objects (bucket_id, name, owner_id)
    values ('profile-images', '81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-000000000002.jpg', '81000000-0000-0000-0000-000000000001')$$,
  '%row-level security%',
  'the owner column cannot grant access to another person folder'
);

select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"81000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select throws_like(
  $$insert into storage.objects (bucket_id, name, owner_id)
    values ('wishlist-images', '81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-000000000003.jpg', '81000000-0000-0000-0000-000000000001')$$,
  '%row-level security%',
  'buckets without a policy stay unreachable'
);

select is(
  (select count(*) from storage.objects where bucket_id = 'profile-images'),
  1::bigint,
  'a signed-in person reads their own profile image'
);

select is(
  (select avatar_path from public.set_my_profile_avatar('81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-000000000001.jpg')),
  '81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-000000000001.jpg',
  'an uploaded object can be attached to the profile'
);
select is(
  (select replaced_avatar_path from public.set_my_profile_avatar('81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-000000000001.jpg')),
  null,
  'reattaching the same object reports nothing to clean up'
);
select throws_like(
  $$select * from public.set_my_profile_avatar('81000000-0000-0000-0000-000000000002/a1b2c3d4-0000-4000-8000-000000000009.jpg')$$,
  '%avatar_not_owned%',
  'a profile cannot point at another person object'
);
select throws_like(
  $$select * from public.set_my_profile_avatar('81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-00000000000f.jpg')$$,
  '%avatar_object_missing%',
  'a profile cannot point at an object that was never uploaded'
);

select lives_ok(
  $$insert into storage.objects (bucket_id, name, owner_id)
    values ('profile-images', '81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-000000000004.jpg', '81000000-0000-0000-0000-000000000001')$$,
  'a replacement image can be uploaded alongside the current one'
);
select is(
  (select replaced_avatar_path from public.set_my_profile_avatar('81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-000000000004.jpg')),
  '81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-000000000001.jpg',
  'replacing an image reports the object the client should remove'
);
select is(
  (select replaced_avatar_path from public.clear_my_profile_avatar()),
  '81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-000000000004.jpg',
  'removing an image reports the object the client should remove'
);
select is(
  (select avatar_path from public.profiles where id = '81000000-0000-0000-0000-000000000001'),
  null,
  'the profile no longer references an image after removal'
);

select set_config('storage.allow_delete_query', 'true', true);
select lives_ok(
  $$delete from storage.objects
    where bucket_id = 'profile-images'
      and name = '81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-000000000004.jpg'$$,
  'a signed-in person deletes their own profile image'
);

reset role;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"81000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;

select is(
  (select count(*) from storage.objects where bucket_id = 'profile-images'),
  0::bigint,
  'another person cannot see profile images they do not own'
);
select set_config('storage.allow_delete_query', 'true', true);
select lives_ok(
  $$delete from storage.objects where bucket_id = 'profile-images'$$,
  'a delete aimed at another person image runs without matching rows'
);
select is(
  (select count(*) from public.profiles),
  1::bigint,
  'another person still reads only their own profile'
);
select is(
  (select display_name from public.profiles),
  'Stranger',
  'a provider supplied name is used instead of the placeholder'
);

reset role;
select is(
  (select count(*) from storage.objects
    where bucket_id = 'profile-images'
      and name = '81000000-0000-0000-0000-000000000001/a1b2c3d4-0000-4000-8000-000000000001.jpg'),
  1::bigint,
  'the first owner image survived the other person delete attempt'
);

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '', true);
set local role authenticated;
select throws_like(
  $$select * from public.save_my_profile('Anonymous')$$,
  '%authentication_required%',
  'an unauthenticated caller cannot save a profile'
);

reset role;
set local role anon;
select throws_like(
  $$select * from public.save_my_profile('Anonymous')$$,
  '%permission denied%',
  'the anonymous role cannot execute the profile functions'
);
select throws_like(
  $$select * from public.clear_my_profile_avatar()$$,
  '%permission denied%',
  'the anonymous role cannot execute the avatar functions'
);

reset role;
select * from finish();
rollback;
