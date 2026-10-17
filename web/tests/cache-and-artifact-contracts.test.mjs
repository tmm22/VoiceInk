import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { evaluateAuditReport } from "../scripts/check-audit.mjs";
import { findDuplicateArtifacts } from "../scripts/check-duplicates.mjs";

test("API responses are centrally private while HTML retains per-request CSP nonces", async () => {
  const source = await readFile(new URL("../proxy.ts", import.meta.url), "utf8");
  assert.match(source, /"Cache-Control": "private, no-store, max-age=0, must-revalidate"/);
  assert.match(source, /Pragma: "no-cache"/);
  assert.match(source, /Expires: "0"/);
  assert.match(source, /pathname === "\/api" \|\| request\.nextUrl\.pathname\.startsWith\("\/api\/"\)/);
  assert.match(source, /btoa\(crypto\.randomUUID\(\)\)/);
  assert.doesNotMatch(source, /sensitiveResponseHeaders[^;]+for \(const \[name, value\][^}]+\}\s*return/s);
});

test("tracked static header policy caches only content-hashed assets immutably", async () => {
  const headers = await readFile(new URL("../public/_headers", import.meta.url), "utf8");
  // vinext 0.2.x emits hashed assets under /_next/static/ (chunks and css).
  assert.match(headers, /\/_next\/static\/\*[\s\S]*public, max-age=31536000, immutable/);
  assert.doesNotMatch(headers, /\/assets\/\*/);
  assert.match(headers, /\/og\.png[\s\S]*public, max-age=3600, must-revalidate/);
  assert.doesNotMatch(headers, /\/og\.png[\s\S]*immutable/);
});

test("duplicate artifact scanner catches Finder copies and accepts clean output", async () => {
  const root = await mkdtemp(join(tmpdir(), "voiceink-duplicates-"));
  try {
    await writeFile(join(root, "page.ts"), "export {};\n");
    assert.deepEqual(await findDuplicateArtifacts(root), []);
    const duplicate = join(root, "page 2.ts");
    await writeFile(duplicate, "export {};\n");
    assert.deepEqual(await findDuplicateArtifacts(root), [duplicate]);
    await rm(duplicate);
    const duplicateDirectory = join(root, "app 2");
    await mkdir(duplicateDirectory);
    assert.deepEqual(await findDuplicateArtifacts(root), [duplicateDirectory]);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("audit exception only accepts the exact build-only braces chain until expiry", () => {
  const propagated = (via, effects, isDirect = false) => ({ severity: "high", isDirect, via, effects });
  const report = { vulnerabilities: {
    braces: propagated([{ name: "braces", url: "https://github.com/advisories/GHSA-vfj7-8cjw-p6xm" }], ["micromatch"]),
    micromatch: propagated(["braces"], ["fast-glob"]),
    "fast-glob": propagated(["micromatch"], ["@next/eslint-plugin-next", "vite-plugin-dynamic-import"]),
    "@next/eslint-plugin-next": propagated(["fast-glob"], ["eslint-config-next"]),
    "eslint-config-next": propagated(["@next/eslint-plugin-next"], [], true),
    "vite-plugin-dynamic-import": propagated(["fast-glob"], ["vite-plugin-commonjs"]),
    "vite-plugin-commonjs": propagated(["vite-plugin-dynamic-import"], ["vinext"]),
    vinext: propagated(["vite-plugin-commonjs"], [], true),
  } };
  const names = Object.keys(report.vulnerabilities).sort();
  const policy = { allowBuildBraces: true, today: "2026-10-17" };
  assert.deepEqual(evaluateAuditReport(report, policy), { allowed: names, blocked: [] });
  assert.deepEqual(evaluateAuditReport(report).blocked, names);
  assert.deepEqual(evaluateAuditReport(report, { ...policy, today: "2026-11-18" }).blocked, names);
  for (const mutate of [
    (v) => { v.braces.isDirect = true; },
    (v) => { v.braces.via.push({ name: "braces", url: "https://example.com/new-advisory" }); },
    (v) => { v.braces.effects.push("runtime-library"); },
    (v) => { v.vinext.via.push("another-package"); },
    (v) => { v.braces.severity = "critical"; },
  ]) {
    const changed = structuredClone(report);
    mutate(changed.vulnerabilities);
    assert.deepEqual(evaluateAuditReport(changed, policy).blocked, names);
  }
  const unrelated = structuredClone(report);
  unrelated.vulnerabilities.other = propagated([], []);
  assert.deepEqual(evaluateAuditReport(unrelated, policy).blocked, ["other"]);
});

// Literals each build-only package carries that survive minification. The
// client build emits no sourcemaps, so these are the only way to inspect it.
const buildOnlySignatures = {
  braces: "exceeds max characters",
  micromatch: "No matches found for",
  "fast-glob": "Patterns must be a string (non empty) or an array of strings",
  "vite-plugin-commonjs": "vite-plugin-commonjs",
  "vite-plugin-dynamic-import": "vite-plugin-dynamic-import",
};

async function readJavaScript(directory) {
  const entries = await readdir(directory, { recursive: true });
  return Promise.all(entries.filter((path) => /\.[cm]?js$/.test(path))
    .map(async (path) => ({ path, text: await readFile(new URL(path, directory), "utf8") })));
}

test("the accepted build-only glob dependencies are absent from deployed bundles", async () => {
  const build = new URL("../dist/", import.meta.url);
  const entries = await readdir(build, { recursive: true });
  const serverMaps = entries.filter((path) => path.startsWith("server/") && path.endsWith(".js.map"));
  assert.ok(serverMaps.length > 0, "inspect real server sourcemaps, not an empty artifact directory");
  for (const path of serverMaps) {
    const map = JSON.parse(await readFile(new URL(path, build), "utf8"));
    assert.ok(Array.isArray(map.sources), `${path} has no sources list to inspect`);
    for (const source of map.sources) {
      assert.doesNotMatch(source, /node_modules\/(?:braces|micromatch|fast-glob|vite-plugin-commonjs|vite-plugin-dynamic-import)\//,
        `build-only dependency leaked into ${path}`);
    }
  }

  const deployed = [
    ...await readJavaScript(new URL("client/", build)),
    ...await readJavaScript(new URL("server/", build)),
  ];
  assert.ok(deployed.some(({ path }) => path.startsWith("_next/static/chunks/")), "inspect real client chunks");
  for (const [name, signature] of Object.entries(buildOnlySignatures)) {
    const installed = await readJavaScript(new URL(`../node_modules/${name}/`, import.meta.url));
    assert.ok(installed.some(({ text }) => text.includes(signature)), `${name} no longer contains its signature; update it`);
    const leaked = deployed.find(({ text }) => text.includes(signature));
    assert.equal(leaked, undefined, `${name} leaked into deployed ${leaked?.path}`);
  }
});
