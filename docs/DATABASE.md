# Database

## Overview

The first migration establishes PostgreSQL enums, profiles, wishlists, memberships, share links, items, reservations, notifications, and device tokens. All exposed tables use RLS. Product offers and social discovery are intentionally deferred.

## Core relationships

- `profiles` extends `auth.users` one-to-one. `private.handle_new_user` creates the row with a seeded `display_name` of `New member` until onboarding replaces it.
- `wishlists.owner_id` identifies the only owner; `wishlist_members` grants selected authenticated users viewer/editor access.
- `wishlist_share_links` stores only a SHA-256 token hash, never the bearer token itself.
- `wishlist_items` belongs to a wishlist and carries desired quantity, lifecycle status, and custom position.
- `gift_reservations` belongs to a reserver and item. Direct inserts/updates are denied; functions own mutations.
- `notifications` contains recipient-scoped events. Reservation-unavailability notifications target only affected gift-givers.

## Reservation capacity

Active capacity includes reservations with `reserved` or `purchased` state. Cancellation releases capacity. The `reserve_wishlist_item` function:

1. requires `auth.uid()`;
2. locks the item row with `FOR UPDATE`;
3. verifies the item is wanted and the wishlist is open;
4. verifies caller access without revealing existing reservations;
5. returns an existing row for a repeated idempotency key;
6. sums active quantities while the item lock serializes competing calls;
7. rejects insufficient capacity; and
8. inserts and returns only the caller-owned reservation.

Every mutation affecting desired quantity or status also locks the item row through PostgreSQL row updates. New reservations therefore cannot race an owner status change.

## Profiles and profile images

`20260813020000_profile_onboarding_and_avatars.sql` moves every profile write behind a
security-definer function and opens the `profile-images` bucket to its owner only.

- `update` on `public.profiles` is revoked from `authenticated`. The `profiles_update_self` policy
  stays in place for any future column-level grant, but no client-side update path exists today.
- `public.save_my_profile(p_display_name, p_complete_onboarding)` normalizes whitespace, enforces the
  1–80 character rule, and can set `onboarding_completed` but never clear it.
- `public.set_my_profile_avatar(p_object_name)` accepts only an object the caller owns and that
  actually exists in `storage.objects`. It returns the previous path as `replaced_avatar_path` so the
  client can delete the object it replaced.
- `public.clear_my_profile_avatar()` removes the reference and reports the previous path the same way.
- All three return the same row shape, including `replaced_avatar_path`, so one Swift type decodes
  every profile mutation.
- `private.is_own_profile_image(p_object_name)` is the single definition of a legitimate object name:
  `<auth.uid()>/<uuid>.<jpg|png|heic|webp>`, with no nested folders and no traversal. The four
  `storage.objects` policies and `set_my_profile_avatar` all use it.
- The migration also inserts the private `profile-images` bucket with a 5 MB limit and a four-entry
  MIME allow list, so a hosted deployment gets the same bucket from migrations alone. The insert is
  `on conflict do nothing`, and `supabase db reset` reconciles it with `supabase/config.toml`.

`storage.objects` blocks direct `DELETE` with the `protect_objects_delete` trigger unless
`storage.allow_delete_query` is set. Application deletes go through the Storage API; the pgTAP suite
sets the flag inside its transaction to exercise the delete policy.

## Account deletion

There is no SQL entry point for account deletion. The `delete-account` Edge Function verifies the
caller's JWT, removes their storage objects, and calls `auth.admin.deleteUser`, which cascades to
`profiles`, `wishlists`, `wishlist_members`, `gift_reservations`, `notifications`, and
`device_tokens` through the foreign keys declared in the initial migration.

## Share links

The database stores a generated link ID and token hash. Application/server code presents the raw token only when it is generated. Revocation or expiry makes the link invalid immediately. A future web/deep-link exchange function will turn a valid bearer token into a constrained session claim; raw bearer tokens are not accepted in normal table policies.

## Migrations

Migrations are append-only under `supabase/migrations`. Never edit a migration already applied outside local development. Add a new timestamped migration for behavior changes.

| Migration                                        | Contents                                                              |
| ------------------------------------------------ | --------------------------------------------------------------------- |
| `20260813010000_initial_mvp_foundation.sql`      | Enums, tables, RLS, reservation functions. Applied; never edit.       |
| `20260813020000_profile_onboarding_and_avatars.sql` | Profile write functions, `profile-images` bucket, storage policies. |

## Development data

`supabase/seed.sql` contains explicitly non-production examples and runs only after local auth users exist. It must never contain real identities or credentials.
