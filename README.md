# Spark OS

An **AI-native personal operating system**. State an intent in plain language —
_"plan my launch week"_, _"summarize what changed across my repos"_ — and Spark
coordinates background AI agents to do the work and report results, with a live
dashboard of agents, tasks, and outputs.

This repo is the M1 vertical slice: a deployable web app that we grow into the
full intent → agent → result loop.

**Live URL:** https://jeff0723.github.io/spark-os/ — serves the hello-world page.

> Hosting note: the production target is **Cloudflare Workers** (see
> [Deploy](#deploy)); all M1 infrastructure (D1, Workers AI, Queues) is
> provisioned there. The current public URL is GitHub Pages (static frontend
> only), used as the interim live URL while Cloudflare account access is
> restored — see [Deploy → Cloudflare](#1-cloudflare-workers-production-target).

---

## Stack

Chosen to be boring, fast, and deployable from the first commit:

| Layer        | Choice                              | Why                                                                   |
| ------------ | ----------------------------------- | --------------------------------------------------------------------- |
| Host         | **Cloudflare Workers**              | Managed, global, CI-free `wrangler deploy`. D1 + Workers AI on-tap.   |
| Backend      | **Hono** (TypeScript)               | Tiny, fast router that runs natively on Workers.                      |
| Frontend     | **Vite + React + TypeScript** (SPA) | Fast, conventional, well-documented.                                  |
| Database     | **Cloudflare D1** (SQLite)          | _Next task ([TES-3]) — wired into `wrangler.jsonc` when the schema lands._ |
| Agent / LLM  | **Cloudflare Workers AI**           | _Later M1 task — same account, no extra vendor._                      |
| Pkg manager  | **pnpm**                            | Fast, disk-efficient.                                                 |

One Worker serves both the JSON API (`/api/*`) and the built React app (static
assets). The frontend build is host-agnostic (`base: "./"`), so the exact same
output serves from a Worker root **or** a GitHub Pages project subpath.

```
.
├── index.html          # Vite entry (frontend)
├── src/                # React frontend (App.tsx, main.tsx, index.css)
├── worker/             # Hono backend (worker/index.ts) — the /api routes
├── docs/               # Build output — GitHub Pages publish dir (committed)
├── wrangler.jsonc      # Cloudflare Worker config (API + static assets)
└── vite.config.ts      # base "./", builds into docs/
```

The `/api/health` endpoint is the seed of the backend; M1 tasks (auth, intents,
agent runs) build on top of it.

## Run locally

Requires Node 20+ and pnpm.

```bash
pnpm install

# 1. Frontend only (Vite dev server, hot reload) — http://localhost:5173
pnpm dev

# 2. Full stack (Worker serving API + built assets) — http://localhost:8787
pnpm build        # build the frontend into docs/ first
pnpm dev:worker   # runs `wrangler dev`
```

Quick check of the full-stack path:

```bash
curl http://localhost:8787/api/health
# {"ok":true,"service":"spark-os","version":"0.1.0"}
```

## Deploy

### 1. Cloudflare Workers (production target)

CI-free — one command from your machine:

```bash
pnpm deploy        # = npm run build && wrangler deploy
```

This builds the frontend into `docs/` and deploys the Worker (API + static
assets) to `https://spark-os.<your-subdomain>.workers.dev`.

> **Current blocker:** the `wrangler` session in this environment is
> authenticated but the OAuth token has **no accessible Cloudflare account**
> (it can authenticate but `GET /accounts` is empty and `/memberships` returns
> an auth error, so `wrangler deploy` cannot resolve an account). Restoring
> access is an account-owner action: either re-run `wrangler login` and grant
> the spark-os account, or set `CLOUDFLARE_ACCOUNT_ID` to an account the token
> is a member of. Tracked as a follow-up; until then the live URL is GitHub
> Pages (below).

### 2. GitHub Pages (current live URL, CI-free)

Pages is configured to **deploy from a branch**: `main` → `/docs`. No GitHub
Actions, no build server. To update the live site:

```bash
pnpm build         # regenerates docs/
git add docs && git commit -m "build: update site" && git push
```

GitHub rebuilds Pages automatically on push (usually < 1 min). Live at
https://jeff0723.github.io/spark-os/.

Pages serves the static frontend only — there is no backend there, so the page
reports _"static preview (backend not attached)"_. The full API runs on the
Cloudflare Worker.

---

_Founding engineer build · M1 vertical slice. Roadmap: see TES-1._

[TES-3]: https://github.com/jeff0723/spark-os
