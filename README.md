# Jiejie

Jiejie is a privacy-first wishlist and gift-coordination app for iPhone and Mac. People can create multiple wishlists, share them securely, and let friends reserve gifts without revealing the surprise to the wishlist owner.

This repository currently contains the MVP foundation:

- a versioned Supabase schema with Row Level Security (RLS)
- transactional reservation functions that prevent duplicate final-unit reservations
- a platform-independent Swift domain package with tests
- adaptive SwiftUI application shells for iOS and macOS
- local-development configuration and CI checks

The implementation is deliberately incremental. Price comparison and social discovery remain out of scope until the secure wishlist MVP is complete.

## Repository map

```text
App/                       Shared and platform-specific SwiftUI code
Config/                    Credential-safe Xcode configuration examples
Packages/WishlistCore/     Portable models, validation, and business logic
supabase/                  Migrations, Edge Functions, seed data, and SQL tests
docs/                      Architecture, security, database, setup, and status
.github/workflows/         Apple, backend, and credential CI checks
project.yml                XcodeGen project definition
```

## Getting started

1. Read [docs/SETUP.md](docs/SETUP.md).
2. Copy the example Xcode configuration files locally; never commit populated credentials.
3. Start the local Supabase stack and reset the database.
4. Generate the Xcode project with XcodeGen.
5. Run the Swift package tests and open the generated workspace in Xcode.

Current progress and the recommended next vertical slice are tracked in [docs/STATUS.md](docs/STATUS.md).

## Security posture

Reservation privacy is a database invariant, not a presentation choice. The owner cannot select gift reservation records through the client API. Availability is exposed through restricted views/functions, and mutations run through server-side transactional functions. See [docs/SECURITY.md](docs/SECURITY.md).

## License

No license has been selected yet. All rights are reserved unless the repository owner adds one.
