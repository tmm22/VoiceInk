import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
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
  assert.match(headers, /\/assets\/\*[\s\S]*public, max-age=31536000, immutable/);
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

test("audit exception is exact, transitive, and expires", () => {
  const exactReport = {
    vulnerabilities: {
      "image-size": {
        severity: "high",
        isDirect: false,
        via: [
          { url: "https://github.com/advisories/GHSA-w3rx-r6r6-pgpr" },
          { url: "https://github.com/advisories/GHSA-5p2g-fcmc-qvqq" },
        ],
        effects: ["vinext"],
      },
      vinext: { severity: "high", isDirect: true, via: ["image-size"], effects: [] },
    },
  };
  assert.deepEqual(evaluateAuditReport(exactReport, { allowImageSize: true, today: "2026-08-15" }), {
    allowed: ["image-size", "vinext"],
    blocked: [],
  });
  assert.deepEqual(evaluateAuditReport(exactReport, { allowImageSize: true, today: "2026-09-16" }).blocked, ["image-size", "vinext"]);

  const unrelated = structuredClone(exactReport);
  unrelated.vulnerabilities.other = { severity: "critical", via: [], effects: [] };
  assert.deepEqual(evaluateAuditReport(unrelated, { allowImageSize: true, today: "2026-08-15" }).blocked, ["other"]);
  const directImageSize = structuredClone(exactReport);
  directImageSize.vulnerabilities["image-size"].isDirect = true;
  assert.deepEqual(evaluateAuditReport(directImageSize, { allowImageSize: true, today: "2026-08-15" }).blocked, ["image-size"]);
});
