import { Hono } from "hono";

// Cloudflare Worker bindings. These are declared in wrangler.jsonc and grow as
// M1 lands (D1 for the data model, Workers AI for the agent loop, etc.).
type Bindings = {
  ASSETS: Fetcher;
};

const app = new Hono<{ Bindings: Bindings }>();

const VERSION = "0.1.0";

// --- API routes ---------------------------------------------------------------
// Everything under /api is the Spark OS backend. The frontend (and downstream
// M1 tasks: auth, intents, agent runs) build on top of this.

app.get("/api/health", (c) =>
  c.json({ ok: true, service: "spark-os", version: VERSION }),
);

// --- Static frontend ----------------------------------------------------------
// Anything that is not an /api route is handed to the static asset server, which
// serves the built Vite/React SPA (configured in wrangler.jsonc -> assets).
app.all("*", (c) => c.env.ASSETS.fetch(c.req.raw));

export default app;
