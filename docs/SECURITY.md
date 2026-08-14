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
- Sign in with Apple generates a single-use random nonce, sends only its SHA-256 digest to Apple, and gives the raw value to Supabase so the digest inside the identity token can be verified. The nonce is consumed once, cleared when generation fails, and refused after five minutes, so neither a replayed credential nor an abandoned authorization can be paired with a stored nonce.
- Apple identity tokens are shape-checked before transmission. Signature and claim verification happen server-side in Supabase.
- Error copy is built from a closed set of cases. No server text reaches the interface, so an address, token, or database detail cannot leak through an error message. `bad_jwt` and `invalid_jwt` end the session rather than suggesting a new sign-in link, because they mean the access token is no longer usable on any call.

### Session lifecycle

The shell holds exactly one identity at a time, and every transition between identities is a barrier.

- Signing out, signing in, and a refresh that reports a different account all invalidate every outstanding operation. A refresh, a verification, a callback exchange, or a profile read that completes afterwards is recognised as superseded and discarded, so it cannot authenticate somebody who has already signed out.
- Sign-out ends the local session and moves the phase before the network call, so a slow or failed remote sign-out never leaves an account on screen that the device no longer has a session for.
- A refresh that carries a different user ID drops the previous person's profile before the new one is read, and the reducer moves to a neutral restoring phase rather than promoting the new account into the previous account's onboarding state. No profile is ever rendered under another identity.
- A refresh that arrives with no session held is ignored outright: it never triggers a profile read and never creates a session.
- A profile row whose ID does not match the authenticated caller is refused and the session is ended, even though Row Level Security should make that impossible.
- The reducer refuses the same transitions independently of the controller, so neither layer relies on the other to be correct.

### Cached sessions and offline launches

`AuthOptions.emitLocalSessionAsInitialSession` is enabled. Without it the SDK refreshes the stored session before reporting the initial one, so an offline launch reports no session and drops the person on the sign-in screen, which contradicts the unverified state the app documents and implements.

With it, the stored session is reported as it is and the app's own profile read decides the outcome:

| Situation | Reported phase |
| --------- | --------------- |
| No stored session | signed out |
| Stored session, profile read succeeds | authenticated or onboarding required |
| Stored session, device offline or the service is unreachable | unverified, with a retry and a sign-out |
| Stored session, token refused as expired or not signed in | signed out |

The token itself is still only ever validated by Supabase. A cached session grants no access on its own: every request carries the token and is authorized server-side.

## Profile image storage

- Object names are always `<auth.uid()>/<uuid>.<jpg|png|heic|webp>`. `private.is_own_profile_image` is the single definition, used by all four `storage.objects` policies and by `public.set_my_profile_avatar`.
- The caller is derived from the verified JWT. Neither the `owner_id` column nor a function argument can point an upload or a profile at another person's folder.
- `set_my_profile_avatar` also refuses a path that was never uploaded, so a profile cannot advertise an object the caller does not own.
- The bucket is private, capped at 5 MB, and restricted to four image MIME types. `20260814010000_auth_profile_security_hardening.sql` applies those settings to an existing bucket as well, so a project where `profile-images` was created by hand cannot stay public or unrestricted.
- The client re-encodes every picked image to JPEG at a maximum of 1024 px before upload, which also drops the original metadata, including any location recorded by the camera. Input above 40 MB is refused before any decoding starts, because the downscale decodes the source at full resolution first.
- Replaced and removed objects are reported back by the mutation functions so the client can delete them. Cleanup failure leaves an unreferenced private object that only its owner can read.

## Public display names

Publishing a wishlist publishes the owner's display name with it. `public.browse_public_wishlists` is granted to `anon` and returns `owner_display_name` for every public, active wishlist. Nothing else about the profile is exposed: `public.profiles` itself is unreadable to `anon` and readable only by its owner to `authenticated`, and a private or link-only wishlist exposes no name at all.

This is intentional, so it is stated where it matters rather than left implicit: onboarding and the profile editor both say the name is shown to anyone on a public wishlist, and the pgTAP suite asserts both the exposure and its limits.

## Account deletion

- Deletion runs in the `delete-account` Edge Function. The caller is identified only by the verified access token; the request body is ignored. No CORS origin is allow-listed, because the declared clients are the iOS and macOS apps and no browser client exists.
- The caller must have authenticated recently. `ACCOUNT_DELETION_MAX_SESSION_AGE_SECONDS` (default 24 hours) bounds `last_sign_in_at` on the verified user, and an older authentication is refused with `recent_sign_in_required`. Without a usable sign-in time the check fails closed.
- The access token's `iat` is deliberately not read. Supabase reissues an access token from the refresh token roughly every hour, so treating `iat` as evidence of authentication let a months-old login pass the check indefinitely.
- **What this does and does not guarantee.** It bounds how long an abandoned session can stay dangerous. It is not a reauthentication challenge: the person is not asked to prove who they are at the moment of deletion, and a device that still holds a valid session within the window can delete the account without any further interaction. It also depends on GoTrue's own bookkeeping — some GoTrue versions update `last_sign_in_at` when a legacy refresh token is rotated — so the window is a staleness bound rather than a proof of recent human authentication. A genuine reauthentication step is tracked in `docs/BACKLOG.md`.
- Profile images are removed through the Storage API before the auth user is deleted, because storage objects have no cascading foreign key to `auth.users`. Every page is processed, not just the first, and every path is re-checked against the caller's own prefix before it is deleted.
- The operation cannot be transactional across Storage and Auth, so it is ordered and idempotent instead. Cleanup lists from the start of the folder on every round, which means deleting never shifts an object out of view and a retry simply resumes from whatever is still stored. An auth user that is already gone is treated as success so a retry can finish.
- No partial outcome is reported as success. If any object may remain, the function returns `502 storage_cleanup_failed` and leaves the auth user in place, because that row is what still ties the remaining objects to somebody who can retry.
- The service-role key exists only in the function's server-side environment. It is never present in Swift code, repository files, logs, or test output.
- The interface requires an explicit destructive-action warning and a typed confirmation before the request is made. A completed deletion is terminal: the request cannot re-enter the deleting state, and the confirmation sheet cannot be swiped away while a deletion is running.

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

The Gitleaks allowlist covers two deterministic, non-secret test fixtures. Each entry allows one exact literal, written with the declaration syntax of the language it appears in, so neither entry can match the other fixture's file and any other credential-shaped string in the same file is still reported.

The entries deliberately do not use `paths`. In Gitleaks 8.x a global allowlist whose `paths` match causes the whole file to be skipped before any rule runs, even with `condition = "AND"`, so a path-scoped entry hides every future credential in that file rather than only the fixture. This was verified against Gitleaks 8.28.0 by planting an `sk_live_...` string in `DeepLinkTests.swift`: the path-scoped form did not report it, and the exact-literal form did. The scan runs against a pinned Gitleaks version so the allowlist is always evaluated by the version it was verified with.

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
- the anonymous role cannot execute any profile function, and an unauthenticated caller is refused;
- a public wishlist exposes its owner's display name to anonymous callers, a private or link-only one does not, and `public.profiles` stays unreadable to `anon`;
- the corrective migration forces an existing public, unlimited `profile-images` bucket back to private with its size and MIME limits, is idempotent, and produces the same settings on a database that has no bucket yet.

The `delete-account` request rules are unit tested without a project or a key: a missing or malformed `Authorization` header, a non-`POST` method, an abandoned session, a months-old login carrying a freshly refreshed token, object names outside the caller's folder, folder placeholders, and every collection size from zero to several pages are all handled. Listing failures, removal failures, a folder that cannot shrink, and an already-deleted auth user are covered too.

Storage object policies now cover `profile-images` only. `wishlist-images` remains private and unusable by clients until the wishlist image slice adds its own path-scoped policies and denial tests.

## Responsible changes

Security fixes require a new migration and regression test. Never relax a policy to make a client query convenient; add a restricted view or function that returns only the necessary projection.
