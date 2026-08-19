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

  assert.match(cleanup, /else if \(expiredDeleted === cleanupBatchSize\)/);
  assert.doesNotMatch(cleanup, /expired\.length === 100/);
  assert.doesNotMatch(cleanup, /expiredPage\.page\.length === cleanupBatchSize/);
  assert.match(cleanup, /!expiredPage\.isDone && scansLeft > 1/);
  assert.match(cleanup, /cursor: expiredPage\.continueCursor/);
});

test("the cron never table-scans for legacy rows; a bounded backfill drains them onto the indexed sweep", async () => {
  const cleanup = await source("convex/cleanup.ts");

  // The per-tick unindexed `.filter` over ownerId/expiresAt-undefined is gone:
  // every database query in cleanup walks an index.
  assert.doesNotMatch(cleanup, /\.filter\(\(q\)/);
  assert.doesNotMatch(cleanup, /q\.field\(/);
  const sweep = cleanup.slice(cleanup.indexOf("export const deleteExpiredTranscriptions"), cleanup.indexOf("export const countLegacyAnonymous"));
  assert.doesNotMatch(sweep, /expiresAt", undefined/);
  assert.match(sweep, /withIndex\("by_expires_at", \(q\) => q\.gt\("expiresAt", 0\)\.lte\("expiresAt", now\)\)/);

  // The one-off operator tools are bounded and use the by_expires_at index at
  // expiresAt === undefined instead of scanning the table.
  assert.match(cleanup, /export const countLegacyAnonymous = internalQuery/);
  assert.match(cleanup, /export const backfillLegacyAnonymous = internalMutation/);
  const count = cleanup.slice(cleanup.indexOf("export const countLegacyAnonymous"), cleanup.indexOf("export const backfillLegacyAnonymous"));
  assert.match(count, /withIndex\("by_expires_at", \(q\) => q\.eq\("expiresAt", undefined\)\)/);
  assert.match(count, /\.take\(bounded\)/);
  const backfill = cleanup.slice(cleanup.indexOf("export const backfillLegacyAnonymous"));
  assert.match(backfill, /withIndex\("by_expires_at", \(q\) => q\.eq\("expiresAt", undefined\)\)/);
  assert.match(backfill, /paginate\(\{ cursor: cursor \?\? null, numItems: cleanupBatchSize \}\)/);
  // Owned keep-until-deleted rows share the expiresAt-undefined range and must
  // never be stamped; legacy anonymous rows get the one-hour policy they predate.
  assert.match(backfill, /if \(item\.ownerId !== undefined\) continue;/);
  assert.match(backfill, /expiresAt: item\.createdAt \+ anonymousRetentionMs/);
  assert.match(backfill, /internal\.cleanup\.backfillLegacyAnonymous, \{ cursor: page\.continueCursor \}/);
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
