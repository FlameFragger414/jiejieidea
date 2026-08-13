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

- `Packages/WishlistCore` owns portable domain models, validation, deep-link parsing, availability calculations, and mapped errors.
- `App/Shared` owns presentation models, dependency protocols, reusable SwiftUI screens, design tokens, and app composition.
- `App/iOS` owns tab/navigation composition and iOS-only share or haptic adapters.
- `App/macOS` owns split-view composition, commands, window behavior, and macOS-only adapters.
- Services use Swift concurrency. Views receive observable state instead of talking to Supabase directly.

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

## Architectural decisions pending

- Image cache implementation and eviction policy.
- Universal-link production host and Apple associated-domain setup.
- Push provider and Edge Function delivery pipeline.
- Whether anonymous link viewing is included before the authenticated sharing slice.
