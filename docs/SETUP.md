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

| Key                        | Purpose                                                                  |
| -------------------------- | ------------------------------------------------------------------------ |
| `APP_BUNDLE_ID`            | Base bundle identifier. The targets append `.ios`, `.macos`, `.tests`.   |
| `SUPABASE_URL`             | Project URL, or `http:/$()/127.0.0.1:54321` for the local stack.         |
| `SUPABASE_PUBLISHABLE_KEY` | Publishable/anon client key only.                                        |
| `AUTH_REDIRECT_SCHEME`     | Custom URL scheme for the sign-in callback, for example `jiejie-debug`.  |
| `SHARE_LINK_HOST`          | Universal-link host used by share links.                                 |
| `APPLE_SIGN_IN_ENABLED`    | `YES` only after the manual Apple steps below. Defaults to `NO`.         |

The scheme is read from configuration at runtime, so the callback URL is always
`<AUTH_REDIRECT_SCHEME>://auth/callback`. With the default debug value that is
`jiejie-debug://auth/callback`.

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

Never run `supabase db reset --linked`. The hosted development project is managed by the repository
owner, and this repository's checks only ever target the local stack.

### Sign-in redirect configuration

`supabase/config.toml` already allow-lists `jiejie-debug://auth/callback` for the local stack. In the
hosted project, add the same value under **Authentication → URL Configuration → Redirect URLs**, plus
the release scheme once one exists. A redirect that is not allow-listed makes the emailed link fail
after it is opened, not when it is requested.

Email links are delivered to the local Mailpit inbox printed by `supabase status`. Open the link on
the same device that requested it: the PKCE code verifier is stored locally by the SDK, so a link
opened elsewhere cannot complete.

## 3. Edge Functions

```sh
supabase functions serve delete-account --env-file supabase/functions/.env.local
deno fmt --check supabase/functions
deno lint supabase/functions
deno check supabase/functions/delete-account/index.ts
deno test supabase/functions
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are provided automatically by the
local stack and by the hosted platform. `supabase/functions/.env.local` is ignored by Git and is only
needed for optional overrides such as `ACCOUNT_DELETION_MAX_SESSION_AGE_SECONDS`. See
[supabase/functions/README.md](../supabase/functions/README.md).

Deploying the function to the hosted project is a manual step for the repository owner:

```sh
supabase functions deploy delete-account
```

Until it is deployed, the in-app delete button reports a failure instead of pretending to succeed.

## 4. Sign in with Apple (manual)

The code path is complete, but it stays hidden until `APPLE_SIGN_IN_ENABLED = YES`, because none of
the following can be invented by this repository. Complete every step, then flip the flag.

In the Apple Developer account:

1. Register the real bundle identifiers for the iOS and macOS apps.
2. Enable the **Sign In with Apple** capability on both App IDs.
3. Create a **Services ID** and configure its return URL to your Supabase callback,
   `https://<project-ref>.supabase.co/auth/v1/callback`.
4. Create a **Sign in with Apple** private key and note the Key ID and Team ID.

In Xcode, after `xcodegen generate`:

5. Add the **Sign In with Apple** capability to both app targets. This repository does not add the
   `com.apple.developer.applesignin` entitlement, because doing so would break signing for anybody
   whose account does not have the capability enabled.

In Supabase:

6. Enable **Authentication → Providers → Apple**.
7. Set the client IDs to your app bundle identifiers and Services ID.
8. Generate the provider secret from the private key, Key ID, and Team ID, and store it as a project
   secret. Never commit it.

Locally, `supabase/config.toml` keeps the Apple provider disabled and reads the secret from
`env(SUPABASE_AUTH_EXTERNAL_APPLE_SECRET)` if you enable it. Placeholders cannot complete a real
Apple flow, so the email link flow is the supported local path.

## 5. Generate and test Apple projects

```sh
brew install xcodegen
xcodegen generate
swift test --package-path Packages/WishlistCore
xcodebuild -project Jiejie.xcodeproj -scheme Jiejie-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Jiejie.xcodeproj -scheme Jiejie-macOS \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Jiejie.xcodeproj -scheme Jiejie-macOS \
  -destination 'platform=macOS' -only-testing:JiejieTests CODE_SIGNING_ALLOWED=NO test
```

Open `Jiejie.xcodeproj` only after generating it. The generated project is ignored; `project.yml` is the source of truth.

### Development sample data

An ordinary Debug run behaves like a release build: no sample content is loaded. To see the
placeholder wishlist UI, add the launch argument `-JiejieSampleData` to the scheme, or set
`JIEJIE_SAMPLE_DATA=1` in the environment. Sample data is never available in a Release build.

## 6. Verification before a pull request

```sh
swift format lint --recursive --strict App Packages
swift test --package-path Packages/WishlistCore
xcodegen generate
xcodebuild -project Jiejie.xcodeproj -scheme Jiejie-macOS \
  -destination 'platform=macOS' -only-testing:JiejieTests CODE_SIGNING_ALLOWED=NO test
supabase db reset --local
supabase db lint --local --level warning
supabase test db
python supabase/tests/concurrent_reservation_test.py
deno fmt --check supabase/functions
deno lint supabase/functions
deno test supabase/functions
gitleaks detect --config .gitleaks.toml
```

Then build both Apple schemes in Xcode or let the macOS CI workflow compile simulator targets without code signing.

## Troubleshooting

- A missing `Config/Debug.xcconfig` or `Release.xcconfig` is expected on a clean clone. Copy the examples. The app shows a configuration screen rather than crashing.
- If generated Info.plist substitution does not resolve, check that `SUPABASE_URL` uses `https:/$()/...`; this prevents `.xcconfig` from treating `//` as a comment.
- If a sign-in link opens the app but nothing happens, confirm the redirect URL is allow-listed in Supabase and that `AUTH_REDIRECT_SCHEME` matches the scheme in the link.
- If local migrations fail after an already-applied change, do not edit old migration history. Add a corrective migration.
