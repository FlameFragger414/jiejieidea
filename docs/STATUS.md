# Status

Last updated: 2026-08-13

## Current milestone

Authentication and profile onboarding. The slice is implemented end to end; Apple platform
compilation and the hosted-project steps below remain outstanding.

## Completed features

- Repository working agreement and initial architecture/security/database documentation.
- Credential-safe configuration examples and ignore rules.
- Reproducible Supabase local configuration, private media buckets, schema migration, and development seed data.
- RLS on every exposed application table, restricted public projections, and owner-safe reservation privacy.
- Transactional, idempotent reserve/cancel/purchase functions with final-unit row locking.
- Private reconciliation and gift-giver notification when an owner makes a reserved item unavailable.
- Shared Swift 6.1 domain package with validation, deep-link parsing, capacity rules, and safe error mapping.
- Adaptive shells: tab/navigation UI on iOS and split-view/menu UI on macOS.
- CI workflows for Apple builds, database/RLS/concurrency tests, Edge Function checks, and credential scanning.
- Email magic-link sign-in with address validation, duplicate-submission guards, and loading, sent, offline, and error states that never claim success after a failed request.
- Authentication callback handling. The redirect scheme is read from configuration, the URL is validated before the SDK sees it, and malformed or unrelated URLs are rejected.
- Native Sign in with Apple: single-use nonce generation, SHA-256 hashing, identity-token verification through Supabase, and distinct cancellation, missing-token, and rejected-credential outcomes. The button appears only when `APPLE_SIGN_IN_ENABLED` is set, so email links work without any Apple configuration.
- Session lifecycle: restoration at launch, authentication-state observation, token refresh, expiry, sign-out, and a tested reducer covering every transition including offline launches and out-of-order events.
- Profile onboarding and editing with display-name validation, optional profile image, image replacement and removal, sign-out, and account deletion.
- Private profile-image storage: an append-only migration adds the bucket, owner-scoped `storage.objects` policies, and a shared path-ownership helper. Uploads are re-encoded and resized on the device before leaving it.
- Account deletion through the `delete-account` Edge Function: JWT verification, identity derived only from the token, recent-session validation, storage cleanup, and cascading auth-user deletion.
- Sample data no longer loads during an ordinary Debug run. It is reachable only through the `-JiejieSampleData` launch argument or `JIEJIE_SAMPLE_DATA=1`.

## Partially completed features

- Wishlist management is still a shell. The dashboard reports an honest empty state instead of pretending wishlists can be created.
- Share-link creation, hashing, expiry, revocation, and parsing exist; authenticated link exchange and full client sharing UI remain.
- In-app notification storage and owner-status events exist; push delivery and preference UI remain.
- Realtime publications exclude reservations and include safe wishlist/item/recipient notification changes; client subscriptions remain.
- Profile reads are self-only. A viewer-facing projection is not needed until wishlists are shared.

## Known issues and risks

- Sign in with Apple has never been exercised against Apple's servers. The flow is implemented and unit tested, but it cannot be marked verified until the manual Apple Developer and Supabase provider steps in `docs/SETUP.md` are complete and someone signs in on a device.
- The `delete-account` Edge Function has not been deployed or invoked against a real project. Its request rules are unit tested; the deletion itself is not integration tested.
- Recent-session validation for deletion uses a 24-hour window on the recorded sign-in or token issue time. It blocks an abandoned session but is not a re-authentication challenge.
- Replaced profile images are deleted by the client after the database reports the previous path. A client that dies between the two steps leaves an unreferenced private object that only its owner can read.
- No production Apple identifiers, team, redirect URLs, associated domains, or credentials have been configured.
- `wishlist-images` is still private with no policy, so it remains unusable by clients.
- Local Apple compilation is unavailable on Linux, so the iOS and macOS builds and the `JiejieTests` bundle are verified only by GitHub Actions.

## Verification status

Performed on this change:

- `swift test --package-path Packages/WishlistCore`: 134/134 tests passed on Swift 6.1.2 for Linux.
- `swift format lint --recursive --strict App Packages`: clean.
- `swiftc -parse` over the iOS, macOS, and test source sets: passed.
- `xcodegen generate` 2.44.1: passed, including the new `JiejieTests` target.
- `supabase db reset --local`: both migrations and the seed applied.
- `supabase db lint --local --level warning`: no findings.
- `supabase test db`: 75/75 pgTAP assertions passed across two files.
- `supabase/tests/concurrent_reservation_test.py`: passed with two simultaneous connections.
- `deno fmt --check`, `deno lint`, `deno check`, and `deno test supabase/functions`: 13/13 Edge Function tests passed.
- `actionlint`: clean.
- `gitleaks detect --config .gitleaks.toml`: no leaks across full history.

Not performed here, pending GitHub Actions on a macOS runner:

- iOS simulator compilation.
- macOS compilation.
- `JiejieTests` execution, which covers `SessionController`, `ProfileModel`, and `AppConfiguration`.

Not performed at all, and not claimable:

- A real Sign in with Apple authorization.
- A real magic-link round trip through a mail client.
- A real account deletion against a deployed Edge Function.
- Any action against the hosted development project, which this change deliberately never touches.

## Manual configuration still required

- Apple Developer: real bundle identifiers, the Sign In with Apple capability on both App IDs, a Services ID with the Supabase callback return URL, and a Sign in with Apple key. Then set `APPLE_SIGN_IN_ENABLED = YES`.
- Supabase Auth: allow-list `jiejie-debug://auth/callback` and the release scheme under URL Configuration, and enable the Apple provider with the generated secret.
- Supabase Edge Functions: `supabase functions deploy delete-account`.

`docs/SETUP.md` lists each step.

## Recommended next task

Implement wishlist create, edit, reorder, archive, and delete against Supabase with realtime refresh.
The authentication and profile slice now provides a signed-in user, a profile, and the service and
view-model patterns to follow. Doing wishlists next also unblocks the `wishlist-images` bucket
policies, which mirror the profile-image ones added here.
