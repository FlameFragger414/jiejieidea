import { assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import {
  bearerToken,
  decodeUnverifiedPayload,
  DEFAULT_MAX_SESSION_AGE_SECONDS,
  hasRecentSignIn,
  maxSessionAgeSeconds,
  ownedObjectNames,
  rejection,
} from "./deletion.ts";

const validToken = "aGVhZGVy.eyJpYXQiOjE3MDAwMDAwMDB9.c2lnbmF0dXJl";

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

Deno.test("the unverified payload is readable for timestamps only", () => {
  assertEquals(decodeUnverifiedPayload(validToken), { iat: 1_700_000_000 });
  assertEquals(decodeUnverifiedPayload("not-a-jwt"), null);
  assertEquals(decodeUnverifiedPayload("aGVhZGVy.bm90LWpzb24=.c2ln"), null);
});

Deno.test("a recent sign-in satisfies the freshness requirement", () => {
  const now = new Date("2026-08-13T12:00:00Z");
  assertEquals(
    hasRecentSignIn({
      lastSignInAt: "2026-08-13T11:30:00Z",
      issuedAt: null,
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
      issuedAt: null,
      now,
      maxAgeSeconds: DEFAULT_MAX_SESSION_AGE_SECONDS,
    }),
    false,
  );
});

Deno.test("the token issue time is used when no sign-in time is recorded", () => {
  const now = new Date("2026-08-13T12:00:00Z");
  assertEquals(
    hasRecentSignIn({
      lastSignInAt: null,
      issuedAt: Math.floor(now.getTime() / 1_000) - 60,
      now,
      maxAgeSeconds: 900,
    }),
    true,
  );
  assertEquals(
    hasRecentSignIn({
      lastSignInAt: null,
      issuedAt: Math.floor(now.getTime() / 1_000) - 4_000,
      now,
      maxAgeSeconds: 900,
    }),
    false,
  );
});

Deno.test("the newest available timestamp decides freshness", () => {
  const now = new Date("2026-08-13T12:00:00Z");
  assertEquals(
    hasRecentSignIn({
      lastSignInAt: "2026-07-01T12:00:00Z",
      issuedAt: Math.floor(now.getTime() / 1_000) - 30,
      now,
      maxAgeSeconds: 900,
    }),
    true,
  );
});

Deno.test("no usable timestamp fails closed", () => {
  const now = new Date("2026-08-13T12:00:00Z");
  assertEquals(
    hasRecentSignIn({
      lastSignInAt: null,
      issuedAt: null,
      now,
      maxAgeSeconds: 900,
    }),
    false,
  );
  assertEquals(
    hasRecentSignIn({
      lastSignInAt: "not a date",
      issuedAt: null,
      now,
      maxAgeSeconds: 900,
    }),
    false,
  );
});

Deno.test("a wildly future timestamp is not accepted", () => {
  const now = new Date("2026-08-13T12:00:00Z");
  assertEquals(
    hasRecentSignIn({
      lastSignInAt: "2027-01-01T00:00:00Z",
      issuedAt: null,
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
      issuedAt: null,
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
  const userID = "10000000-0000-0000-0000-000000000001";
  const otherID = "10000000-0000-0000-0000-000000000002";
  const names = [
    `${userID}/a.jpg`,
    `${userID}/nested/b.jpg`,
    `${otherID}/c.jpg`,
    `${userID}x/d.jpg`,
    "e.jpg",
  ];
  assertEquals(ownedObjectNames(userID, names), [`${userID}/a.jpg`]);
  assertNotEquals(ownedObjectNames(userID, names).length, names.length);
});
