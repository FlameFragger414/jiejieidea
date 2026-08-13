/**
 * Permanently deletes the calling person's account.
 *
 * Identity comes exclusively from the verified access token: the request body is ignored, so a
 * caller cannot name somebody else. Removing the auth user needs the service-role key, which lives
 * only in this function's server-side environment and is never returned to the client.
 */

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  bearerToken,
  decodeUnverifiedPayload,
  hasRecentSignIn,
  maxSessionAgeSeconds,
  ownedObjectNames,
  rejection,
  type RejectionResponse,
} from "./deletion.ts";

const PROFILE_IMAGE_BUCKET = "profile-images";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function rejected(response: RejectionResponse): Response {
  return jsonResponse({ error: response.code }, response.status);
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
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

  const payload = decodeUnverifiedPayload(token);
  const issuedAt = typeof payload?.iat === "number" ? payload.iat : null;
  const recentEnough = hasRecentSignIn({
    lastSignInAt: user.last_sign_in_at ?? null,
    issuedAt,
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
  const { data: storedObjects, error: listError } = await adminClient.storage
    .from(PROFILE_IMAGE_BUCKET)
    .list(user.id, { limit: 100 });

  if (listError) {
    console.error("delete-account could not list stored profile images");
    return jsonResponse({ error: "storage_cleanup_failed" }, 502);
  }

  const objectNames = ownedObjectNames(
    user.id,
    (storedObjects ?? []).map((object) => `${user.id}/${object.name}`),
  );

  if (objectNames.length > 0) {
    const { error: removeError } = await adminClient.storage
      .from(PROFILE_IMAGE_BUCKET)
      .remove(objectNames);
    if (removeError) {
      console.error("delete-account could not remove stored profile images");
      return jsonResponse({ error: "storage_cleanup_failed" }, 502);
    }
  }

  // Deleting the auth user cascades to profiles, wishlists, memberships, reservations, and
  // notifications through the foreign keys declared in the initial migration.
  const { error: deleteError } = await adminClient.auth.admin.deleteUser(
    user.id,
  );
  if (deleteError) {
    console.error("delete-account could not delete the auth user");
    return jsonResponse({ error: "account_deletion_failed" }, 502);
  }

  return jsonResponse({ status: "deleted" }, 200);
});
