# Architecture

## Goals

Jiejie uses a shared Swift domain package, thin platform-adaptive SwiftUI applications, and Supabase as the source of truth. The architecture is designed around one non-negotiable invariant: wishlist owners cannot learn reservation details.

## System boundaries

```text
iOS NavigationStack / tabs       macOS NavigationSplitView / menus
              \                    /
               Shared SwiftUI features
                         |
                  WishlistCore package
             models | validation | deep links
                         |
               async Supabase services
                         |
              RLS + restricted views/RPC
                         |
                 PostgreSQL transactions
```

### Client

- `Packages/WishlistCore` owns portable domain models, validation, deep-link and authentication-callback parsing, the authentication phase reducer, nonce generation and hashing, availability calculations, and mapped errors.
- `App/Shared` owns presentation models, dependency protocols, reusable SwiftUI screens, design tokens, and app composition.
- `App/iOS` owns tab/navigation composition, the photo-library picker, and iOS-only share or haptic adapters.
- `App/macOS` owns split-view composition, commands, window behavior, the open-panel picker, and macOS-only adapters.
- `App/Tests` holds logic tests for the shared services and view models. They compile the shared sources directly and run on a macOS runner without a host app or a simulator.
- Services use Swift concurrency. Views receive observable state instead of talking to Supabase directly.

## Authentication and profile flow

```text
SignInView / SignInWithAppleButton
              |
       SessionController  ──  AuthenticationStateMachine (pure, tested)
        |            |
AuthenticationService  ProfileService
        |                    |
   Supabase Auth      PostgREST + Storage + Edge Function
```

- `SessionController` is the only owner of the authentication phase. Views observe it and never call the SDK.
- Phase transitions run through `AuthenticationStateMachine`, a value type in `WishlistCore`, so orderings such as a refresh arriving after a sign-out are covered by tests rather than implied by view code.
- Session persistence belongs to the Supabase SDK. On Apple platforms its default local storage is `KeychainLocalStorage` and token refresh is automatic, so the app adds no second store and keeps no token in presentation state.
- The PKCE flow is explicit. `AuthenticationCallbackParser` validates a redirect before the SDK sees it: the scheme comes from `AUTH_REDIRECT_SCHEME`, the host must be `auth`, the path must be exactly `callback`, and the authorization code must look like an unreserved token.
- Sign in with Apple generates a single-use nonce, sends the SHA-256 digest to Apple, and gives the raw value to Supabase for verification. The button is shown only when `APPLE_SIGN_IN_ENABLED` is set, so the email flow works before Apple configuration exists.
- Profile writes go through security-definer functions. The client never sends an owner ID, and avatar object names are derived from the signed-in user's ID.
- Account deletion runs in the `delete-account` Edge Function, which is the only place a service-role key exists.

### Shell states

`AuthenticationPhase` has one case per state the shell can be in: restoring a stored session, signed out, a sign-in in progress, signed in but onboarding incomplete, fully onboarded, and "a session may exist but cannot be verified" for the offline case. `AuthenticationGate` maps each to exactly one screen.

### Backend

- PostgreSQL tables store authoritative state.
- RLS protects rows for direct client reads and owner CRUD.
- Security-definer functions are narrowly granted and perform sensitive reads/writes.
- Reservation capacity is calculated while holding a row lock on the requested item.
- Gift-givers see aggregate availability; reservation rows remain visible only to the reserver.
- Realtime subscriptions must target non-sensitive wishlist/item projections, never `gift_reservations`.

## Data flow: reserve a gift

1. An authenticated viewer opens a wishlist they may access.
2. The client reads item presentation data and safe aggregate availability.
3. The client calls `reserve_wishlist_item` with quantity, optional note, and an idempotency key.
4. PostgreSQL authenticates the caller, locks the item, rechecks access/status/capacity, inserts the reservation, and returns only the caller's reservation result.
5. Realtime invalidation refreshes aggregate availability. A reconnect performs a full authoritative refresh.

## Offline behavior

Non-sensitive wishlist content may be cached in a later vertical slice. Reservation requests are never confirmed locally. Owner edits may enter an explicit pending state, but retryable mutations need stable idempotency keys before automatic retries are enabled.

## Dependency policy

The Apple apps use the official Supabase Swift SDK through Swift Package Manager. Domain tests do not import Supabase, SwiftUI, UIKit, or AppKit. XcodeGen keeps project configuration reviewable and reduces project-file merge conflicts.

`WishlistCore` has no external dependencies. SHA-256 uses CryptoKit on Apple platforms, with a portable implementation compiled only where CryptoKit is unavailable so the package also builds without it. Both paths are checked against the published FIPS 180-4 vectors. CI runs the package tests on `macos-15` only, so the CryptoKit path is the one CI exercises; the portable path is covered by a local Linux toolchain when one is available.

## Architectural decisions pending

- Wishlist persistence. `AppModel` currently reports an honest empty state; sample content is reachable only through the opt-in development mode.
- Image cache implementation and eviction policy.
- Universal-link production host and Apple associated-domain setup.
- Push provider and Edge Function delivery pipeline.
- Whether anonymous link viewing is included before the authenticated sharing slice.
