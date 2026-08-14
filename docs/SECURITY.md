# Security model

## Primary threat: surprise leakage

The wishlist owner must not learn whether a specific item was reserved, how much was reserved, who reserved it, or the private note. The application never solves this by fetching rows and hiding them in SwiftUI.

Controls:

- `gift_reservations` RLS allows `SELECT` only when `reserver_id = auth.uid()`.
- Owners receive no reservation-table policy and no owner-facing reservation function.
- Availability functions return aggregate remaining quantity only to non-owner viewers with wishlist access.
- Reservation mutation functions authenticate from `auth.uid()`, use a fixed safe search path, and are granted only to `authenticated`.
- Realtime publication must exclude reservation rows; clients subscribe to safe projections and refresh aggregate availability.
- Notification policies expose events only to their recipient. Owner notification code must never create reservation-revealing events.

## Authorization principles

- Client-supplied ownership fields are ignored or rejected.
- Owner CRUD policies compare `owner_id` to `auth.uid()`.
- Selected-user access is expressed in `wishlist_members` and checked by helper functions.
- Public policies expose only public/open wishlists and wanted items.
- Link-only bearer tokens are hashed at rest, revocable, expirable, and handled through a constrained exchange path rather than interpolated into SQL.
- Profile writes are behind `public.save_my_profile`, `public.set_my_profile_avatar`, and `public.clear_my_profile_avatar`. `update` on `public.profiles` is revoked from `authenticated`, so a client cannot set `avatar_path` or `onboarding_completed` directly.
- `profile-images` is private. `storage.objects` policies allow a caller only the objects under `<auth.uid()>/`, and every other bucket, including `wishlist-images`, still has no policy and stays unreachable.

## Authentication

- Sessions live in the Supabase SDK's Keychain-backed storage. The app defines no second store and never copies an access or refresh token into presentation state, logs, or errors.
- The PKCE flow is used explicitly. A redirect is validated before the SDK sees it: the configured scheme, host `auth`, path exactly `callback`, no embedded credentials or port, and an authorization code limited to unreserved characters.
- Callback parsing never logs and never surfaces `error_description`, which can echo the address or token from the link. Only a short machine-readable `error_code` is kept.
- Sign in with Apple generates a single-use random nonce, sends only its SHA-256 digest to Apple, and gives the raw value to Supabase so the digest inside the identity token can be verified. The nonce is consumed once, so a replayed credential cannot be paired with a fresh nonce.
- Apple identity tokens are shape-checked before transmission. Signature and claim verification happen server-side in Supabase.
- Error copy is built from a closed set of cases. No server text reaches the interface, so an address, token, or database detail cannot leak through an error message.

## Profile image storage

- Object names are always `<auth.uid()>/<uuid>.<jpg|png|heic|webp>`. `private.is_own_profile_image` is the single definition, used by all four `storage.objects` policies and by `public.set_my_profile_avatar`.
- The caller is derived from the verified JWT. Neither the `owner_id` column nor a function argument can point an upload or a profile at another person's folder.
- `set_my_profile_avatar` also refuses a path that was never uploaded, so a profile cannot advertise an object the caller does not own.
- The bucket is private, capped at 5 MB, and restricted to four image MIME types. The client re-encodes every picked image to JPEG at a maximum of 1024 px before upload, which also drops the original metadata, including any location recorded by the camera.
- Replaced and removed objects are reported back by the mutation functions so the client can delete them. Cleanup failure leaves an unreferenced private object that only its owner can read.

## Account deletion

- Deletion runs in the `delete-account` Edge Function. The caller is identified only by the verified access token; the request body is ignored.
- The session must be recent. `ACCOUNT_DELETION_MAX_SESSION_AGE_SECONDS` (default 24 hours) bounds the recorded sign-in time, or the token issue time when no sign-in time exists, and an older session is refused with `recent_sign_in_required`.
- Profile images are removed through the Storage API before the auth user is deleted, because storage objects have no cascading foreign key to `auth.users`. Deleting the auth user cascades to profiles, wishlists, memberships, reservations, and notifications.
- The service-role key exists only in the function's server-side environment. It is never present in Swift code, repository files, logs, or test output.
- The interface requires an explicit destructive-action warning and a typed confirmation before the request is made.

## Function hardening

Every `security definer` function must:

- set `search_path = pg_catalog, public`;
- schema-qualify sensitive relations where practical;
- revoke default `PUBLIC` execution;
- authenticate and authorize internally;
- expose the smallest return shape; and
- avoid accepting an owner or reserver identity from the client.

## Secrets

Apple clients may contain only the Supabase URL and publishable client key. Service-role keys belong only in server-side secret stores, which for this repository means the Edge Function environment. Local values live in ignored `.xcconfig` and `.env` files. CI includes a credential-pattern scan, but review remains required.

The Gitleaks allowlist covers two deterministic, non-secret test fixtures, each scoped to one file and one exact literal shape, so a real credential added to the same file is still reported.

## Security verification matrix

The automated SQL and integration suites cover:

- owner manages only owned wishlists/items;
- unrelated users cannot read private/link-only content;
- selected members can read granted content;
- gift-givers see only their reservations;
- owners cannot read reservations for owned wishlists;
- another gift-giver cannot read identity or notes;
- expired/revoked share links validate false;
- concurrent final-unit reservations serialize and only one succeeds (verified with two independent database connections);
- a person reads only their own profile row, and direct profile updates are denied;
- display names are normalized, and blank or overlong names are rejected;
- completed onboarding cannot be reverted by a later edit;
- an upload into another person's storage folder is denied, including when the `owner_id` column claims otherwise;
- a bucket without a policy, such as `wishlist-images`, stays unreachable;
- one person cannot read or delete another person's profile image;
- a profile cannot point at an object it does not own or one that was never uploaded;
- the anonymous role cannot execute any profile function, and an unauthenticated caller is refused.

The `delete-account` request rules are unit tested without a project or a key: a missing or malformed `Authorization` header, a non-`POST` method, an abandoned session, and object names outside the caller's folder are all refused.

Storage object policies now cover `profile-images` only. `wishlist-images` remains private and unusable by clients until the wishlist image slice adds its own path-scoped policies and denial tests.

## Responsible changes

Security fixes require a new migration and regression test. Never relax a policy to make a client query convenient; add a restricted view or function that returns only the necessary projection.
