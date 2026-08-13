# Repository working agreement

These instructions apply to the entire repository.

## Product boundaries

- Build the secure wishlist MVP before price comparison or social features.
- Treat gift reservations as sensitive. Never expose reservation identity, item association, quantity, or notes to the wishlist owner.
- Enforce authorization and concurrency in PostgreSQL. SwiftUI visibility is not a security boundary.
- Never commit Supabase secret/service-role keys, signing credentials, real bundle identifiers, or production redirect URLs.

## Workflow

1. Read `docs/STATUS.md` and select the smallest complete vertical slice.
2. Inspect existing migrations before changing the database. Never rewrite an applied migration; add a new one.
3. Keep shared domain logic in `Packages/WishlistCore` when it can be platform independent.
4. Isolate platform-specific SwiftUI code in `App/iOS` and `App/macOS`.
5. Update architecture, database, security, setup, and status documents when decisions change.
6. Add tests for business rules and expected authorization denials.
7. Make focused commits and avoid unrelated formatting changes.

## Verification

- Run `swift test --package-path Packages/WishlistCore` when Swift is available.
- Run `supabase db reset` and the SQL test suite when Docker and Supabase CLI are available.
- Run `deno check` for every Edge Function.
- Generate the project with `xcodegen generate`, then build both simulator targets on macOS.
- Do not claim Apple compilation passed without Xcode output.

## Swift conventions

- Swift 6 language mode; strict concurrency warnings should remain actionable.
- Prefer value types, `Sendable`, explicit error mapping, and dependency injection.
- Use `async/await`; do not introduce callback-only service APIs.
- Keep user-facing copy plain, specific, and accessible.
- Support Dynamic Type, VoiceOver, reduced motion, light mode, and dark mode.

## SQL conventions

- Use `uuid` primary keys, `timestamptz`, foreign keys, checks, and useful indexes.
- Enable RLS on every table in exposed schemas.
- Set a safe `search_path` on every `security definer` function.
- Derive the caller from `auth.uid()`; never trust a client-supplied owner ID.
- Revoke broad function execution and grant only the intended roles.
- Keep reservation writes behind database functions and lock the wishlist item row before checking availability.
