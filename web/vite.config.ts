import preact from "@preact/preset-vite";
import { defineConfig, loadEnv, type Plugin } from "vite";

// macOS Seatbelt blocks FSEvents, so Codex previews need polling for HMR.
const isCodexSeatbeltSandbox = process.env.CODEX_SANDBOX === "seatbelt";

// Public build-time configuration. The names predate the move off Next.js and
// are kept so deployment variables stay unchanged. Values come from the shell
// or .env files and are inlined into the client bundle only; the Worker reads
// its own runtime variables.
const PUBLIC_ENV_NAMES = [
  "NEXT_PUBLIC_CONVEX_URL",
  "NEXT_PUBLIC_SITE_URL",
  "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY",
  "NEXT_PUBLIC_TURNSTILE_SITE_KEY",
] as const;

// Absolute social-preview URLs need the canonical origin at build time.
function siteUrlInHtml(siteUrl: string): Plugin {
  return {
    name: "voiceink:site-url",
    transformIndexHtml: (html) => html.replaceAll("%SITE_URL%", siteUrl.replace(/\/$/, "")),
  };
}

export default defineConfig(async ({ mode }) => {
  // Keep Wrangler and Miniflare state project-local. These are non-secret tool
  // settings; application environment belongs in ignored `.env*` files.
  process.env.WRANGLER_WRITE_LOGS ??= "false";
  process.env.WRANGLER_LOG_PATH ??= ".wrangler/logs";
  process.env.MINIFLARE_REGISTRY_PATH ??= ".wrangler/registry";

  // Wrangler snapshots its log path while the Cloudflare plugin is imported.
  const { cloudflare } = await import("@cloudflare/vite-plugin");

  const fileEnv = loadEnv(mode, process.cwd(), "NEXT_PUBLIC_");
  const publicEnv = Object.fromEntries(PUBLIC_ENV_NAMES.map((name) => {
    const value = process.env[name] ?? fileEnv[name];
    return [`process.env.${name}`, value === undefined ? "undefined" : JSON.stringify(value)];
  }));
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? fileEnv.NEXT_PUBLIC_SITE_URL ?? "http://localhost:5173";

  return {
    server: isCodexSeatbeltSandbox
      ? { watch: { useFsEvents: false, usePolling: true } }
      : undefined,
    environments: {
      client: { define: publicEnv, build: { sourcemap: false } },
      server: { build: { outDir: "dist/server" } },
    },
    plugins: [
      preact({ prerender: { enabled: true, renderTarget: "#app" } }),
      siteUrlInHtml(siteUrl),
      cloudflare({
        viteEnvironment: { name: "server" },
        // Local development binds only the static assets; production bindings
        // (ASR service, rate limiters) live in wrangler.production.jsonc, and
        // their absence fails the API routes closed.
        config: {
          name: "voiceink-web",
          main: "./worker/index.ts",
          compatibility_date: "2026-07-12",
          compatibility_flags: ["nodejs_compat", "enable_request_signal"],
          assets: { binding: "ASSETS", run_worker_first: ["/", "/index.html"] },
        },
      }),
    ],
  };
});
