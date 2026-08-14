# Edge Functions

Edge Functions are added only with the vertical slice that uses them.

## `delete-account`

Permanently deletes the calling person's account.

- The caller is identified only by the `Authorization: Bearer <access token>`
  header. The request body is ignored, so a caller can never name another
  account.
- `auth.getUser()` verifies the token before anything is deleted.
- The session must be recent. `ACCOUNT_DELETION_MAX_SESSION_AGE_SECONDS`
  (default `86400`) bounds how old the recorded sign-in, or the token issue
  time, may be. Older sessions get `403` with `recent_sign_in_required`, and the
  app asks the person to sign in again.
- Profile images under `profile-images/<user id>/` are removed through the
  Storage API first, because storage objects have no cascading foreign key to
  `auth.users`.
- `auth.admin.deleteUser` then removes the auth user, which cascades to
  profiles, wishlists, memberships, reservations, and notifications.

### Responses

| Status | Body                                  | Meaning                                      |
| ------ | ------------------------------------- | -------------------------------------------- |
| `200`  | `{"status":"deleted"}`                | The account and its data are gone.           |
| `401`  | `{"error":"missing_authorization"}`   | No `Authorization` header was sent.          |
| `401`  | `{"error":"invalid_authorization"}`   | The header was not a well-formed bearer JWT. |
| `401`  | `{"error":"invalid_token"}`           | Supabase rejected the token.                 |
| `403`  | `{"error":"recent_sign_in_required"}` | The session is too old to delete an account. |
| `405`  | `{"error":"method_not_allowed"}`      | Only `POST` and `OPTIONS` are accepted.      |
| `500`  | `{"error":"server_misconfigured"}`    | A required environment variable is missing.  |
| `502`  | `{"error":"storage_cleanup_failed"}`  | Stored images could not be removed.          |
| `502`  | `{"error":"account_deletion_failed"}` | The auth user could not be deleted.          |

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
deno check supabase/functions/delete-account/index.ts
deno test supabase/functions/delete-account/deletion_test.ts
```

`deletion.ts` holds the pure request-validation rules so the authorization
behaviour is unit tested without a project, a key, or a network connection. No
service-role key belongs in this directory or in a client-visible response.

## Planned

`product-metadata` will arrive with the wishlist item slice. It will validate
the authenticated caller, reject private or internal network targets, limit
response size and redirects, and return editable best-effort metadata.
