import { readdir, readFile } from "node:fs/promises";

const webRoot = new URL("../../", import.meta.url);

// The ASR Worker's request-handling modules read as one text, so contract
// assertions keep holding when code moves between files. The ledger modules
// (ledgerClient.ts, spendLedger.ts) are asserted on separately.
export async function asrWorkerSource() {
  const directory = new URL("cloudflare-asr/src/", webRoot);
  const files = (await readdir(directory))
    .filter((name) => name.endsWith(".ts") && name !== "ledgerClient.ts" && name !== "spendLedger.ts")
    .sort();
  return (await Promise.all(files.map((name) => readFile(new URL(name, directory), "utf8")))).join("\n");
}

// The history route plus its shared client helper, helper first so the route's
// per-method blocks can still be sliced by their "export async function" headers.
export async function historyRouteSource() {
  const [helper, route] = await Promise.all([
    readFile(new URL("lib/server/historyClient.ts", webRoot), "utf8"),
    readFile(new URL("app/api/history/route.ts", webRoot), "utf8"),
  ]);
  return `${helper}\n${route}`;
}

// The Studio page and the hooks it was split into, read as one text.
export async function studioSource() {
  const files = [
    "app/page.tsx",
    "app/use-transcription-session.ts",
    "app/use-recording-session.ts",
    "app/recording-stage.ts",
    "app/use-theme.ts",
  ];
  return (await Promise.all(files.map((file) => readFile(new URL(file, webRoot), "utf8")))).join("\n");
}
