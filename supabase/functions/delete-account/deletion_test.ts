import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  bearerToken,
  DEFAULT_MAX_SESSION_AGE_SECONDS,
  deletableObjectPaths,
  hasRecentSignIn,
  isAlreadyDeleted,
  maxSessionAgeSeconds,
  ownedObjectNames,
  type ProfileImageStorage,
  rejection,
  removeOwnedProfileImages,
  type StorageListEntry,
} from "./deletion.ts";

const validToken = "aGVhZGVy.eyJpYXQiOjE3MDAwMDAwMDB9.c2lnbmF0dXJl";

const userID = "10000000-0000-0000-0000-000000000001";
const otherID = "10000000-0000-0000-0000-000000000002";

/** An in-memory stand-in for the Storage API, paginated the same way. */
class FakeProfileImageStorage implements ProfileImageStorage {
  objects: string[];
  listCalls: { prefix: string; limit: number; offset: number }[] = [];
  removedBatches: string[][] = [];
  failListOnCall: number | null = null;
  failRemoveOnCall: number | null = null;
  /** Extra entries returned by `list` that are folder placeholders rather than objects. */
  folderPlaceholders: string[] = [];

  constructor(names: string[]) {
    this.objects = [...names];
  }

  list(
    prefix: string,
    options: { limit: number; offset: number },
  ): Promise<{ data: StorageListEntry[] | null; error: unknown }> {
    this.listCalls.push({ prefix, ...options });
    if (this.failListOnCall === this.listCalls.length) {
      return Promise.resolve({ data: null, error: { message: "list failed" } });
    }

    const entries: StorageListEntry[] = [
      ...this.objects.map((name, index) => ({ name, id: `object-${index}` })),
      ...this.folderPlaceholders.map((name) => ({ name, id: null })),
    ];
    const page = entries.slice(options.offset, options.offset + options.limit);
    return Promise.resolve({ data: page, error: null });
  }

  remove(paths: string[]): Promise<{ error: unknown }> {
    this.removedBatches.push([...paths]);
    if (this.failRemoveOnCall === this.removedBatches.length) {
      return Promise.resolve({ error: { message: "remove failed" } });
    }

    const names = new Set(
      paths.map((path) => path.slice(`${userID}/`.length)),
    );
    this.objects = this.objects.filter((name) => !names.has(name));
    return Promise.resolve({ error: null });
  }

  get removedCount(): number {
    return this.removedBatches.reduce(
      (total, batch) => total + batch.length,
      0,
    );
  }
}

function imageNames(count: number): string[] {
  return Array.from({ length: count }, (_, index) => `image-${index}.jpg`);
}

Deno.test("a missing authorization header yields no token", () => {
  assertEquals(bearerToken(null), null);
  assertEquals(bearerToken(""), null);
});

Deno.test("only a well formed bearer JWT is accepted", () => {
  assertEquals(bearerToken(`Bearer ${validToken}`), validToken);
  assertEquals(bearerToken(`  Bearer ${validToken}  `), validToken);
  assertEquals(bearerToken(validToken), null);
  assertEquals(bearerToken(`Basic ${validToken}`), null);
  assertEquals(bearerToken("Bearer not-a-jwt"), null);
  assertEquals(bearerToken("Bearer only.two"), null);
  assertEquals(bearerToken("Bearer a..c"), null);
  assertEquals(bearerToken(`Bearer ${validToken} extra`), null);
});

Deno.test("rejections map to the intended status codes", () => {
  assertEquals(rejection("method_not_allowed").status, 405);
  assertEquals(rejection("missing_authorization").status, 401);
  assertEquals(rejection("invalid_authorization").status, 401);
  assertEquals(rejection("invalid_token").status, 401);
  assertEquals(rejection("recent_sign_in_required").status, 403);
});

Deno.test("a recent sign-in satisfies the freshness requirement", () => {
  const now = new Date("2026-08-13T12:00:00Z");
  assertEquals(
    hasRecentSignIn({
      lastSignInAt: "2026-08-13T11:30:00Z",
      now,
      maxAgeSeconds: DEFAULT_MAX_SESSION_AGE_SECONDS,
    }),
    true,
  );
});

Deno.test("an abandoned session cannot delete the account", () => {
  const now = new Date("2026-08-13T12:00:00Z");
  assertEquals(
    hasRecentSignIn({
      lastSignInAt: "2026-08-01T12:00:00Z",
      now,
      maxAgeSeconds: DEFAULT_MAX_SESSION_AGE_SECONDS,
    }),
    false,
  );
});

/**
 * The regression this endpoint most needs: an access token reissued minutes ago from a refresh
 * token proves only that the app kept running. It must not make a months-old login look recent.
 */
Deno.test("a freshly refreshed token cannot revive an old login", () => {
  const now = new Date("2026-08-13T12:00:00Z");
  assertEquals(
    hasRecentSignIn({
      lastSignInAt: "2026-02-01T09:15:00Z",
      now,
      maxAgeSeconds: DEFAULT_MAX_SESSION_AGE_SECONDS,
    }),
    false,
  );
  // The token issue time is not part of the contract any more, so `deno check` refuses any caller
  // that tries to reintroduce it.
  hasRecentSignIn({
    lastSignInAt: "2026-02-01T09:15:00Z",
    // @ts-expect-error issuedAt is deliberately not accepted by hasRecentSignIn.
    issuedAt: Math.floor(now.getTime() / 1_000),
    now,
    maxAgeSeconds: DEFAULT_MAX_SESSION_AGE_SECONDS,
  });
});

Deno.test("no usable sign-in time fails closed", () => {
  const now = new Date("2026-08-13T12:00:00Z");
  assertEquals(
    hasRecentSignIn({ lastSignInAt: null, now, maxAgeSeconds: 900 }),
    false,
  );
  assertEquals(
    hasRecentSignIn({ lastSignInAt: undefined, now, maxAgeSeconds: 900 }),
    false,
  );
  assertEquals(
    hasRecentSignIn({ lastSignInAt: "", now, maxAgeSeconds: 900 }),
    false,
  );
  assertEquals(
    hasRecentSignIn({ lastSignInAt: "not a date", now, maxAgeSeconds: 900 }),
    false,
  );
});

Deno.test("a wildly future timestamp is not accepted", () => {
  const now = new Date("2026-08-13T12:00:00Z");
  assertEquals(
    hasRecentSignIn({
      lastSignInAt: "2027-01-01T00:00:00Z",
      now,
      maxAgeSeconds: 900,
    }),
    false,
  );
});

Deno.test("small clock differences are tolerated", () => {
  const now = new Date("2026-08-13T12:00:00Z");
  assertEquals(
    hasRecentSignIn({
      lastSignInAt: "2026-08-13T12:00:30Z",
      now,
      maxAgeSeconds: 900,
    }),
    true,
  );
});

Deno.test("the session age window falls back to the default when unset or invalid", () => {
  assertEquals(
    maxSessionAgeSeconds(undefined),
    DEFAULT_MAX_SESSION_AGE_SECONDS,
  );
  assertEquals(maxSessionAgeSeconds(""), DEFAULT_MAX_SESSION_AGE_SECONDS);
  assertEquals(
    maxSessionAgeSeconds("not-a-number"),
    DEFAULT_MAX_SESSION_AGE_SECONDS,
  );
  assertEquals(maxSessionAgeSeconds("0"), DEFAULT_MAX_SESSION_AGE_SECONDS);
  assertEquals(maxSessionAgeSeconds("-5"), DEFAULT_MAX_SESSION_AGE_SECONDS);
  assertEquals(maxSessionAgeSeconds("900"), 900);
});

Deno.test("only objects directly inside the caller folder are removed", () => {
  const names = [
    `${userID}/a.jpg`,
    `${userID}/nested/b.jpg`,
    `${otherID}/c.jpg`,
    `${userID}x/d.jpg`,
    "e.jpg",
  ];
  assertEquals(ownedObjectNames(userID, names), [`${userID}/a.jpg`]);
});

Deno.test("folder placeholders are never treated as deletable objects", () => {
  const entries: StorageListEntry[] = [
    { name: "a.jpg", id: "object-1" },
    { name: "nested", id: null },
    { name: "b.jpg" },
  ];
  assertEquals(deletableObjectPaths(userID, entries), [`${userID}/a.jpg`]);
});

Deno.test("an empty folder needs no removal", async () => {
  const storage = new FakeProfileImageStorage([]);
  assertEquals(await removeOwnedProfileImages(storage, userID), {
    status: "cleaned",
    removed: 0,
  });
  assertEquals(storage.removedBatches.length, 0);
  assertEquals(storage.listCalls.length, 1);
});

Deno.test("a single object is removed", async () => {
  const storage = new FakeProfileImageStorage(imageNames(1));
  assertEquals(await removeOwnedProfileImages(storage, userID), {
    status: "cleaned",
    removed: 1,
  });
  assertEquals(storage.objects, []);
});

Deno.test("exactly one full page is removed and confirmed empty", async () => {
  const storage = new FakeProfileImageStorage(imageNames(100));
  assertEquals(await removeOwnedProfileImages(storage, userID), {
    status: "cleaned",
    removed: 100,
  });
  assertEquals(storage.objects, []);
  // One page of removals, then one more listing to prove nothing is left behind it.
  assertEquals(storage.removedBatches.length, 1);
  assertEquals(storage.listCalls.length, 2);
});

Deno.test("the object past the first page is not left behind", async () => {
  const storage = new FakeProfileImageStorage(imageNames(101));
  assertEquals(await removeOwnedProfileImages(storage, userID), {
    status: "cleaned",
    removed: 101,
  });
  assertEquals(storage.objects, []);
  assertEquals(storage.removedBatches.map((batch) => batch.length), [100, 1]);
});

Deno.test("many pages are all processed", async () => {
  const storage = new FakeProfileImageStorage(imageNames(457));
  assertEquals(await removeOwnedProfileImages(storage, userID), {
    status: "cleaned",
    removed: 457,
  });
  assertEquals(storage.objects, []);
  assertEquals(storage.removedBatches.map((batch) => batch.length), [
    100,
    100,
    100,
    100,
    57,
  ]);
});

Deno.test("another person's objects are never deleted", async () => {
  const storage = new FakeProfileImageStorage(["a.jpg"]);
  storage.objects.push("../escape.jpg");
  await removeOwnedProfileImages(storage, userID);
  for (const batch of storage.removedBatches) {
    for (const path of batch) {
      assertEquals(path.startsWith(`${userID}/`), true);
      assertEquals(path.slice(`${userID}/`.length).includes("/"), false);
    }
  }
});

Deno.test("a listing failure is reported rather than assumed empty", async () => {
  const storage = new FakeProfileImageStorage(imageNames(3));
  storage.failListOnCall = 1;
  assertEquals(await removeOwnedProfileImages(storage, userID), {
    status: "list_failed",
    removed: 0,
  });
});

Deno.test("a removal failure reports what was already deleted", async () => {
  const storage = new FakeProfileImageStorage(imageNames(150));
  storage.failRemoveOnCall = 2;
  assertEquals(await removeOwnedProfileImages(storage, userID), {
    status: "remove_failed",
    removed: 100,
  });
  // Retrying resumes from whatever is still stored.
  storage.failRemoveOnCall = null;
  assertEquals(await removeOwnedProfileImages(storage, userID), {
    status: "cleaned",
    removed: 50,
  });
  assertEquals(storage.objects, []);
});

Deno.test("a folder that cannot shrink stops instead of looping", async () => {
  const storage = new FakeProfileImageStorage([]);
  storage.folderPlaceholders = ["nested"];
  assertEquals(await removeOwnedProfileImages(storage, userID), {
    status: "incomplete",
    removed: 0,
  });
  assertEquals(storage.listCalls.length, 1);
});

Deno.test("cleanup gives up after a bounded number of rounds", async () => {
  const storage = new FakeProfileImageStorage(imageNames(10));
  // A bucket that refills as fast as it is emptied must not spin forever.
  const original = storage.remove.bind(storage);
  storage.remove = (paths: string[]) => {
    const result = original(paths);
    storage.objects.push(...paths.map((path) => path.split("/")[1]));
    return result;
  };
  const outcome = await removeOwnedProfileImages(storage, userID, {
    pageSize: 5,
    maxRounds: 4,
  });
  assertEquals(outcome.status, "incomplete");
  assertEquals(storage.listCalls.length, 4);
});

Deno.test("an already deleted auth user is not reported as a failure", () => {
  assertEquals(isAlreadyDeleted({ status: 404 }), true);
  assertEquals(isAlreadyDeleted({ status: 500 }), false);
  assertEquals(isAlreadyDeleted({ message: "boom" }), false);
  assertEquals(isAlreadyDeleted(null), false);
  assertEquals(isAlreadyDeleted(undefined), false);
  assertEquals(isAlreadyDeleted("404"), false);
});
