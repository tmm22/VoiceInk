import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const source = (path) => readFile(new URL(path, root), "utf8");

// Regression coverage for the per-owner quota aggregate (ownerStats): quota
// math on save must read the tiny aggregate row instead of paging full
// ciphertext documents, and every mutation that inserts, deletes, or resizes
// an owned transcription must keep the aggregate consistent in the same
// transaction — otherwise limits drift and either lock users out or stop
// enforcing.

test("the ownerStats table exists with a by_owner index and the shared helpers", async () => {
  const [schema, ownerStats] = await Promise.all([
    source("convex/schema.ts"),
    source("convex/ownerStats.ts"),
  ]);
  assert.match(schema, /ownerStats: defineTable\(\{\s*ownerId: v\.string\(\),\s*itemCount: v\.number\(\),\s*storedChars: v\.number\(\),\s*\}\)\.index\("by_owner", \["ownerId"\]\)/);
  // Lazy initialization is one bounded read of the owner's existing rows and
  // counts text plus summary characters, matching the pre-aggregate math.
  assert.match(ownerStats, /export async function ensureOwnerStats/);
  assert.match(ownerStats, /\.take\(initializationScanLimit\)/);
  assert.match(ownerStats, /const initializationScanLimit = 200;/);
  assert.match(ownerStats, /item\.text\.length \+ \(item\.summary\?\.length \?\? 0\)/);
  // Deltas clamp at zero and an absent row is a no-op (the next save's lazy
  // initialization reads ground truth, so skipping cannot drift).
  assert.match(ownerStats, /if \(!stats\) return;/);
  assert.match(ownerStats, /Math\.max\(0, stats\.itemCount \+ deltaItems\)/);
  assert.match(ownerStats, /Math\.max\(0, stats\.storedChars \+ deltaChars\)/);
});

test("save enforces quotas from the aggregate, initialized before the insert it then counts", async () => {
  const transcriptions = await source("convex/transcriptions.ts");
  const save = transcriptions.slice(transcriptions.indexOf("export const save = mutation"), transcriptions.indexOf("export const remove"));
  const ensureAt = save.indexOf("ensureOwnerStats(ctx, identity.tokenIdentifier)");
  const insertAt = save.indexOf('ctx.db.insert("transcriptions"');
  const adjustAt = save.indexOf("adjustOwnerStats(ctx, identity.tokenIdentifier, 1, text.length)");
  assert.ok(ensureAt >= 0 && insertAt > ensureAt && adjustAt > insertAt,
    "ensure (bounded init) must run before the insert, and the increment after it, so the new row is never double counted");
  // Same limits as before the aggregate: 50 items, 10,000,000 characters, and
  // ten writes per minute from a ten-row read instead of fifty-one.
  assert.match(save, /stats\.itemCount >= ownerItemLimit[\s\S]{0,120}Account history limit reached/);
  assert.match(save, /stats\.storedChars \+ text\.length > ownerStoredCharsLimit[\s\S]{0,120}Account storage limit reached/);
  assert.match(save, /\.order\("desc"\)\.take\(10\)/);
  assert.match(save, /recent\.length >= 10 && recent\[9\]\.createdAt > createdAt - 60_000[\s\S]{0,120}Transcription write limit reached/);
  // The idempotent-retry path returns before any quota mutation.
  assert.ok(save.indexOf("return existingOperation._id") < ensureAt);
});

test("every mutation that deletes or resizes an owned row adjusts the aggregate transactionally", async () => {
  const [transcriptions, cleanup] = await Promise.all([
    source("convex/transcriptions.ts"),
    source("convex/cleanup.ts"),
  ]);
  const section = (text, from, to) => text.slice(text.indexOf(from), to ? text.indexOf(to) : undefined);

  const remove = section(transcriptions, "export const remove", "export const clearAll");
  assert.match(remove, /if \(item\.ownerId\) await adjustOwnerStats\(ctx, item\.ownerId, -1, -historyItemChars\(item\)\);/);

  const clearAll = section(transcriptions, "export const clearAll", "export const saveSummary");
  assert.match(clearAll, /ownedChars \+= historyItemChars\(item\);/);
  assert.match(clearAll, /adjustOwnerStats\(ctx, ownerId, -owned\.length, -ownedChars\)/);

  const saveSummary = section(transcriptions, "export const saveSummary", "export const plaintextPage");
  assert.match(saveSummary, /adjustOwnerStats\(ctx, item\.ownerId, 0, normalizedSummary\.length - \(item\.summary\?\.length \?\? 0\)\)/);

  // Cleanup deletions: the scheduled purge and the expiry sweep both decrement
  // per deleted owned row.
  const purge = section(cleanup, "export const purgeHistoryPage", "export const deleteExpiredTranscriptions");
  assert.match(purge, /deletedChars \+= historyItemChars\(item\);/);
  assert.match(purge, /adjustOwnerStats\(ctx, ownerId, -deleted, -deletedChars\)/);
  const sweep = section(cleanup, "export const deleteExpiredTranscriptions", "export const countLegacyAnonymous");
  assert.match(sweep, /delta\.chars \+= historyItemChars\(item\);/);
  assert.match(sweep, /adjustOwnerStats\(ctx, ownerId, -delta\.items, -delta\.chars\)/);

  // Account deletion drops the aggregate row with the retention setting so
  // nothing keyed to the identity survives.
  assert.match(purge, /await removeOwnerStats\(ctx, ownerId\);/);
});

test("the unreachable daily counter is gone and no full-history quota read remains in save", async () => {
  const transcriptions = await source("convex/transcriptions.ts");
  // The old check filtered a take(51) read for a count of 100 — always false.
  assert.doesNotMatch(transcriptions, /Daily transcription limit reached/);
  assert.doesNotMatch(transcriptions, /\.take\(51\)/);
});
