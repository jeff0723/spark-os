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
| Database     | **Cloudflare D1** (SQLite)          | Managed SQLite on the same account. Schema in `migrations/` — see [Data model](#data-model). |
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
├── migrations/         # D1 (SQLite) schema migrations — see Data model
├── docs/               # Build output — GitHub Pages publish dir (committed)
├── wrangler.jsonc      # Cloudflare Worker config (API + static assets + D1)
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

## Data model

The data layer is **Cloudflare D1** (managed SQLite), bound to the Worker as
`DB`. The schema is the spine of the product: a user states an **intent**, Spark
breaks it into **tasks**, each task is executed by one or more **agent runs**,
and each run produces **outputs**.

```
users ──1:N──> intents ──1:N──> tasks ──1:N──> agent_runs ──1:N──> outputs
                                   └───────────────────────1:N──────────┘
                                       (outputs also carry task_id, denormalized)
```

| Table        | Purpose                                              | Key relationships                          |
| ------------ | ---------------------------------------------------- | ------------------------------------------ |
| `users`      | The human account that owns everything.              | —                                          |
| `intents`    | A natural-language goal ("plan my launch week").     | `user_id → users.id`                       |
| `tasks`      | A unit of work Spark derives from an intent.         | `intent_id → intents.id`                   |
| `agent_runs` | One execution attempt of an agent against a task.    | `task_id → tasks.id`                       |
| `outputs`    | A result artifact produced by an agent run.          | `agent_run_id → agent_runs.id`, `task_id → tasks.id` |

**Conventions:**

- **IDs** are app-generated UUID strings (`crypto.randomUUID()` in the Worker) —
  D1 has no `gen_random_uuid()`.
- **Timestamps** are ISO-8601 UTC strings; `created_at` defaults in SQL,
  `updated_at` is kept fresh by triggers.
- **Lifecycle** columns (`status`, output `type`) use `CHECK` constraints rather
  than lookup tables — minimal and easy to widen later.
- **Foreign keys cascade on delete** down the whole chain (delete a user and
  their intents, tasks, runs, and outputs all go).

**Modeling tradeoffs** (deliberate, reversible):

- `agent_runs` is a separate table (not a column on `tasks`) so a task can be
  **retried** — many runs per task, latest is current. Costs one extra join; buys
  a full execution history for the live dashboard.
- `outputs.task_id` is **denormalized** (also reachable via `agent_run_id`) so the
  dashboard can list a task's outputs without joining through runs. Both columns
  cascade from `tasks`, so they can't drift.
- Statuses are CHECK-constrained strings, not a `statuses` table. Widening the set
  is a one-line migration; the simplicity is worth losing referential rigor here.
- `agent_runs.input` / `outputs.content` hold JSON/text blobs rather than typed
  columns — the agent payload shape is still moving in M1; we'll normalize once it
  settles.

**Migrations** live in `migrations/` and are applied with `wrangler`:

```bash
pnpm db:create          # one-time: create the D1 database (records database_id)
pnpm db:migrate:local   # apply migrations to the local dev DB (.wrangler/state)
pnpm db:migrate         # apply migrations to the remote (prod) DB
pnpm db:console "SELECT * FROM users"   # ad-hoc query against the local DB
```

> Requires **Node 22+** (wrangler 4). `pnpm db:create` writes the real
> `database_id` into `wrangler.jsonc`, replacing the committed placeholder; it
> needs Cloudflare account access (same blocker as deploy, below). Local
> migrations (`--local`) work today with no account.

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
