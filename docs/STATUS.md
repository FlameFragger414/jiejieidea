# Status

Last updated: 2026-08-13

## Current milestone

Milestones 1–3 and foundation work from milestones 5–7 are complete. The next active milestone is authentication and profiles.

## Completed features

- Repository working agreement and initial architecture/security/database documentation.
- Credential-safe configuration examples and ignore rules.
- Reproducible Supabase local configuration, private media buckets, schema migration, and development seed data.
- RLS on every exposed application table, restricted public projections, and owner-safe reservation privacy.
- Transactional, idempotent reserve/cancel/purchase functions with final-unit row locking.
- Private reconciliation and gift-giver notification when an owner makes a reserved item unavailable.
- Shared Swift 6.1 domain package with validation, deep-link parsing, capacity rules, and safe error mapping.
- Adaptive debug shells: tab/navigation UI on iOS and split-view/menu UI on macOS.
- CI workflows for Apple builds, database/RLS/concurrency tests, Edge Function checks, and credential scanning.

## Partially completed features

- App shells use functional development-only in-memory data. Release builds do not pretend that unimplemented authentication or persistence works.
- Share-link creation, hashing, expiry, revocation, and parsing exist; authenticated link exchange and full client sharing UI remain.
- In-app notification storage and owner-status events exist; push delivery and preference UI remain.
- Realtime publications exclude reservations and include safe wishlist/item/recipient notification changes; client subscriptions remain.

## Known issues

- No production Apple identifiers, team, redirect URLs, associated domains, or credentials have been configured.
- Private Storage buckets exist, but object policies and media upload flows are intentionally deferred to the profile/image slice.
- Link bearer-token exchange and authenticated selected-user invitation flows are not yet implemented.
- Authentication, account deletion, and all persistent application services are not yet implemented.

## Blockers

- Local Apple compilation remains unavailable on this Windows host because Xcode and Apple SDKs require macOS. GitHub Actions performs both builds, which pass with Xcode 16.4.

## Verification status

- `supabase db reset --local`: passed with migration and development seed.
- `supabase db lint --local --level warning`: passed with zero findings.
- `supabase test db`: 31/31 pgTAP assertions passed.
- `supabase/tests/concurrent_reservation_test.py`: passed with two simultaneous connections; exactly one final-unit reservation succeeded.
- `swift test --package-path Packages/WishlistCore`: 30/30 tests passed in the Swift 6.1 Linux container.
- `swift format`: shared package and app sources formatted.
- XcodeGen 2.44.1 project generation: passed in the Swift Linux container.
- iOS and macOS source-set parser checks: passed.
- GitHub workflow `actionlint`: passed.
- Gitleaks full-history scan: passed with no leaks; one deterministic test-token fixture has a path-and-pattern-scoped allowlist.
- Full iOS/macOS semantic builds: passed in GitHub Actions with Xcode 16.4; not runnable locally on this Windows host.

## Recommended next task

Implement authentication and profile onboarding as one vertical slice: Sign in with Apple, email magic links, Keychain-backed Supabase session restoration, profile completion/editing, useful failure states, and service/view-model tests.
