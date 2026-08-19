import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  anonymousContext,
  decryptHistoryField,
  encryptHistoryField,
  historyTextDigest,
  importHistoryKey,
  isEncryptedEnvelope,
  loadHistoryKey,
  ownerContext,
} from "../lib/server/historyCrypto.ts";
import { pseudonymousClientKey } from "../lib/server/clientKey.ts";

const root = new URL("../", import.meta.url);
const source = (path) => readFile(new URL(path, root), "utf8");

const keyBase64 = Buffer.alloc(32, 7).toString("base64");
const otherKeyBase64 = Buffer.alloc(32, 9).toString("base64");
const ctxA = ownerContext("user_aaa");
const ctxB = ownerContext("user_bbb");

test("history fields round-trip through the envelope and never store plaintext", async () => {
  const key = await importHistoryKey(keyBase64);
  const plaintext = "the quick brown fox — تجربة — 試験";
  const envelope = await encryptHistoryField(key, "text", ctxA, plaintext);
  assert.ok(isEncryptedEnvelope(envelope));
  assert.ok(!envelope.includes("quick brown"), "ciphertext must not contain plaintext");
  assert.equal(await decryptHistoryField(key, "text", ctxA, envelope), plaintext);
  // Fresh salt and IV every time: equal plaintexts must not produce equal envelopes.
  assert.notEqual(envelope, await encryptHistoryField(key, "text", ctxA, plaintext));
});

test("a large multi-byte payload round-trips (base64 helpers do not corrupt it)", async () => {
  const key = await importHistoryKey(keyBase64);
  const big = "字".repeat(60_000) + "🎧".repeat(5_000);
  assert.equal(await decryptHistoryField(key, "text", ctxA, await encryptHistoryField(key, "text", ctxA, big)), big);
});

test("tampered, truncated, wrong-key, and non-envelope inputs are rejected", async () => {
  const key = await importHistoryKey(keyBase64);
  const envelope = await encryptHistoryField(key, "text", ctxA, "sensitive transcript");
  const body = envelope.slice("$venc1$".length);
  const flipped = "$venc1$" + (body[0] === "A" ? "B" : "A") + body.slice(1);
  await assert.rejects(() => decryptHistoryField(key, "text", ctxA, flipped));
  await assert.rejects(() => decryptHistoryField(key, "text", ctxA, "$venc1$" + body.slice(0, 20)));
  const wrongKey = await importHistoryKey(otherKeyBase64);
  await assert.rejects(() => decryptHistoryField(wrongKey, "text", ctxA, envelope));
  await assert.rejects(() => decryptHistoryField(key, "text", ctxA, "plain old text"));
});

test("field and ownership binding prevent replaying an envelope elsewhere", async () => {
  const key = await importHistoryKey(keyBase64);
  const envelope = await encryptHistoryField(key, "text", ctxA, "bound to user A's text field");
  // Wrong field.
  await assert.rejects(() => decryptHistoryField(key, "summary", ctxA, envelope));
  // Wrong owner: a ciphertext transplanted into another account's row cannot open.
  await assert.rejects(() => decryptHistoryField(key, "text", ctxB, envelope));
  // Anonymous vs account context are distinct namespaces.
  await assert.rejects(() => decryptHistoryField(key, "text", anonymousContext("user_aaa"), envelope));
});

test("keys must be exactly 32 bytes and a missing secret fails closed", async () => {
  await assert.rejects(() => importHistoryKey(Buffer.alloc(16, 1).toString("base64")));
  assert.equal(loadHistoryKey(undefined), null);
  assert.equal(loadHistoryKey(""), null);
});

test("isEncryptedEnvelope rejects plaintext that merely starts with the prefix", () => {
  assert.equal(isEncryptedEnvelope("$venc1$ and then I said hello"), false, "short non-base64 body is not an envelope");
  assert.equal(isEncryptedEnvelope("$venc1$"), false);
  assert.equal(isEncryptedEnvelope("a normal transcript"), false);
});

test("the idempotency digest is keyed, per-operation, and content-sensitive", async () => {
  const key = await importHistoryKey(keyBase64);
  const digest = await historyTextDigest(key, "op-1", "same words");
  assert.equal(digest, await historyTextDigest(key, "op-1", "same words"));
  assert.notEqual(digest, await historyTextDigest(key, "op-1", "different words"));
  // Same text under a different operation id must NOT collide — Convex cannot
  // use the digest to correlate identical transcripts across records.
  assert.notEqual(digest, await historyTextDigest(key, "op-2", "same words"));
  assert.match(digest, /^[A-Za-z0-9+/]{43}=$/);
  const otherKey = await importHistoryKey(otherKeyBase64);
  assert.notEqual(digest, await historyTextDigest(otherKey, "op-1", "same words"), "digest must depend on the key");
});

test("spend-ledger client keys are pseudonymous and rotate daily", async () => {
  const day = Date.UTC(2026, 7, 17, 12);
  const key = await pseudonymousClientKey("server-secret", "203.0.113.7", day);
  assert.equal(key, await pseudonymousClientKey("server-secret", "203.0.113.7", day));
  assert.ok(key.startsWith("k1:"));
  assert.ok(!key.includes("203.0.113.7") && !key.includes("203"), "key must not embed the address");
  assert.notEqual(key, await pseudonymousClientKey("server-secret", "203.0.113.8", day));
  assert.notEqual(key, await pseudonymousClientKey("server-secret", "203.0.113.7", day + 24 * 60 * 60 * 1000), "keys must be unlinkable across days");
  assert.notEqual(key, await pseudonymousClientKey("other-secret", "203.0.113.7", day));
  assert.equal(await pseudonymousClientKey("server-secret", null, day), await pseudonymousClientKey("server-secret", null, day));
});

test("routes seal with ownership context, key the pseudonym off the web-only key, and isolate per-row decryption", async () => {
  const [route, transcribe, convex, schema] = await Promise.all([
    source("app/api/history/route.ts"),
    source("app/api/transcribe/route.ts"),
    source("convex/transcriptions.ts"),
    source("convex/schema.ts"),
  ]);
  assert.match(route, /encryptHistoryField\(secured\.historyKey, "text", context, plaintext\)/);
  assert.match(route, /historyTextDigest\(secured\.historyKey, operationId, plaintext\)/);
  assert.match(route, /decryptHistoryField\(secured\.historyKey, field, context, value\)/);
  // Context comes from Convex's VERIFIED identity, never a local token decode,
  // so seal-context and storage/read-context can never diverge.
  assert.match(route, /transcriptions:viewerContext/);
  assert.match(route, /result\.ownerContext \?\? anonymousContext\(clientId\)/);
  assert.match(convex, /export const viewerContext = query/);
  assert.doesNotMatch(route, /clerkSubjectFromToken/);
  // The local anonymous shortcut applies ONLY when NO bearer token exists (so
  // setAuth was never called); whenever ANY token is present — valid or not —
  // the context must come from the Convex-verified query, never a local guess.
  assert.match(route, /if \(!secured\.hasToken\) return anonymousContext\(clientId\);/);
  assert.match(route, /const hasToken = authorization\?\.startsWith\("Bearer "\) \?\? false;/);
  assert.match(route, /if \(hasToken\) client\.setAuth/);
  // Per-row, per-field isolation: one bad envelope must not 503 the whole page,
  // and a failed summary must be dropped (not leaked as ciphertext via ...item).
  assert.match(route, /catch \{\s*return \{ value: "", failed: true \}/);
  assert.match(route, /const \{ summary: _storedSummary, \.\.\.rest \} = item;/);
  assert.match(route, /summary !== undefined && !summary\.failed \? \{ summary: summary\.value \}/);
  assert.match(route, /text\.failed \? \{ decryptError: true \}/);
  assert.match(route, /summary\?\.failed \? \{ summaryDecryptError: true \}/);
  assert.match(route, /loadHistoryKey\(process\.env\.HISTORY_ENCRYPTION_KEY\)/);
  // The pseudonym HMAC key must be the web-only history key and must FAIL CLOSED
  // (no silent fallback to the shared ASR credential).
  assert.match(transcribe, /const pseudonymSecret = process\.env\.HISTORY_ENCRYPTION_KEY;/);
  assert.match(transcribe, /pseudonymousClientKey\(pseudonymSecret,/);
  assert.doesNotMatch(transcribe, /\?\? apiKey/);
  assert.match(transcribe, /!pseudonymSecret/);
  assert.match(schema, /textHash: v\.optional\(v\.string\(\)\)/);
  assert.doesNotMatch(convex, /HISTORY_ENCRYPTION_KEY/, "Convex must never hold the history key");
  assert.match(convex, /existingOperation\.textHash === args\.textHash/);
});

test("history writes start the verified-context round trip before parsing the body", async () => {
  const route = await source("app/api/history/route.ts");
  // POST and PATCH overlap the Convex viewerContext round trip with body
  // parse/validation: the query starts as soon as securedClient returns and is
  // awaited only at encryption time.
  for (const name of ["POST", "PATCH"]) {
    const start = route.indexOf(`export async function ${name}`);
    assert.ok(start >= 0, `${name} handler exists`);
    const next = route.indexOf("export async function", start + 1);
    const block = route.slice(start, next === -1 ? route.length : next);
    const kickoff = block.indexOf("startViewerContext(secured)");
    const parse = block.indexOf("readBoundedJson");
    assert.ok(kickoff >= 0, `${name} starts the viewer-context query eagerly`);
    assert.ok(parse >= 0 && kickoff < parse, `${name} starts context resolution before parsing the body`);
  }
  // The eager query observes its own rejection so an early 400 exit cannot
  // raise an unhandled rejection, while resolveContext awaits the original
  // promise so the real error still lands in the fail-closed catch.
  assert.match(route, /void pending\.catch\(\(\) => \{\}\);/);
  assert.match(route, /await resolveContext\(secured, pendingContext, clientId\)/);
  assert.match(route, /await resolveContext\(secured, pendingContext, body\.clientId\)/);
  // Fail closed: a token-bearing request that somehow skipped the kickoff must
  // throw into the 503 path, never guess a context locally.
  assert.match(route, /if \(!pendingContext\) throw new Error/);
  // GET and DELETE never resolve a write context, so they must not pay the
  // extra viewerContext query.
  const readBlock = route.slice(route.indexOf("export async function GET"), route.indexOf("export async function PATCH"));
  const deleteBlock = route.slice(route.indexOf("export async function DELETE"));
  assert.doesNotMatch(readBlock, /startViewerContext/);
  assert.doesNotMatch(deleteBlock, /startViewerContext/);
});

test("history GET is one combined Convex query whose ownerContext comes from the same verified identity as the page", async () => {
  const [route, convex, retention] = await Promise.all([
    source("app/api/history/route.ts"),
    source("convex/transcriptions.ts"),
    source("convex/retention.ts"),
  ]);
  // One round trip: page + retention + ownership context from a single
  // getUserIdentity(), so the open context can never diverge from the identity
  // that selected the rows.
  assert.match(route, /transcriptions:historyPage/);
  assert.match(route, /const context = result\.ownerContext \?\? anonymousContext\(clientId\);/);
  assert.match(route, /retentionDays: result\.retentionDays \?\? null/);
  // The replaced per-request calls are gone from the GET path and their dead
  // Convex exports are removed.
  assert.doesNotMatch(route, /transcriptions:list/);
  assert.doesNotMatch(route, /retention:get/);
  assert.doesNotMatch(convex, /export const list = query/);
  assert.doesNotMatch(retention, /export const get = query/);
  // The combined query stays service-secret-gated, validates the clientId, and
  // derives ownerContext through the same helper viewerContext uses.
  const historyPageBlock = convex.slice(convex.indexOf("export const historyPage"), convex.indexOf("export const save"));
  assert.match(historyPageBlock, /requireServiceSecret\(serviceSecret\)/);
  assert.match(historyPageBlock, /clientIdPattern\.test\(clientId\)/);
  assert.match(historyPageBlock, /ownerContext: verifiedOwnerContext\(identity\)/);
  assert.match(historyPageBlock, /ownerContext: null/);
  assert.match(historyPageBlock, /retentionDays: null/);
  assert.match(convex, /identity \? verifiedOwnerContext\(identity\) : null/);
  assert.equal(convex.match(/getUserIdentity\(\)/g).length >= 1, true);
});

test("Convex service-secret checks are constant-time and shared; migration is gated", async () => {
  const [auth, transcriptions, retention] = await Promise.all([
    source("convex/serviceAuth.ts"),
    source("convex/transcriptions.ts"),
    source("convex/retention.ts"),
  ]);
  assert.match(auth, /timingSafeEqualStrings/);
  assert.doesNotMatch(auth, /value !== process\.env/);
  for (const file of [transcriptions, retention]) {
    assert.match(file, /from "\.\/serviceAuth"/);
    assert.doesNotMatch(file, /function requireServiceSecret/);
  }
  // The broad plaintext read is inert unless explicitly enabled for a migration.
  assert.match(transcriptions, /HISTORY_MIGRATION_ENABLED !== "true"/);
  assert.match(transcriptions, /export const plaintextPage[\s\S]{0,500}requireMigrationEnabled\(\)/);
  assert.match(transcriptions, /export const applyCipher[\s\S]{0,800}requireMigrationEnabled\(\)/);
});

test("a summary write must be sealed to a context the read path can reconstruct", async () => {
  // A signed-in PATCH on a pre-sign-in anonymous row would seal to o:<sub> but
  // only ever be read back under a:<clientId>; saveSummary must reject it rather
  // than persist an undecryptable envelope. remove() stays context-free.
  const transcriptions = await source("convex/transcriptions.ts");
  const saveSummaryBlock = transcriptions.slice(transcriptions.indexOf("export const saveSummary"));
  assert.match(saveSummaryBlock, /const ownsAnonymousItem = !identity && item\.clientId === clientId && !item\.ownerId;/);
  const removeBlock = transcriptions.slice(transcriptions.indexOf("export const remove"), transcriptions.indexOf("export const clearAll"));
  assert.match(removeBlock, /const ownsAnonymousItem = item\.clientId === clientId && !item\.ownerId;/);
});

test("migration backfills an operationId so no plaintext row is left behind", async () => {
  const [script, transcriptions] = await Promise.all([
    source("scripts/encrypt-history.mjs"),
    source("convex/transcriptions.ts"),
  ]);
  assert.match(script, /item\.operationId \?\? crypto\.randomUUID\(\)/);
  assert.doesNotMatch(script, /!item\.operationId \) \{ skipped/);
  assert.match(transcriptions, /if \(item\.operationId === undefined && args\.operationId !== undefined\)/);
});

test("every user history row is reachable by a bulk purge that deletes before it reports success", async () => {
  const [transcriptions, cleanup, http] = await Promise.all([
    source("convex/transcriptions.ts"),
    source("convex/cleanup.ts"),
    source("convex/http.ts"),
  ]);
  assert.match(transcriptions, /export const clearAll = mutation/);
  // First batch is deleted inline so an immediate refetch sees them gone.
  assert.match(transcriptions, /for \(const item of owned\) \{\s*await ctx\.db\.delete\(item\._id\);/);
  assert.match(transcriptions, /if \(owned\.length === clearAllBatchSize\)/);
  assert.match(cleanup, /export const purgeHistoryPage = internalMutation/);
  assert.match(cleanup, /if \(deleted === cleanupBatchSize\)/);
  assert.match(http, /user\.deleted/);
  assert.match(http, /removeSettings: true/);
  assert.match(http, /svix-signature/);
  assert.match(http, /TIMESTAMP_TOLERANCE_SECONDS/);
});
