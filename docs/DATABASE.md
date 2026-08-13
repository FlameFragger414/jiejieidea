# Database

## Overview

The first migration establishes PostgreSQL enums, profiles, wishlists, memberships, share links, items, reservations, notifications, and device tokens. All exposed tables use RLS. Product offers and social discovery are intentionally deferred.

## Core relationships

- `profiles` extends `auth.users` one-to-one.
- `wishlists.owner_id` identifies the only owner; `wishlist_members` grants selected authenticated users viewer/editor access.
- `wishlist_share_links` stores only a SHA-256 token hash, never the bearer token itself.
- `wishlist_items` belongs to a wishlist and carries desired quantity, lifecycle status, and custom position.
- `gift_reservations` belongs to a reserver and item. Direct inserts/updates are denied; functions own mutations.
- `notifications` contains recipient-scoped events. Reservation-unavailability notifications target only affected gift-givers.

## Reservation capacity

Active capacity includes reservations with `reserved` or `purchased` state. Cancellation releases capacity. The `reserve_wishlist_item` function:

1. requires `auth.uid()`;
2. locks the item row with `FOR UPDATE`;
3. verifies the item is wanted and the wishlist is open;
4. verifies caller access without revealing existing reservations;
5. returns an existing row for a repeated idempotency key;
6. sums active quantities while the item lock serializes competing calls;
7. rejects insufficient capacity; and
8. inserts and returns only the caller-owned reservation.

Every mutation affecting desired quantity or status also locks the item row through PostgreSQL row updates. New reservations therefore cannot race an owner status change.

## Share links

The database stores a generated link ID and token hash. Application/server code presents the raw token only when it is generated. Revocation or expiry makes the link invalid immediately. A future web/deep-link exchange function will turn a valid bearer token into a constrained session claim; raw bearer tokens are not accepted in normal table policies.

## Migrations

Migrations are append-only under `supabase/migrations`. Never edit a migration already applied outside local development. Add a new timestamped migration for behavior changes.

## Development data

`supabase/seed.sql` contains explicitly non-production examples and runs only after local auth users exist. It must never contain real identities or credentials.
