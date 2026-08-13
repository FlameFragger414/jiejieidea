import { useEffect, useState, type FormEvent } from "react";
import { api, type Idea } from "./api.js";

export function App() {
  const [ideas, setIdeas] = useState<Idea[]>([]);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  async function refresh() {
    try {
      setIdeas(await api.list());
      setError(null);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void refresh();
  }, []);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    if (!title.trim()) return;
    try {
      await api.create(title, description);
      setTitle("");
      setDescription("");
      await refresh();
    } catch (err) {
      setError((err as Error).message);
    }
  }

  function sortIdeas(items: Idea[]): Idea[] {
    return [...items].sort(
      (a, b) => b.votes - a.votes || b.createdAt.localeCompare(a.createdAt),
    );
  }

  async function onUpvote(id: string) {
    setIdeas((prev) =>
      sortIdeas(prev.map((i) => (i.id === id ? { ...i, votes: i.votes + 1 } : i))),
    );
    try {
      await api.upvote(id);
    } catch (err) {
      setError((err as Error).message);
      await refresh();
    }
  }

  async function onDelete(id: string) {
    const previous = ideas;
    setIdeas((prev) => prev.filter((i) => i.id !== id));
    try {
      await api.remove(id);
    } catch (err) {
      setError((err as Error).message);
      setIdeas(previous);
    }
  }

  return (
    <main className="app">
      <header className="hero">
        <h1>Idea Board</h1>
        <p>Capture ideas, upvote the best ones, and keep the momentum going.</p>
      </header>

      <form className="card form" onSubmit={onSubmit}>
        <input
          aria-label="Idea title"
          placeholder="What's your idea?"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
        />
        <textarea
          aria-label="Idea description"
          placeholder="Add a few details (optional)"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          rows={2}
        />
        <button type="submit" disabled={!title.trim()}>
          Add idea
        </button>
      </form>

      {error && <p className="error">{error}</p>}
      {loading ? (
        <p className="muted">Loading ideas…</p>
      ) : ideas.length === 0 ? (
        <p className="muted">No ideas yet — add the first one above.</p>
      ) : (
        <ul className="list">
          {ideas.map((idea) => (
            <li key={idea.id} className="card idea">
              <div className="idea-body">
                <h3>{idea.title}</h3>
                {idea.description && <p>{idea.description}</p>}
              </div>
              <div className="idea-actions">
                <button className="vote" onClick={() => onUpvote(idea.id)}>
                  ▲ {idea.votes}
                </button>
                <button
                  className="delete"
                  aria-label={`Delete ${idea.title}`}
                  onClick={() => onDelete(idea.id)}
                >
                  ✕
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
