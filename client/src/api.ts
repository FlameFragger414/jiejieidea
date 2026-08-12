export interface Idea {
  id: string;
  title: string;
  description: string;
  votes: number;
  createdAt: string;
}

async function handle<T>(res: Response): Promise<T> {
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { error?: string };
    throw new Error(body.error ?? `Request failed with ${res.status}`);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

export const api = {
  list: () => fetch("/api/ideas").then((r) => handle<Idea[]>(r)),
  create: (title: string, description: string) =>
    fetch("/api/ideas", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title, description }),
    }).then((r) => handle<Idea>(r)),
  upvote: (id: string) =>
    fetch(`/api/ideas/${id}/upvote`, { method: "POST" }).then((r) => handle<Idea>(r)),
  remove: (id: string) =>
    fetch(`/api/ideas/${id}`, { method: "DELETE" }).then((r) => handle<void>(r)),
};
