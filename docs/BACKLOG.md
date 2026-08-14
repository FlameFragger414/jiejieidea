# Backlog

Work proceeds in vertical slices. A slice includes implementation, failure states, tests, security review, and documentation.

## MVP

- [x] Establish repository conventions and architecture documents.
- [x] Establish Supabase schema, RLS, local configuration, and database tests.
- [x] Add shared Swift domain package and validation tests.
- [x] Add adaptive iOS/macOS application shells and CI build workflows.
- [x] Implement Sign in with Apple and email magic links. Apple sign-in is implemented and unit tested but stays hidden until the manual Apple and Supabase configuration is done.
- [x] Implement profile onboarding, editing, image upload, sign-out, and account deletion. Deletion needs the Edge Function deployed before it can succeed against a hosted project.
- [x] Harden the authentication and profile slice: session identity, callback parsing, deletion freshness, and complete profile-image cleanup.
- [ ] Require a genuine reauthentication before account deletion. The current control bounds how stale the last authentication may be, which is not the same as asking the person to prove who they are at the moment of deletion. Reauthenticating through a fresh magic link or Apple assertion, or reading the session creation time from `auth.sessions` rather than `last_sign_in_at`, would close the gap.
- [ ] Implement wishlist create/edit/reorder/archive/delete with realtime refresh.
- [ ] Implement item create/edit/reorder/status transitions and URL metadata review.
- [ ] Implement revocable/expiring share links, selected users, and deep-link routing.
- [ ] Implement gift-giver availability, reservation, cancellation, purchase marking, and history.
- [ ] Implement in-app notifications and affected-reserver status notifications.
- [ ] Implement Apple push registration and per-category preferences.
- [ ] Add offline read cache and explicit pending owner edits.
- [ ] Complete accessibility, reduced motion, localization readiness, and UI polish.
- [ ] Run full security, concurrency, Apple platform, and credential verification.

## Deferred until MVP verification

- [ ] Price-comparison provider interface and scheduled offer refresh.
- [ ] Product discovery feed, creator profiles, collections, and engagement.
- [ ] Affiliate attribution and disclosure.

## Explicitly not placeholders

Screens and controls enter production navigation only when their action is functional. Future destinations may be documented or represented in development previews, but must not ship as inert buttons.
