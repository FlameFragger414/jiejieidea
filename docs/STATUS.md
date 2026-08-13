# Status

Last updated: 2026-08-13

## Current milestone

Milestone 1 — repository and documentation foundation (in progress).

## Completed features

- Repository working agreement and initial architecture/security/database documentation.
- Credential-safe configuration examples and ignore rules.

## Partially completed features

- Supabase schema, RLS, reservation functions, Swift core, app shells, and CI are planned for this foundation branch.

## Known issues

- No production Apple identifiers, team, redirect URLs, associated domains, or credentials have been configured.
- No Storage policies or media upload implementation exists yet.
- Link bearer-token exchange and authenticated selected-user invitation flows are not yet implemented.

## Blockers

- Apple builds require macOS with Xcode.
- Full database and RLS verification requires Supabase CLI/Docker or a PostgreSQL environment with Supabase auth roles/extensions.

## Verification status

- Documentation reviewed against the MVP brief.
- Implementation verification pending.

## Recommended next task

Complete the Supabase foundation migration and automated authorization/reservation tests.
