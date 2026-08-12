import { randomUUID } from "node:crypto";

export interface Idea {
  id: string;
  title: string;
  description: string;
  votes: number;
  createdAt: string;
}

export interface CreateIdeaInput {
  title: string;
  description?: string;
}

/**
 * In-memory store for ideas. Intentionally simple so the starter app runs with
 * zero external dependencies; swap for a real database when the project grows.
 */
export class IdeaStore {
  private ideas: Map<string, Idea> = new Map();

  constructor(seed: CreateIdeaInput[] = []) {
    for (const item of seed) {
      this.create(item);
    }
  }

  list(): Idea[] {
    return [...this.ideas.values()].sort(
      (a, b) => b.votes - a.votes || b.createdAt.localeCompare(a.createdAt),
    );
  }

  get(id: string): Idea | undefined {
    return this.ideas.get(id);
  }

  create(input: CreateIdeaInput): Idea {
    const title = input.title?.trim();
    if (!title) {
      throw new ValidationError("title is required");
    }
    const idea: Idea = {
      id: randomUUID(),
      title,
      description: input.description?.trim() ?? "",
      votes: 0,
      createdAt: new Date().toISOString(),
    };
    this.ideas.set(idea.id, idea);
    return idea;
  }

  upvote(id: string): Idea | undefined {
    const idea = this.ideas.get(id);
    if (!idea) return undefined;
    idea.votes += 1;
    return idea;
  }

  delete(id: string): boolean {
    return this.ideas.delete(id);
  }
}

export class ValidationError extends Error {}
