# Status

Last updated: 2026-08-14

## Current milestone

Authentication and profile onboarding, plus the security hardening of that slice. The
feature work is implemented end to end and the blocking findings raised against it are
fixed. Remaining work is hosted-project configuration (Apple Sign In, Auth redirect
allow-list, and deploying `delete-account`), not further client or schema work for this
milestone.

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

## Security hardening of the authentication slice

Blocking fixes:

- Session resurrection and identity mixing. Every identity transition invalidates outstanding work, so a refresh, verification, callback exchange, or profile read that completes after a sign-out is discarded instead of signing somebody back in. A refresh carrying a different user ID drops the previous profile before the new one is read, and the reducer moves to a neutral phase so no profile is ever shown under another identity. Regression tests are gated rather than timed: sign-out during an in-flight profile read, sign-out during an in-flight verification, a late refresh event, a cross-account refresh, and two overlapping operations settling out of order.
- Authentication callback parsing. The decoded fragment is no longer assigned back to `percentEncodedQuery`, which trapped on ordinary input such as `%20`. Query and fragment are decoded with the same rules and precedence the Supabase Swift SDK uses, so a redirect this parser accepts is one the SDK can complete. Covered by query, fragment, encoded-percent, malformed-escape, duplicate-field, precedence, and seeded fuzz tests.
- Recent-sign-in validation for account deletion. Only the verified user's `last_sign_in_at` is read, and it fails closed without one. The access token's `iat` is not read at all, so an automatic refresh can no longer make a months-old login look recent. The test that approved that bypass is gone, replaced by one that rejects it.
- Profile-image cleanup during account deletion. Every owned object is removed, not only the first hundred. Pagination is bounded, folder placeholders are never mistaken for objects, each path is re-checked against the caller's prefix, and any incomplete outcome is reported as a failure with the auth user left in place rather than claimed as a deletion.

Important hardening:

- A new append-only migration forces an existing `profile-images` bucket private with its size and MIME limits, and re-declares the four owner-scoped storage policies idempotently. Neither existing migration is modified.
- Expired cached sessions and offline launches now behave as documented. The SDK emits the stored session as the initial one, so an offline launch reaches the unverified state instead of the sign-in screen.
- `bad_jwt` and `invalid_jwt` map to session expiry, so a stale token ends the session instead of leaving signed-in UI that cannot read anything. `validation_failed` no longer blames the email field on screens that have none, and cancellation has a provider-neutral case.
- The Gitleaks allowlist matches exact fixture literals. Path-scoped entries were removed because a global allowlist with matching paths skips the whole file in Gitleaks 8.x, which hid every future credential in those two files.
- Image input above 40 MB is refused before decoding, and macOS file reads and their size checks run off the main actor.
- Public display-name exposure is stated in onboarding, in the profile editor, in `docs/SECURITY.md`, and asserted in pgTAP.
- A failed Apple nonce generation clears any pending nonce, an unused one expires after five minutes, and a failure to prepare one is reported instead of silently running an unprotected request.
- A deleted account-deletion request cannot re-enter the deleting state, and the confirmation sheet cannot be dismissed mid-deletion.
- `AppConfiguration` validates the redirect scheme once and stores the parser, removing the `try!` that could trap on any directly constructed value.
- Dependencies are pinned: `supabase-swift`, the Edge Function JSR specifiers, the Supabase CLI, Deno, Gitleaks, and Xcode. XcodeGen is documented as a deliberate exception.

## Partially completed features

- Wishlist management is still a shell. The dashboard reports an honest empty state instead of pretending wishlists can be created.
- Share-link creation, hashing, expiry, revocation, and parsing exist; authenticated link exchange and full client sharing UI remain.
- In-app notification storage and owner-status events exist; push delivery and preference UI remain.
- Realtime publications exclude reservations and include safe wishlist/item/recipient notification changes; client subscriptions remain.
- Profile reads are self-only. A viewer-facing projection is not needed until wishlists are shared.

## Known issues and risks

- Sign in with Apple has never been exercised against Apple's servers. The flow is implemented and unit tested, but it cannot be marked verified until the manual Apple Developer and Supabase provider steps in `docs/SETUP.md` are complete and someone signs in on a device.
- The `delete-account` Edge Function has not been deployed or invoked against a real project. Its request rules and its storage-cleanup loop are unit tested against an in-memory storage double; the deletion itself is not integration tested, so the pagination fix is proven by unit tests rather than against a real bucket holding more than 100 objects.
- Recent-session validation for deletion bounds `last_sign_in_at` to a 24-hour window. It blocks an abandoned session and no longer accepts a refreshed token's issue time, but it is still not a reauthentication challenge: a device holding a valid session inside the window can delete the account without proving who is holding it. Some GoTrue versions also update `last_sign_in_at` when a legacy refresh token is rotated, so the window is a staleness bound rather than proof of recent human authentication.
- Replaced profile images are deleted by the client after the database reports the previous path. A client that dies between the two steps leaves an unreferenced private object that only its owner can read.
- The session identity work is verified through `SessionController` and the reducer. The SwiftUI wiring that keys the signed-in shell by account, and that forwards a re-read profile into the profile model, is reviewed rather than covered by a UI test.
- No production Apple identifiers, team, redirect URLs, associated domains, or credentials have been configured.
- `wishlist-images` is still private with no policy, so it remains unusable by clients.
- Local Apple compilation is unavailable on Linux. iOS and macOS compilation and the
  `JiejieTests` bundle are verified by GitHub Actions on `macos-15` with Xcode 16.4.

## Verification status

Performed locally on this change (Linux, Swift 6.1.2, Supabase CLI 2.114.0, Deno 2.9.5,
Gitleaks 8.28.0):

- `swift test --package-path Packages/WishlistCore`: 160/160 tests passed.
- `swift format lint --recursive --strict App Packages`: clean.
- `supabase db reset --local`: all three migrations and the seed applied.
- `supabase db lint --local --level warning`: no findings.
- `supabase test db`: 94/94 pgTAP assertions passed across three files.
- `supabase/tests/concurrent_reservation_test.py`: passed with two simultaneous connections.
- `deno fmt --check`, `deno lint`, `deno check` on every `.ts` file, and `deno test supabase/functions`: 23/23 Edge Function tests passed.
- `actionlint`: clean.
- `gitleaks detect --config .gitleaks.toml`: no leaks across full history. The allowlist was also checked by planting an `sk_live_...` string in each fixture file and confirming both were reported.

GitHub Actions on this branch (`macos-15`, Xcode 16.4):

- WishlistCore tests: passed.
- Build iOS (`Jiejie-iOS`, iOS Simulator, unsigned Debug): passed.
- Build macOS (`Jiejie-macOS`, unsigned Debug): passed.
- `JiejieTests` (`SessionController`, `ProfileModel`, `AppConfiguration`): 58/58 passed, including the six gated session-lifecycle regressions.
- Backend verification (reset, lint, pgTAP, concurrency, Deno fmt/lint/check/test): passed.
- Credential safety scan: passed.

Not performed at all, and not claimable:

- A real Sign in with Apple authorization.
- A real magic-link round trip through a mail client.
- A real account deletion against a deployed Edge Function, so the profile-image pagination fix is proven against an in-memory storage double rather than a real bucket with more than 100 objects.
- Any action against the hosted development project, which this change deliberately never touches. No migration and no Edge Function was deployed.
- Any manual interaction with the running apps. Apple compilation and the app tests come from GitHub Actions output; nothing was run on a simulator or a device.

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

Before that, or alongside it, the account-deletion reauthentication item in `docs/BACKLOG.md` is the
one remaining security gap this hardening pass bounded rather than closed.
