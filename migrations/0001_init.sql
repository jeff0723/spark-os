-- Spark OS — core data model (M1)
-- Datastore: Cloudflare D1 (SQLite). Apply with:
--   pnpm db:migrate:local   (local dev)  |  pnpm db:migrate (remote/prod)
--
-- The intent → task → agent_run → output chain is the spine of the product:
-- a user states an INTENT, Spark breaks it into TASKS, each task is executed by
-- one or more AGENT_RUNS, and each run produces OUTPUTS.
--
-- Conventions (boring on purpose):
--   * Primary keys are app-generated UUID strings (TEXT). D1 has no gen_random_uuid();
--     the Worker mints ids with crypto.randomUUID().
--   * Timestamps are ISO-8601 UTC strings (e.g. 2026-06-08T04:47:06.173Z) so they
--     round-trip cleanly to JS Date. created_at defaults in SQL; updated_at is kept
--     fresh by triggers below.
--   * Lifecycle columns use CHECK constraints instead of a lookup table — minimal,
--     readable, and easy to widen in a later migration.
--   * Foreign keys cascade on delete down the chain (delete a user -> their intents,
--     tasks, runs, outputs all go). PRAGMA foreign_keys is ON by default in D1.

-- users — the human account that owns everything else.
CREATE TABLE users (
  id         TEXT PRIMARY KEY,
  email      TEXT NOT NULL UNIQUE,
  name       TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

-- intents — a natural-language goal a user states ("plan my launch week").
CREATE TABLE intents (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  prompt     TEXT NOT NULL,
  status     TEXT NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending', 'planning', 'running', 'completed', 'failed', 'cancelled')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE INDEX idx_intents_user_id ON intents(user_id);
CREATE INDEX idx_intents_status ON intents(status);

-- tasks — a unit of work Spark derives from an intent. The dashboard task list.
CREATE TABLE tasks (
  id          TEXT PRIMARY KEY,
  intent_id   TEXT NOT NULL REFERENCES intents(id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  description TEXT,
  status      TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE INDEX idx_tasks_intent_id ON tasks(intent_id);
CREATE INDEX idx_tasks_status ON tasks(status);

-- agent_runs — one execution attempt of an agent against a task. A task may be
-- retried, so it can have many runs; the latest succeeded/failed run is current.
CREATE TABLE agent_runs (
  id          TEXT PRIMARY KEY,
  task_id     TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  agent       TEXT NOT NULL,                 -- agent/model identifier, e.g. "workers-ai:@cf/meta/llama-3.1-8b"
  status      TEXT NOT NULL DEFAULT 'queued'
                CHECK (status IN ('queued', 'running', 'succeeded', 'failed', 'cancelled')),
  input       TEXT,                          -- JSON snapshot of the prompt/context handed to the agent
  error       TEXT,                          -- failure message when status = 'failed'
  started_at  TEXT,
  finished_at TEXT,
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE INDEX idx_agent_runs_task_id ON agent_runs(task_id);
CREATE INDEX idx_agent_runs_status ON agent_runs(status);

-- outputs — a result artifact produced by an agent run (text, markdown, json, link).
-- task_id is denormalized so the dashboard can fetch a task's outputs without a
-- join through agent_runs; it stays consistent because both cascade from tasks.
CREATE TABLE outputs (
  id           TEXT PRIMARY KEY,
  agent_run_id TEXT NOT NULL REFERENCES agent_runs(id) ON DELETE CASCADE,
  task_id      TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  type         TEXT NOT NULL DEFAULT 'text'
                 CHECK (type IN ('text', 'markdown', 'json', 'link', 'error')),
  content      TEXT NOT NULL,
  created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE INDEX idx_outputs_agent_run_id ON outputs(agent_run_id);
CREATE INDEX idx_outputs_task_id ON outputs(task_id);

-- updated_at triggers — SQLite doesn't auto-touch updated_at; keep it honest in SQL
-- so it's correct no matter which client writes. (outputs are immutable: no trigger.)
CREATE TRIGGER trg_users_updated_at AFTER UPDATE ON users
  BEGIN UPDATE users SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id; END;
CREATE TRIGGER trg_intents_updated_at AFTER UPDATE ON intents
  BEGIN UPDATE intents SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id; END;
CREATE TRIGGER trg_tasks_updated_at AFTER UPDATE ON tasks
  BEGIN UPDATE tasks SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id; END;
CREATE TRIGGER trg_agent_runs_updated_at AFTER UPDATE ON agent_runs
  BEGIN UPDATE agent_runs SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id; END;
