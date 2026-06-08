import { useEffect, useState } from "react";

type Health = { ok: boolean; service: string; version: string };

/**
 * Spark OS hello-world landing.
 *
 * It also probes the `/api/health` endpoint exposed by the Cloudflare Worker
 * backend. When served as a static site (e.g. GitHub Pages) there is no
 * backend, so the probe simply reports "static" — the page still renders.
 */
export default function App() {
  const [api, setApi] = useState<"checking" | "online" | "static">("checking");
  const [health, setHealth] = useState<Health | null>(null);

  useEffect(() => {
    fetch("api/health")
      .then((r) => (r.ok ? r.json() : Promise.reject()))
      .then((data: Health) => {
        setHealth(data);
        setApi("online");
      })
      .catch(() => setApi("static"));
  }, []);

  return (
    <main className="shell">
      <div className="card">
        <p className="eyebrow">Spark OS</p>
        <h1>Hello, world.</h1>
        <p className="lede">
          An AI-native personal operating system. State an intent; Spark
          coordinates background agents to do the work and reports back.
        </p>
        <p className="status" data-state={api}>
          <span className="dot" />
          {api === "checking" && "checking backend…"}
          {api === "online" &&
            `backend online — ${health?.service} v${health?.version}`}
          {api === "static" && "static preview (backend not attached)"}
        </p>
      </div>
      <footer>M1 · vertical slice · founding engineer build</footer>
    </main>
  );
}
