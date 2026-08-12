# jiejieidea

**Idea Board** — a small full-stack starter app for capturing, upvoting, and managing ideas.

It's an [npm workspaces](https://docs.npmjs.com/cli/using-npm/workspaces) monorepo:

- `server/` — Express + TypeScript REST API (in-memory store, no external database required)
- `client/` — Vite + React + TypeScript single-page app

## Requirements

- Node.js >= 20 (developed against Node 22)
- npm 10+

## Getting started

```bash
npm install        # install all workspace dependencies
npm run dev        # start API (:3001) and web client (:5173) together
```

Then open http://localhost:5173. The Vite dev server proxies `/api/*` to the
API at `http://localhost:3001`.

## Scripts (run from the repo root)

| Command | Description |
| --- | --- |
| `npm run dev` | Run the API and client together with live reload |
| `npm run build` | Type-check and build both workspaces for production |
| `npm run typecheck` | Type-check both workspaces without emitting |
| `npm test` | Run the server test suite (Vitest) |
| `npm start` | Run the built API from `server/dist` |

## API

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/health` | Health check |
| `GET` | `/api/ideas` | List ideas (sorted by votes) |
| `POST` | `/api/ideas` | Create an idea `{ title, description? }` |
| `POST` | `/api/ideas/:id/upvote` | Upvote an idea |
| `DELETE` | `/api/ideas/:id` | Delete an idea |
