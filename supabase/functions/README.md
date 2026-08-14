# Edge Functions

Edge Functions are added only with the vertical slice that uses them.

## `delete-account`

Permanently deletes the calling person's account.

- The caller is identified only by the `Authorization: Bearer <access token>`
  header. The request body is ignored, so a caller can never name another
  account. No CORS origin is allow-listed: the declared clients are the iOS and
  macOS apps, and no browser client exists.
- `auth.getUser()` verifies the token before anything is deleted.
- The caller must have authenticated recently.
  `ACCOUNT_DELETION_MAX_SESSION_AGE_SECONDS` (default `86400`) bounds how old
  `last_sign_in_at` on the verified user may be. Without a usable sign-in time
  the check fails closed. The token's own `iat` is deliberately not read: an
  automatic refresh reissues it roughly every hour, so it says the app is still
  running, not that the person proved who they are. Older authentications get
  `403` with `recent_sign_in_required`, and the app asks the person to sign in
  again. This bounds staleness; it is not a reauthentication challenge. See
  `docs/SECURITY.md` for the exact guarantee.
- Every profile image under `profile-images/<user id>/` is removed through the
  Storage API first, because storage objects have no cascading foreign key to
  `auth.users`. Cleanup lists a page, deletes what it may delete, and lists
  again from the start of the folder, so an account with more than one page of
  images is fully cleaned and a retry after a partial failure resumes from
  whatever is still stored. Folder placeholders are never counted as objects,
  and the loop is bounded so a folder that cannot shrink stops instead of
  spinning.
- `auth.admin.deleteUser` then removes the auth user, which cascades to
  profiles, wishlists, memberships, reservations, and notifications. A user that
  is already gone counts as success, so a retry can finish.
- Storage and Auth cannot be changed in one transaction. The order and the
  idempotency above are what make that safe, and no partial outcome is ever
  reported as a deletion.

### Responses

| Status | Body                                  | Meaning                                                        |
| ------ | ------------------------------------- | -------------------------------------------------------------- |
| `200`  | `{"status":"deleted"}`                | The account and its data are gone.                             |
| `401`  | `{"error":"missing_authorization"}`   | No `Authorization` header was sent.                            |
| `401`  | `{"error":"invalid_authorization"}`   | The header was not a well-formed bearer JWT.                   |
| `401`  | `{"error":"invalid_token"}`           | Supabase rejected the token.                                   |
| `403`  | `{"error":"recent_sign_in_required"}` | The last authentication is too old to delete an account.       |
| `405`  | `{"error":"method_not_allowed"}`      | Only `POST` is accepted.                                       |
| `500`  | `{"error":"server_misconfigured"}`    | A required environment variable is missing.                    |
| `502`  | `{"error":"storage_cleanup_failed"}`  | Images may remain, so the account was not deleted. Retry.      |
| `502`  | `{"error":"account_deletion_failed"}` | Images are gone but the auth user could not be deleted. Retry. |

### Server-side environment

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
injected automatically by the local stack and by the hosted platform. The
service-role key must never be copied into Swift code, a repository file, a log
line, or test output.

Optional overrides belong in an ignored `supabase/functions/.env.local`:

```sh
ACCOUNT_DELETION_MAX_SESSION_AGE_SECONDS=86400
```

### Local development

```sh
supabase functions serve delete-account --env-file supabase/functions/.env.local
deno fmt --check supabase/functions
deno lint supabase/functions
find supabase/functions -name '*.ts' -exec deno check {} +
deno test supabase/functions/delete-account/deletion_test.ts
```

`deletion.ts` holds the request-validation rules and the storage-cleanup loop.
The loop takes a small injected storage interface rather than a Supabase client,
so pagination, partial failures, and retries are unit tested without a project,
a key, or a network connection. No service-role key belongs in this directory or
in a client-visible response.

Every `.ts` file is type-checked, not just `index.ts`: the test file relies on
`deno check` to prove that the freshness helper no longer accepts a token issue
time.

Dependency specifiers are pinned to exact versions so a local run, a CI run, and
a deploy all resolve the same code.

## Planned

`product-metadata` will arrive with the wishlist item slice. It will validate
the authenticated caller, reject private or internal network targets, limit
response size and redirects, and return editable best-effort metadata.
