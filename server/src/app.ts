import express, { type Express, type Request, type Response } from "express";
import cors from "cors";
import { IdeaStore, ValidationError } from "./ideas.js";

export function createApp(store: IdeaStore = defaultStore()): Express {
  const app = express();
  app.use(cors());
  app.use(express.json());

  app.get("/api/health", (_req: Request, res: Response) => {
    res.json({ status: "ok", uptime: process.uptime() });
  });

  app.get("/api/ideas", (_req: Request, res: Response) => {
    res.json(store.list());
  });

  app.post("/api/ideas", (req: Request, res: Response) => {
    try {
      const idea = store.create({
        title: req.body?.title,
        description: req.body?.description,
      });
      res.status(201).json(idea);
    } catch (err) {
      if (err instanceof ValidationError) {
        res.status(400).json({ error: err.message });
        return;
      }
      throw err;
    }
  });

  app.post("/api/ideas/:id/upvote", (req: Request, res: Response) => {
    const idea = store.upvote(req.params.id);
    if (!idea) {
      res.status(404).json({ error: "idea not found" });
      return;
    }
    res.json(idea);
  });

  app.delete("/api/ideas/:id", (req: Request, res: Response) => {
    const deleted = store.delete(req.params.id);
    if (!deleted) {
      res.status(404).json({ error: "idea not found" });
      return;
    }
    res.status(204).end();
  });

  return app;
}

export function defaultStore(): IdeaStore {
  return new IdeaStore([
    { title: "Weekly idea jam", description: "Reserve 30 minutes every Friday to brainstorm." },
    { title: "Dark mode", description: "Add a theme toggle to the board." },
    { title: "Shareable boards", description: "Let teammates collaborate on the same board." },
  ]);
}
