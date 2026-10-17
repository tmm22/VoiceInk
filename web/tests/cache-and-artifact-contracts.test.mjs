import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { evaluateAuditReport } from "../scripts/check-audit.mjs";
import { findDuplicateArtifacts } from "../scripts/check-duplicates.mjs";

test("API responses are centrally private while HTML retains per-request CSP nonces", async () => {
  const [source, worker] = await Promise.all([
    readFile(new URL("../worker/securityHeaders.ts", import.meta.url), "utf8"),
    readFile(new URL("../worker/index.ts", import.meta.url), "utf8"),
  ]);
  assert.match(source, /"Cache-Control": "private, no-store, max-age=0, must-revalidate"/);
  assert.match(source, /Pragma: "no-cache"/);
  assert.match(source, /Expires: "0"/);
  assert.match(source, /pathname === "\/api" \|\| pathname\.startsWith\("\/api\/"\)/);
  // Every Worker response passes through the security headers, and the
  // document gets a fresh nonce stamped onto its scripts and module preloads.
  assert.match(worker, /return applySecurityHeaders\(response, pathname, nonce\);/);
  assert.match(worker, /\.on\("script", stampNonce\)/);
  assert.match(worker, /\.on\('link\[rel="modulepreload"\]', stampNonce\)/);
  assert.match(worker, /"Cache-Control": "no-store, must-revalidate"/);
  assert.match(source, /btoa\(crypto\.randomUUID\(\)\)/);
  assert.doesNotMatch(source, /sensitiveResponseHeaders[^;]+for \(const \[name, value\][^}]+\}\s*return/s);
});

test("tracked static header policy caches only content-hashed assets immutably", async () => {
  const headers = await readFile(new URL("../public/_headers", import.meta.url), "utf8");
  // Vite emits content-hashed scripts and stylesheets under /assets/.
  assert.match(headers, /\/assets\/\*[\s\S]*public, max-age=31536000, immutable/);
  assert.doesNotMatch(headers, /\/_next\//);
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

test("the audit gate blocks every high or critical advisory with no exceptions", () => {
  const finding = (severity) => ({ severity, isDirect: false, via: [], effects: [] });
  const report = { vulnerabilities: {
    braces: finding("high"),
    vinext: finding("high"),
    lodash: finding("critical"),
    postcss: finding("moderate"),
    tiny: finding("low"),
  } };
  assert.deepEqual(evaluateAuditReport(report), { blocked: ["braces", "lodash", "vinext"] });
  assert.deepEqual(evaluateAuditReport({}), { blocked: [] });
});
