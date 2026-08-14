begin;

-- Covers 20260814010000_auth_profile_security_hardening.sql.
--
-- The earlier migration created the `profile-images` bucket with `on conflict (id) do nothing`, so
-- a project that already had a bucket with that id kept whatever settings it had. These assertions
-- pin both halves of the corrective behaviour: the settled state after a clean reset, and the
-- repair applied to a bucket that already existed with unsafe settings.

create extension if not exists pgtap with schema extensions;
select plan(16);

-- The state a clean `supabase db reset` must leave behind.
select is(
  (select public from storage.buckets where id = 'profile-images'),
  false,
  'a migrated database has a private profile image bucket'
);
select is(
  (select file_size_limit from storage.buckets where id = 'profile-images'),
  5242880::bigint,
  'a migrated database caps profile image size'
);
select is(
  (select allowed_mime_types from storage.buckets where id = 'profile-images'),
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp'],
  'a migrated database restricts profile image MIME types'
);

-- Every policy the slice depends on survives the re-declaration in the corrective migration.
select policies_are(
  'storage',
  'objects',
  array[
    'profile_images_select_own',
    'profile_images_insert_own',
    'profile_images_update_own',
    'profile_images_delete_own'
  ],
  'profile-images is the only bucket with storage policies'
);
select is(
  (select count(*) from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and 'authenticated' = any(roles)),
  4::bigint,
  'every profile image policy is granted only to authenticated callers'
);

-- Simulate a hosted project where `profile-images` was created by hand before the migrations ran:
-- public, unlimited, and accepting any content type.
update storage.buckets
set public = true,
    file_size_limit = null,
    allowed_mime_types = null
where id = 'profile-images';

select is(
  (select public from storage.buckets where id = 'profile-images'),
  true,
  'the unsafe bucket state used by this test was applied'
);

-- The statement below is the one in 20260814010000. It must repair the bucket rather than skip it.
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

select is(
  (select public from storage.buckets where id = 'profile-images'),
  false,
  'an existing public bucket is forced private'
);
select is(
  (select file_size_limit from storage.buckets where id = 'profile-images'),
  5242880::bigint,
  'an existing bucket without a size ceiling is given one'
);
select is(
  (select allowed_mime_types from storage.buckets where id = 'profile-images'),
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp'],
  'an existing bucket without a MIME allow list is given one'
);
select is(
  (select count(*) from storage.buckets where id = 'profile-images'),
  1::bigint,
  'the corrective statement never creates a second bucket row'
);

-- Applying it a second time changes nothing, so a re-run or a partially applied deploy is safe.
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

select is(
  (select public from storage.buckets where id = 'profile-images'),
  false,
  'the corrective statement is idempotent'
);

-- The same statement on a database that has no bucket yet takes the insert path. Storage guards
-- direct deletes with a trigger, so the escape hatch it provides is set for this transaction only.
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects where bucket_id = 'profile-images';
delete from storage.buckets where id = 'profile-images';
select is(
  (select count(*) from storage.buckets where id = 'profile-images'),
  0::bigint,
  'the fresh-database state used by this test was applied'
);

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

select is(
  (select public from storage.buckets where id = 'profile-images'),
  false,
  'a newly created bucket is private'
);
select is(
  (select file_size_limit from storage.buckets where id = 'profile-images'),
  5242880::bigint,
  'a newly created bucket caps object size'
);
select is(
  (select allowed_mime_types from storage.buckets where id = 'profile-images'),
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp'],
  'a newly created bucket restricts MIME types'
);

-- The other declared bucket is untouched by the corrective migration and still has no policy.
select is(
  (select public from storage.buckets where id = 'wishlist-images'),
  false,
  'the wishlist image bucket is left private and unchanged'
);

select * from finish();
rollback;
