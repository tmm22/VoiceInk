#!/usr/bin/env node
// One-off migration: seal pre-existing plaintext history rows in Convex with
// the same envelope format new writes use, bound to each row's ownership
// context so the read path can reconstruct it. Safe to re-run; already-sealed
// rows are skipped and racing edits are left alone by applyCipher's guards.
//
// Requires HISTORY_MIGRATION_ENABLED=true in the Convex environment for the
// duration of the run (unset it afterwards). Run from web/:
//   CONVEX_URL=https://<deployment>.convex.cloud \
//   CONVEX_WEB_API_SECRET=... HISTORY_ENCRYPTION_KEY=... \
//   node --experimental-strip-types scripts/encrypt-history.mjs
import { ConvexHttpClient } from "convex/browser";
import { makeFunctionReference } from "convex/server";
import {
  anonymousContext,
  encryptHistoryField,
  historyTextDigest,
  importHistoryKey,
  ownerContext,
} from "../lib/server/historyCrypto.ts";

const convexUrl = process.env.CONVEX_URL ?? process.env.NEXT_PUBLIC_CONVEX_URL;
const serviceSecret = process.env.CONVEX_WEB_API_SECRET;
const keySecret = process.env.HISTORY_ENCRYPTION_KEY;
if (!convexUrl || !serviceSecret || !keySecret) {
  console.error("CONVEX_URL (or NEXT_PUBLIC_CONVEX_URL), CONVEX_WEB_API_SECRET, and HISTORY_ENCRYPTION_KEY are required.");
  process.exit(1);
}

// Mirrors the read path: account rows bind to the Clerk subject (the segment of
// the Convex tokenIdentifier after the issuer bar), anonymous rows to clientId.
function contextFor(row) {
  if (row.ownerId) {
    const subject = String(row.ownerId).split("|").pop();
    return subject ? ownerContext(subject) : null;
  }
  return row.clientId ? anonymousContext(row.clientId) : null;
}

const key = await importHistoryKey(keySecret);
const client = new ConvexHttpClient(convexUrl);
const plaintextPage = makeFunctionReference("transcriptions:plaintextPage");
const applyCipher = makeFunctionReference("transcriptions:applyCipher");

let cursor = null;
let migrated = 0;
let skipped = 0;
for (;;) {
  const page = await client.query(plaintextPage, { cursor, serviceSecret });
  for (const item of page.items) {
    const context = contextFor(item);
    if (!context) { skipped += 1; console.warn(`skipped ${item.id}: no ownership context`); continue; }
    // Legacy rows may predate operation ids; backfill one so the digest stays
    // bound to an operationId and the row is not reselected next run. The
    // save-path dedupe only ever looks up rows by a client-supplied operationId,
    // so a backfilled id can never collide with a live write.
    const operationId = item.operationId ?? crypto.randomUUID();
    const args = { id: item.id, serviceSecret };
    if (item.text !== undefined && !item.text.startsWith("$venc1$")) {
      args.text = await encryptHistoryField(key, "text", context, item.text);
      args.textHash = await historyTextDigest(key, operationId, item.text);
      args.expectedTextLength = item.text.length;
      if (item.operationId === undefined) args.operationId = operationId;
    }
    if (item.summary !== undefined && !item.summary.startsWith("$venc1$")) {
      args.summary = await encryptHistoryField(key, "summary", context, item.summary);
      args.expectedSummaryLength = item.summary.length;
    }
    if (args.text === undefined && args.summary === undefined) continue;
    await client.mutation(applyCipher, args);
    migrated += 1;
  }
  if (page.isDone) break;
  cursor = page.continueCursor;
}
console.log(`Sealed ${migrated} history record(s)${skipped ? `, skipped ${skipped} without an ownership context or operation id` : ""}.`);
