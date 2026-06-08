import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Spark OS frontend build.
//
// `base: "./"` keeps all asset URLs relative so the same build works whether it
// is served from the root of a Cloudflare Worker (https://spark-os.workers.dev/)
// or from a GitHub Pages project subpath (https://<user>.github.io/spark-os/).
//
// We build into `docs/` because that is the directory GitHub Pages publishes
// from on the `main` branch (CI-free, "deploy from a branch"). The Cloudflare
// Worker also serves this same directory as its static assets.
export default defineConfig({
  plugins: [react()],
  base: "./",
  build: {
    outDir: "docs",
    emptyOutDir: true,
  },
});
