/**
 * Permanently deletes the calling person's account.
 *
 * Identity comes exclusively from the verified access token: the request body is ignored, so a
 * caller cannot name somebody else. Removing the auth user needs the service-role key, which lives
 * only in this function's server-side environment and is never returned to the client.
 *
 * The operation cannot be transactional across Storage and Auth, so it is ordered and idempotent
 * instead: every owned profile image is removed first, and the auth user is deleted only once no
 * personal data is known to remain. A partial failure is reported as a failure and can be retried.
 */

// Pinned to an exact version so a CI run, a local run, and a deploy all resolve the same client.
import { createClient } from "jsr:@supabase/supabase-js@2.112.3";
import {
  authUserDeletionOutcome,
  bearerToken,
  hasRecentSignIn,
  maxSessionAgeSeconds,
  type ProfileImageStorage,
  rejection,
  type RejectionResponse,
  removeOwnedProfileImages,
  type StorageListEntry,
} from "./deletion.ts";

const PROFILE_IMAGE_BUCKET = "profile-images";

// The declared clients are the iOS and macOS apps, which do not send an `Origin` and do not need
// CORS. No origin is allow-listed, so a web page cannot invoke this destructive endpoint from a
// browser even if it obtains a token.
const baseHeaders = { "Content-Type": "application/json" };

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: baseHeaders });
}

function rejected(response: RejectionResponse): Response {
  return jsonResponse({ error: response.code }, response.status);
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return rejected(rejection("method_not_allowed"));
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !publishableKey || !serviceRoleKey) {
    console.error(
      "delete-account is missing its server-side environment configuration",
    );
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return rejected(rejection("missing_authorization"));
  }

  const token = bearerToken(authorization);
  if (!token) {
    return rejected(rejection("invalid_authorization"));
  }

  // A client scoped to the caller's token, used only to verify who the caller is.
  const callerClient = createClient(supabaseURL, publishableKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await callerClient.auth
    .getUser();
  if (userError || !userData?.user) {
    return rejected(rejection("invalid_token"));
  }
  const user = userData.user;

  // Only the sign-in recorded on the verified user counts. The token's own `iat` is not read at
  // all, because an automatic refresh reissues it without the person authenticating again.
  const recentEnough = hasRecentSignIn({
    lastSignInAt: user.last_sign_in_at ?? null,
    now: new Date(),
    maxAgeSeconds: maxSessionAgeSeconds(
      Deno.env.get("ACCOUNT_DELETION_MAX_SESSION_AGE_SECONDS"),
    ),
  });
  if (!recentEnough) {
    return rejected(rejection("recent_sign_in_required"));
  }

  const adminClient = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Storage objects have no cascading foreign key to auth.users, so they are removed explicitly
  // before the user row disappears and the folder becomes unattributable.
  const bucket = adminClient.storage.from(PROFILE_IMAGE_BUCKET);
  const storage: ProfileImageStorage = {
    list: (prefix, options) =>
      bucket.list(prefix, options) as Promise<
        { data: StorageListEntry[] | null; error: unknown }
      >,
    remove: (paths) => bucket.remove(paths),
  };

  const cleanup = await removeOwnedProfileImages(storage, user.id);
  if (cleanup.status !== "cleaned") {
    // Personal data is still stored, so the account must not be reported as deleted. The auth user
    // is left in place: it is what ties the remaining objects to a person who can retry.
    console.error(
      `delete-account stopped during profile image cleanup: ${cleanup.status}`,
    );
    return jsonResponse({ error: "storage_cleanup_failed" }, 502);
  }

  // Deleting the auth user cascades to profiles, wishlists, memberships, reservations, and
  // notifications through the foreign keys declared in the initial migration.
  const { error: deleteError } = await adminClient.auth.admin.deleteUser(
    user.id,
  );
  if (authUserDeletionOutcome(deleteError) === "failed") {
    console.error("delete-account could not delete the auth user");
    return jsonResponse({ error: "account_deletion_failed" }, 502);
  }

  return jsonResponse({ status: "deleted" }, 200);
});
