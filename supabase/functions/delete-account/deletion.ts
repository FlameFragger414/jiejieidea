/**
 * Request validation for the account deletion endpoint.
 *
 * The helpers here are pure so the authorization rules can be tested without a Supabase project,
 * a service-role key, or a network connection.
 */

export const DEFAULT_MAX_SESSION_AGE_SECONDS = 86_400;

export type DeletionRejection =
  | "method_not_allowed"
  | "missing_authorization"
  | "invalid_authorization"
  | "invalid_token"
  | "recent_sign_in_required";

export interface RejectionResponse {
  status: number;
  code: DeletionRejection;
}

const REJECTION_STATUS: Record<DeletionRejection, number> = {
  method_not_allowed: 405,
  missing_authorization: 401,
  invalid_authorization: 401,
  invalid_token: 401,
  recent_sign_in_required: 403,
};

export function rejection(code: DeletionRejection): RejectionResponse {
  return { status: REJECTION_STATUS[code], code };
}

/**
 * Extracts the bearer token from an `Authorization` header.
 *
 * The token is never logged and is only forwarded to Supabase for verification.
 */
export function bearerToken(header: string | null): string | null {
  if (!header) return null;

  const match = /^Bearer[ ]([A-Za-z0-9\-_.]+)$/.exec(header.trim());
  if (!match) return null;

  const token = match[1];
  // A JWT always has three non-empty dot separated segments.
  const segments = token.split(".");
  if (
    segments.length !== 3 || segments.some((segment) => segment.length === 0)
  ) {
    return null;
  }
  return token;
}

/** Decodes the unverified payload only to read timestamps. Trust comes from `auth.getUser`. */
export function decodeUnverifiedPayload(
  token: string,
): Record<string, unknown> | null {
  const segments = token.split(".");
  if (segments.length !== 3) return null;

  try {
    const normalized = segments[1].replaceAll("-", "+").replaceAll("_", "/");
    const padded = normalized.padEnd(
      normalized.length + ((4 - (normalized.length % 4)) % 4),
      "=",
    );
    const decoded = new TextDecoder().decode(
      Uint8Array.from(atob(padded), (character) => character.charCodeAt(0)),
    );
    const payload = JSON.parse(decoded);
    return typeof payload === "object" && payload !== null ? payload : null;
  } catch {
    return null;
  }
}

/**
 * Requires the session behind the request to be recent.
 *
 * A long-abandoned session should not be able to destroy an account, so the sign-in time recorded
 * on the verified user, or the token issue time when that is unavailable, must fall inside the
 * configured window.
 */
export function hasRecentSignIn(
  options: {
    lastSignInAt?: string | null;
    issuedAt?: number | null;
    now: Date;
    maxAgeSeconds: number;
  },
): boolean {
  const { lastSignInAt, issuedAt, now, maxAgeSeconds } = options;

  const candidates: number[] = [];
  if (lastSignInAt) {
    const parsed = Date.parse(lastSignInAt);
    if (!Number.isNaN(parsed)) candidates.push(parsed);
  }
  if (typeof issuedAt === "number" && Number.isFinite(issuedAt)) {
    candidates.push(issuedAt * 1_000);
  }
  if (candidates.length === 0) return false;

  const mostRecent = Math.max(...candidates);
  const ageSeconds = (now.getTime() - mostRecent) / 1_000;
  // A timestamp slightly in the future is tolerated so small clock differences are not fatal.
  return ageSeconds <= maxAgeSeconds && ageSeconds >= -300;
}

export function maxSessionAgeSeconds(rawValue: string | undefined): number {
  if (!rawValue) return DEFAULT_MAX_SESSION_AGE_SECONDS;
  const parsed = Number.parseInt(rawValue, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_MAX_SESSION_AGE_SECONDS;
  }
  return parsed;
}

/** Object names the function is allowed to delete for a given user. */
export function ownedObjectNames(userID: string, names: string[]): string[] {
  const prefix = `${userID}/`;
  return names.filter((name) =>
    name.startsWith(prefix) && !name.slice(prefix.length).includes("/")
  );
}
