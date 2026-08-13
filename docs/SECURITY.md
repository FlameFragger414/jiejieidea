# Security model

## Primary threat: surprise leakage

The wishlist owner must not learn whether a specific item was reserved, how much was reserved, who reserved it, or the private note. The application never solves this by fetching rows and hiding them in SwiftUI.

Controls:

- `gift_reservations` RLS allows `SELECT` only when `reserver_id = auth.uid()`.
- Owners receive no reservation-table policy and no owner-facing reservation function.
- Availability functions return aggregate remaining quantity only to non-owner viewers with wishlist access.
- Reservation mutation functions authenticate from `auth.uid()`, use a fixed safe search path, and are granted only to `authenticated`.
- Realtime publication must exclude reservation rows; clients subscribe to safe projections and refresh aggregate availability.
- Notification policies expose events only to their recipient. Owner notification code must never create reservation-revealing events.

## Authorization principles

- Client-supplied ownership fields are ignored or rejected.
- Owner CRUD policies compare `owner_id` to `auth.uid()`.
- Selected-user access is expressed in `wishlist_members` and checked by helper functions.
- Public policies expose only public/open wishlists and wanted items.
- Link-only bearer tokens are hashed at rest, revocable, expirable, and handled through a constrained exchange path rather than interpolated into SQL.
- Storage buckets and object policies will be added with the profile/cover-image vertical slice; no public bucket is assumed.

## Function hardening

Every `security definer` function must:

- set `search_path = pg_catalog, public`;
- schema-qualify sensitive relations where practical;
- revoke default `PUBLIC` execution;
- authenticate and authorize internally;
- expose the smallest return shape; and
- avoid accepting an owner or reserver identity from the client.

## Secrets

Apple clients may contain only the Supabase URL and publishable client key. Service-role keys belong only in server-side secret stores. Local values live in ignored `.xcconfig` and `.env` files. CI includes a credential-pattern scan, but review remains required.

## Security verification matrix

The automated SQL and integration suites cover:

- owner manages only owned wishlists/items;
- unrelated users cannot read private/link-only content;
- selected members can read granted content;
- gift-givers see only their reservations;
- owners cannot read reservations for owned wishlists;
- another gift-giver cannot read identity or notes;
- expired/revoked share links validate false;
- concurrent final-unit reservations serialize and only one succeeds (verified with two independent database connections).

Storage object policies are not marked complete. Buckets are private and unusable by clients until the profile/image vertical slice adds path-scoped policies and denial tests.

## Responsible changes

Security fixes require a new migration and regression test. Never relax a policy to make a client query convenient; add a restricted view or function that returns only the necessary projection.
