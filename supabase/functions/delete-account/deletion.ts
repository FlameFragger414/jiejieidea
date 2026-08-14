/**
 * Request validation and storage cleanup rules for the account deletion endpoint.
 *
 * The helpers here are pure, or take a minimal injected storage interface, so the authorization and
 * cleanup rules can be tested without a Supabase project, a service-role key, or a network
 * connection.
 */

export const DEFAULT_MAX_SESSION_AGE_SECONDS = 86_400;

/** How many objects one `list` page may contain. This is the Storage API maximum default page. */
export const STORAGE_PAGE_SIZE = 100;

/**
 * An upper bound on cleanup rounds, so a bucket that never shrinks cannot loop forever. Each round
 * removes up to `STORAGE_PAGE_SIZE` objects, which is far more profile images than an account can
 * legitimately hold.
 */
export const MAX_STORAGE_CLEANUP_ROUNDS = 200;

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

/**
 * Requires the caller to have authenticated recently.
 *
 * Only `last_sign_in_at` from the verified user is considered. It records an actual authentication:
 * a magic-link exchange or an Apple identity-token exchange. The access token's `iat` is
 * deliberately ignored, because Supabase reissues an access token from the refresh token roughly
 * every hour, so an `iat` is evidence that the app is still running, not that the person proved who
 * they are.
 *
 * Without a usable sign-in time the check fails closed: destroying an account is not something to
 * allow on missing evidence.
 *
 * This bounds staleness. It is not a reauthentication challenge, and it is not equivalent to one.
 * See `docs/SECURITY.md` for the exact guarantee and its limits.
 */
export function hasRecentSignIn(
  options: {
    lastSignInAt?: string | null;
    now: Date;
    maxAgeSeconds: number;
  },
): boolean {
  const { lastSignInAt, now, maxAgeSeconds } = options;

  if (!lastSignInAt) return false;
  const signedInAt = Date.parse(lastSignInAt);
  if (Number.isNaN(signedInAt)) return false;

  const ageSeconds = (now.getTime() - signedInAt) / 1_000;
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

/** One entry from a Storage `list` page. Folder placeholders are reported with a null `id`. */
export interface StorageListEntry {
  name: string;
  id?: string | null;
}

/**
 * Turns one `list` page into the full object paths this function may delete.
 *
 * Folder placeholders are dropped: they are not objects, so removing them is a no-op that would
 * make a cleanup round appear to make progress when it does not. Every remaining path is then
 * re-checked against the caller's own prefix, so a listing that returned something unexpected can
 * never widen what gets deleted.
 */
export function deletableObjectPaths(
  userID: string,
  entries: readonly StorageListEntry[],
): string[] {
  const names = entries
    .filter((entry) => entry.id !== null && entry.id !== undefined)
    .map((entry) => `${userID}/${entry.name}`);
  return ownedObjectNames(userID, names);
}

/** The slice of the Storage client this cleanup needs, so tests can supply their own. */
export interface ProfileImageStorage {
  list(
    prefix: string,
    options: { limit: number; offset: number },
  ): Promise<{ data: StorageListEntry[] | null; error: unknown }>;
  remove(
    paths: string[],
  ): Promise<{ error: unknown }>;
}

export type StorageCleanupOutcome =
  /** The caller's folder is empty. `removed` counts the objects this call deleted. */
  | { status: "cleaned"; removed: number }
  /** A page could not be listed, so it is unknown whether anything remains. */
  | { status: "list_failed"; removed: number }
  /** A removal was refused. Objects known to exist are still there. */
  | { status: "remove_failed"; removed: number }
  /** Objects remain that this function cannot delete or ran out of rounds for. */
  | { status: "incomplete"; removed: number };

/**
 * Removes every profile image the caller owns, not just the first page.
 *
 * Each round lists from offset zero and deletes what it finds, so deleting never shifts a later
 * page out of view, and re-invoking the endpoint after a partial failure simply resumes: the work
 * is idempotent because it is defined by what is still in the bucket rather than by a cursor.
 *
 * Any outcome other than `cleaned` means personal data may remain, and the caller must not report
 * the account as deleted.
 */
export async function removeOwnedProfileImages(
  storage: ProfileImageStorage,
  userID: string,
  options: { pageSize?: number; maxRounds?: number } = {},
): Promise<StorageCleanupOutcome> {
  const pageSize = options.pageSize ?? STORAGE_PAGE_SIZE;
  const maxRounds = options.maxRounds ?? MAX_STORAGE_CLEANUP_ROUNDS;
  let removed = 0;

  for (let round = 0; round < maxRounds; round++) {
    const { data, error } = await storage.list(userID, {
      limit: pageSize,
      offset: 0,
    });
    if (error) return { status: "list_failed", removed };

    const entries = data ?? [];
    if (entries.length === 0) return { status: "cleaned", removed };

    const paths = deletableObjectPaths(userID, entries);
    if (paths.length === 0) {
      // The folder is not empty but holds nothing this function may delete, so another round would
      // list the same entries forever. Report what is left instead of looping or claiming success.
      return { status: "incomplete", removed };
    }

    const { error: removeError } = await storage.remove(paths);
    if (removeError) return { status: "remove_failed", removed };
    removed += paths.length;
  }

  return { status: "incomplete", removed };
}

/**
 * `true` when deleting the auth user failed because the user is already gone.
 *
 * A retry after a partial failure has to be able to finish rather than report a permanent error for
 * work that actually completed.
 */
export function isAlreadyDeleted(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const status = (error as { status?: unknown }).status;
  return status === 404;
}
