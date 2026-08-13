# Backlog

Work proceeds in vertical slices. A slice includes implementation, failure states, tests, security review, and documentation.

## MVP

- [x] Establish repository conventions and architecture documents.
- [x] Establish Supabase schema, RLS, local configuration, and database tests.
- [x] Add shared Swift domain package and validation tests.
- [x] Add adaptive iOS/macOS application shells and CI build workflows.
- [ ] Implement Sign in with Apple and email magic links.
- [ ] Implement profile onboarding, editing, image upload, sign-out, and account deletion.
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
