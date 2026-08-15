import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const source = (path) => readFile(new URL(path, root), "utf8");

test("retention extensions hold expiry cleanup until the current migration finishes", async () => {
  const [schema, retention, cleanup] = await Promise.all([
    source("convex/schema.ts"),
    source("convex/retention.ts"),
    source("convex/cleanup.ts"),
  ]);

  assert.match(schema, /migrationRevision: v\.optional\(v\.number\(\)\)/);
  assert.match(retention, /nextDays === 0/);
  assert.match(retention, /nextDays > previousDays/);
  assert.match(retention, /existing\?\.migrationRevision !== undefined/);
  assert.match(retention, /migrationRevision: holdCleanup \? revision : undefined/);
  assert.match(cleanup, /setting\.migrationRevision === revision/);
  assert.match(cleanup, /migrationRevision: undefined/);
  assert.match(cleanup, /setting\?\.migrationRevision !== undefined/);
});

test("cleanup continuation requires a fully deleted batch, not a fully read batch", async () => {
  const cleanup = await source("convex/cleanup.ts");

  assert.match(cleanup, /expiredDeleted === cleanupBatchSize \|\| legacyDeleted === cleanupBatchSize/);
  assert.doesNotMatch(cleanup, /expired\.length === 100/);
  assert.doesNotMatch(cleanup, /legacyAnonymous\.length === 100/);
  assert.match(cleanup, /if \(item\.createdAt \+ anonymousRetentionMs > now\) break/);
  assert.match(cleanup, /!expiredPage\.isDone && scansLeft > 1/);
  assert.match(cleanup, /cursor: expiredPage\.continueCursor/);
});

test("held rows cannot head-of-line block cleanup and stale migrations restart", async () => {
  const cleanup = await source("convex/cleanup.ts");
  assert.match(cleanup, /cleanupScanPages = 10/);
  assert.match(cleanup, /now - setting\.updatedAt > staleMigrationMs/);
  assert.match(cleanup, /internal\.cleanup\.applyRetentionPage/);
  assert.match(cleanup, /revision: setting\.migrationRevision/);
});

test("stale retention migrations stop before reading or clearing current state", async () => {
  const cleanup = await source("convex/cleanup.ts");
  const staleGuard = cleanup.indexOf("setting.updatedAt !== revision || setting.days !== days");
  const pageRead = cleanup.indexOf('.query("transcriptions")');
  const clearHold = cleanup.indexOf("setting.migrationRevision === revision");

  assert.ok(staleGuard >= 0);
  assert.ok(pageRead > staleGuard);
  assert.ok(clearHold > pageRead);
});
