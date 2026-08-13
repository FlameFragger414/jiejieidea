# Local setup

## Prerequisites

- macOS with the current stable Xcode for Apple app work
- XcodeGen
- Swift toolchain (included with Xcode)
- Docker Desktop
- Supabase CLI
- Deno 2.x for Edge Functions
- Git

## 1. App configuration

Copy configuration examples without committing the populated files:

```sh
cp Config/Debug.example.xcconfig Config/Debug.xcconfig
cp Config/Release.example.xcconfig Config/Release.xcconfig
```

Replace placeholder values with your Supabase URL, publishable key, chosen bundle identifiers, redirect scheme, and share-link host. Only a publishable/anon client key is valid in these files. Never use a secret or service-role key.

Manual values intentionally not invented by this repository:

- Apple Developer Team ID
- iOS/macOS bundle IDs and App Group ID
- Sign in with Apple capability and service configuration
- production redirect URL and custom URL scheme
- universal-link domain and `apple-app-site-association` file
- production Supabase project reference and keys

## 2. Local Supabase

```sh
supabase start
supabase db reset --local
supabase status
```

The reset applies all migrations and development seed data. To run pgTAP tests:

```sh
supabase test db
```

To run the real two-connection final-unit race test:

```sh
python -m pip install "psycopg[binary]>=3.2,<4"
python supabase/tests/concurrent_reservation_test.py
```

If local email-link testing is enabled, use the local Mailpit URL printed by `supabase status`. Configure Apple auth only with your real developer settings; placeholders cannot complete an OAuth flow.

## 3. Edge Functions

Edge Functions are added with the vertical slice that uses them. When present, type-check each function with `deno check` and serve it with an ignored `.env.local` file for server-only development secrets.

## 4. Generate and test Apple projects

```sh
brew install xcodegen
xcodegen generate
swift test --package-path Packages/WishlistCore
xcodebuild -project Jiejie.xcodeproj -scheme Jiejie-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Jiejie.xcodeproj -scheme Jiejie-macOS \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Open `Jiejie.xcodeproj` only after generating it. The generated project is ignored; `project.yml` is the source of truth.

## 5. Verification before a pull request

```sh
swift test --package-path Packages/WishlistCore
deno fmt --check supabase/functions
supabase db reset --local
supabase test db
python supabase/tests/concurrent_reservation_test.py
xcodegen generate
```

Then build both Apple schemes in Xcode or let the macOS CI workflow compile simulator targets without code signing.

## Troubleshooting

- A missing `Config/Debug.xcconfig` or `Release.xcconfig` is expected on a clean clone. Copy the examples.
- If generated Info.plist substitution does not resolve, check that `SUPABASE_URL` uses `https:/$()/...`; this prevents `.xcconfig` from treating `//` as a comment.
- If local migrations fail after an already-applied change, do not edit old migration history. Add a corrective migration.
