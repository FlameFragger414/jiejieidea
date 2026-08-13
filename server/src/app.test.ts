import { describe, it, expect } from "vitest";
import request from "supertest";
import { createApp } from "./app.js";
import { IdeaStore } from "./ideas.js";

function freshApp() {
  return createApp(new IdeaStore());
}

describe("Idea Board API", () => {
  it("reports health", async () => {
    const res = await request(freshApp()).get("/api/health");
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("ok");
  });

  it("starts with an empty list", async () => {
    const res = await request(freshApp()).get("/api/ideas");
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });

  it("creates, lists, upvotes, and deletes an idea", async () => {
    const app = freshApp();

    const created = await request(app)
      .post("/api/ideas")
      .send({ title: "Test idea", description: "hello" });
    expect(created.status).toBe(201);
    const id = created.body.id as string;
    expect(created.body.title).toBe("Test idea");
    expect(created.body.votes).toBe(0);

    const listed = await request(app).get("/api/ideas");
    expect(listed.body).toHaveLength(1);

    const voted = await request(app).post(`/api/ideas/${id}/upvote`);
    expect(voted.status).toBe(200);
    expect(voted.body.votes).toBe(1);

    const removed = await request(app).delete(`/api/ideas/${id}`);
    expect(removed.status).toBe(204);

    const empty = await request(app).get("/api/ideas");
    expect(empty.body).toEqual([]);
  });

  it("rejects an idea without a title", async () => {
    const res = await request(freshApp()).post("/api/ideas").send({ description: "no title" });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/title/);
  });

  it("returns 404 when deleting a missing idea", async () => {
    const res = await request(freshApp()).delete("/api/ideas/does-not-exist");
    expect(res.status).toBe(404);
  });
});
