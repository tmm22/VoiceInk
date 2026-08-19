import { paginationOptsValidator } from "convex/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import { mutation, query } from "./_generated/server";
import { adjustOwnerStats, ensureOwnerStats, historyItemChars, ownerItemLimit, ownerStoredCharsLimit } from "./ownerStats";
import { requireServiceSecret } from "./serviceAuth";

const dayMs = 24 * 60 * 60 * 1000;
const defaultRetentionDays = 90;
const clientIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const operationIdPattern = clientIdPattern;
// Web-Worker-produced envelope prefix (see lib/server/historyCrypto.ts) and
// the base64 shape of its keyed idempotency digest. The Worker encrypts before
// calling Convex, so stored text is a ciphertext envelope, never plaintext.
const envelopePrefix = "$venc1$";
const textHashPattern = /^[A-Za-z0-9+/]{43}=$/;
// A 200k-character plaintext cap becomes ~267k characters of base64 envelope.
const maximumStoredTextLength = 320_000;
const clearAllBatchSize = 100;

// The one-off encryption migration reads plaintext across all rows, so its two
// functions are inert unless this flag is explicitly set in the Convex
// environment for the migration window and removed afterwards. Without it, no
// holder of the web service secret can page through every user's plaintext.
function requireMigrationEnabled() {
  if (process.env.HISTORY_MIGRATION_ENABLED !== "true") throw new Error("History migration is not enabled.");
}

function publicHistoryItem(item: {
  _id: unknown; model: string; detectedLanguage?: string; text: string; summary?: string; durationSeconds: number;
  segments?: Array<{ start: number; end: number; text: string }>; operationId?: string;
  status: "processing" | "complete" | "failed"; createdAt: number;
}) {
  return {
    _id: item._id,
    model: item.model,
    ...(item.detectedLanguage ? { detectedLanguage: item.detectedLanguage } : {}),
    text: item.text,
    ...(item.summary ? { summary: item.summary } : {}),
    durationSeconds: item.durationSeconds,
    ...(item.segments?.length ? { segments: item.segments } : {}),
    ...(item.operationId ? { operationId: item.operationId } : {}),
    status: item.status,
    createdAt: item.createdAt,
  };
}

// The envelope ownership context for a verified identity: the
// tokenIdentifier's final segment, matching the read path and the migration.
function verifiedOwnerContext(identity: { tokenIdentifier: string }): string {
  return `o:${identity.tokenIdentifier.split("|").pop()}`;
}

// The single source of truth for the envelope ownership context. Convex
// verifies the caller's token here exactly as save/historyPage/saveSummary do,
// so the worker seals and opens with the SAME owner-vs-anonymous decision
// Convex uses to place and return rows — a present-but-invalid token can never
// make the seal context (worker) diverge from the storage/read context
// (Convex). Used by the write paths; the read path gets the same context from
// historyPage's single round trip.
export const viewerContext = query({
  args: { serviceSecret: v.optional(v.string()) },
  handler: async (ctx, { serviceSecret }) => {
    requireServiceSecret(serviceSecret);
    const identity = await ctx.auth.getUserIdentity();
    return { ownerContext: identity ? verifiedOwnerContext(identity) : null };
  },
});

// The one query behind history GET: page, retention setting, and the verified
// ownership context in a single getUserIdentity() round trip. ownerContext is
// derived from the SAME verified identity that selects which rows are
// returned, so the worker's open context can never diverge from the storage
// context — a present-but-invalid token yields a null identity, no owned rows,
// and a null ownerContext together.
export const historyPage = query({
  args: { clientId: v.string(), paginationOpts: paginationOptsValidator, serviceSecret: v.optional(v.string()) },
  handler: async (ctx, { clientId, paginationOpts, serviceSecret }) => {
    requireServiceSecret(serviceSecret);
    if (!clientIdPattern.test(clientId)) throw new Error("Invalid client identifier.");
    const identity = await ctx.auth.getUserIdentity();
    if (identity) {
      const [result, setting] = await Promise.all([
        ctx.db
          .query("transcriptions")
          .withIndex("by_owner_created", (q) => q.eq("ownerId", identity.tokenIdentifier))
          .order("desc")
          .paginate({ ...paginationOpts, numItems: Math.min(paginationOpts.numItems, 25) }),
        ctx.db
          .query("retentionSettings")
          .withIndex("by_owner", (q) => q.eq("ownerId", identity.tokenIdentifier))
          .unique(),
      ]);
      const now = Date.now();
      return {
        page: result.page.filter((item) => item.expiresAt === undefined || item.expiresAt > now).map(publicHistoryItem),
        isDone: result.isDone,
        continueCursor: result.continueCursor,
        retentionDays: setting?.days ?? defaultRetentionDays,
        ownerContext: verifiedOwnerContext(identity),
      };
    }

    const now = Date.now();
    const items = await ctx.db
      .query("transcriptions")
      .withIndex("by_client_created", (q) => q.eq("clientId", clientId))
      .order("desc")
      .take(30);
    return {
      page: items.filter((item) => (item.expiresAt ?? item.createdAt + 60 * 60 * 1000) > now).map(publicHistoryItem),
      isDone: true,
      continueCursor: "",
      retentionDays: null,
      ownerContext: null,
    };
  },
});

export const save = mutation({
  args: {
    clientId: v.string(), model: v.string(), text: v.string(), durationSeconds: v.number(), operationId: v.string(),
    textHash: v.optional(v.string()),
    detectedLanguage: v.optional(v.string()),
    segments: v.optional(v.array(v.object({ start: v.number(), end: v.number(), text: v.string() }))),
    serviceSecret: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    requireServiceSecret(args.serviceSecret);
    const text = args.text.trim();
    if (!clientIdPattern.test(args.clientId)) throw new Error("Invalid client identifier.");
    if (!operationIdPattern.test(args.operationId)) throw new Error("Invalid operation identifier.");
    if (!text || text.length > maximumStoredTextLength) throw new Error("Transcript length is invalid.");
    if (args.textHash !== undefined && !textHashPattern.test(args.textHash)) throw new Error("Invalid transcript digest.");
    if (args.model !== "nova-3" && args.model !== "whisper-large-v3-turbo") throw new Error("Unsupported transcription model.");
    if (args.detectedLanguage !== undefined && (
      args.detectedLanguage.length > 35 || !/^[a-z]{2,3}(-[a-z0-9]{2,8})*$/i.test(args.detectedLanguage)
    )) throw new Error("Invalid detected language.");
    if (!Number.isFinite(args.durationSeconds) || args.durationSeconds < 0 || args.durationSeconds > 21_600) throw new Error("Invalid recording duration.");
    if (args.segments && (args.segments.length > 5_000 || args.segments.some((segment, index) =>
      !segment.text.trim() || segment.text.length > 2_000 || !Number.isFinite(segment.start) || !Number.isFinite(segment.end)
      || segment.start < 0 || segment.end <= segment.start || segment.end > 21_600
      || (index > 0 && segment.start < args.segments![index - 1].start)))) throw new Error("Invalid transcription timing.");
    const createdAt = Date.now();
    const { clientId } = args;
    const existingOperation = identity
      ? await ctx.db.query("transcriptions")
        .withIndex("by_owner_operation", (q) => q.eq("ownerId", identity.tokenIdentifier).eq("operationId", args.operationId)).unique()
      : await ctx.db.query("transcriptions")
        .withIndex("by_client_operation", (q) => q.eq("clientId", clientId).eq("operationId", args.operationId)).unique();
    if (existingOperation) {
      // Ciphertext envelopes differ on every encryption, so content equality is
      // checked through the keyed digest. A legacy plaintext row retried after
      // the encryption rollout has no digest to compare; the operation id plus
      // model and duration is the best remaining evidence, so trust it.
      const sameContent = existingOperation.textHash !== undefined && args.textHash !== undefined
        ? existingOperation.textHash === args.textHash
        : existingOperation.textHash === undefined && args.textHash === undefined
          ? existingOperation.text === text
          : true;
      if (!sameContent || existingOperation.model !== args.model || existingOperation.durationSeconds !== args.durationSeconds) {
        throw new Error("Operation identifier was already used for different content.");
      }
      return existingOperation._id;
    }
    const transcription = { model: args.model, text: args.text, durationSeconds: args.durationSeconds, operationId: args.operationId, ...(args.textHash ? { textHash: args.textHash } : {}), ...(args.detectedLanguage ? { detectedLanguage: args.detectedLanguage.toLowerCase() } : {}), ...(args.segments?.length ? { segments: args.segments } : {}) };
    let accountRetentionDays = defaultRetentionDays;
    if (identity) {
      // Quota math reads the tiny per-owner aggregate instead of paging full
      // ciphertext documents; the aggregate is maintained transactionally by
      // every mutation that inserts, deletes, or resizes an owned row.
      const stats = await ensureOwnerStats(ctx, identity.tokenIdentifier);
      if (stats.itemCount >= ownerItemLimit) throw new Error("Account history limit reached. Delete older items or shorten retention.");
      if (stats.storedChars + text.length > ownerStoredCharsLimit) throw new Error("Account storage limit reached.");
      // Burst limit: ten writes per minute. Newest-first, so ten-or-more items
      // inside the window is exactly "the tenth-newest item is inside it" —
      // the same decision the previous 51-row filter made, from ten rows.
      // (The former "100 per day" check was unreachable: it filtered a read
      // bounded at 51 rows for a count of 100, and the 50-item cap above keeps
      // any equivalent count unreachable, so it is deliberately removed.)
      const recent = await ctx.db.query("transcriptions").withIndex("by_owner_created", (q) => q.eq("ownerId", identity.tokenIdentifier)).order("desc").take(10);
      if (recent.length >= 10 && recent[9].createdAt > createdAt - 60_000) throw new Error("Transcription write limit reached. Please wait.");
      const setting = await ctx.db
        .query("retentionSettings")
        .withIndex("by_owner", (q) => q.eq("ownerId", identity.tokenIdentifier))
        .unique();
      if (setting) accountRetentionDays = setting.days;
      else await ctx.db.insert("retentionSettings", {
        ownerId: identity.tokenIdentifier,
        days: defaultRetentionDays,
        updatedAt: createdAt,
      });
    } else {
      const recent = await ctx.db.query("transcriptions").withIndex("by_client_created", (q) => q.eq("clientId", clientId)).order("desc").take(31);
      if (recent.filter((item) => (item.expiresAt ?? 0) > createdAt).length >= 30) throw new Error("Anonymous history limit reached. Sign in or wait for older items to expire.");
    }
    const id = await ctx.db.insert("transcriptions", {
      ...transcription,
      text,
      ...(identity
        ? {
            ownerId: identity.tokenIdentifier,
            ...(accountRetentionDays === 0 ? {} : { expiresAt: createdAt + accountRetentionDays * dayMs }),
          }
        : { clientId, expiresAt: createdAt + 60 * 60 * 1000 }),
      status: "complete",
      createdAt,
    });
    // The aggregate was ensured above (before this insert), so the new row is
    // never double counted by the lazy initialization read.
    if (identity) await adjustOwnerStats(ctx, identity.tokenIdentifier, 1, text.length);
    return id;
  },
});

export const remove = mutation({
  args: { id: v.id("transcriptions"), clientId: v.string(), serviceSecret: v.optional(v.string()) },
  handler: async (ctx, { id, clientId, serviceSecret }) => {
    requireServiceSecret(serviceSecret);
    if (!clientIdPattern.test(clientId)) throw new Error("Invalid client identifier.");
    const item = await ctx.db.get(id);
    if (!item) return;
    const identity = await ctx.auth.getUserIdentity();
    const ownsAccountItem = identity && item.ownerId === identity.tokenIdentifier;
    // Anonymous rows stay reachable after sign-in: the browser still holds the
    // clientId that created them, so it may delete them.
    const ownsAnonymousItem = item.clientId === clientId && !item.ownerId;
    if (!ownsAccountItem && !ownsAnonymousItem) throw new Error("Not authorized to delete this transcription.");
    await ctx.db.delete(id);
    if (item.ownerId) await adjustOwnerStats(ctx, item.ownerId, -1, -historyItemChars(item));
  },
});

export const clearAll = mutation({
  args: { clientId: v.string(), serviceSecret: v.optional(v.string()) },
  handler: async (ctx, { clientId, serviceSecret }) => {
    requireServiceSecret(serviceSecret);
    if (!clientIdPattern.test(clientId)) throw new Error("Invalid client identifier.");
    const identity = await ctx.auth.getUserIdentity();
    // Delete the first page of each set inline so a caller that refetches
    // immediately after the { ok } response sees them gone; larger histories
    // continue draining in scheduled batches. Small histories are fully
    // consistent before this mutation returns.
    if (identity) {
      const ownerId = identity.tokenIdentifier;
      const owned = await ctx.db.query("transcriptions").withIndex("by_owner_created", (q) => q.eq("ownerId", ownerId)).take(clearAllBatchSize);
      let ownedChars = 0;
      for (const item of owned) {
        await ctx.db.delete(item._id);
        ownedChars += historyItemChars(item);
      }
      await adjustOwnerStats(ctx, ownerId, -owned.length, -ownedChars);
      if (owned.length === clearAllBatchSize) await ctx.scheduler.runAfter(0, internal.cleanup.purgeHistoryPage, { ownerId });
    }
    // Always purge this browser's anonymous rows too, so pre-sign-in items go
    // with the rest.
    const anon = await ctx.db.query("transcriptions").withIndex("by_client_created", (q) => q.eq("clientId", clientId)).take(clearAllBatchSize);
    let anonDeleted = 0;
    for (const item of anon) {
      if (item.ownerId) continue;
      await ctx.db.delete(item._id);
      anonDeleted += 1;
    }
    if (anonDeleted === clearAllBatchSize) await ctx.scheduler.runAfter(0, internal.cleanup.purgeHistoryPage, { clientId });
  },
});

export const saveSummary = mutation({
  args: { id: v.id("transcriptions"), clientId: v.string(), summary: v.string(), serviceSecret: v.optional(v.string()) },
  handler: async (ctx, { id, clientId, summary, serviceSecret }) => {
    requireServiceSecret(serviceSecret);
    if (!clientIdPattern.test(clientId)) throw new Error("Invalid client identifier.");
    const normalizedSummary = summary.trim();
    // The PATCH body is bounded at 25,000 bytes upstream; a UTF-8 payload that
    // large seals to at most 4*ceil((25000+44)/3)+7 = 33,399 envelope
    // characters, so 34,000 admits every multi-byte summary the route accepts.
    if (!normalizedSummary || normalizedSummary.length > 34_000) throw new Error("Summary length is invalid.");
    const item = await ctx.db.get(id);
    if (!item) throw new Error("Transcription not found.");
    const identity = await ctx.auth.getUserIdentity();
    const ownsAccountItem = identity && item.ownerId === identity.tokenIdentifier;
    // Unlike remove (which is context-free), a summary write must be sealed to a
    // context the read path can reconstruct. A signed-in request seals to the
    // Clerk subject, but an anonymous row is only ever read back under its
    // clientId context, so a signed-in patch on one would store a summary that
    // can never decrypt. Require the anonymous branch to be genuinely anonymous.
    const ownsAnonymousItem = !identity && item.clientId === clientId && !item.ownerId;
    if (!ownsAccountItem && !ownsAnonymousItem) throw new Error("Not authorized to update this transcription.");
    await ctx.db.patch(id, { summary: normalizedSummary });
    if (item.ownerId) {
      await adjustOwnerStats(ctx, item.ownerId, 0, normalizedSummary.length - (item.summary?.length ?? 0));
    }
  },
});

// Migration support for rows written before encryption at rest. Gated by both
// the web service secret and the HISTORY_MIGRATION_ENABLED flag so the broad
// plaintext read cannot be invoked during normal operation. The migration
// script (web/scripts/encrypt-history.mjs) drives them with the history key,
// which Convex itself never holds; ownerId/clientId are returned so the script
// can seal each row to the same ownership context the read path reconstructs.
// A row is unmigrated when it has no textHash (text still plaintext) or carries
// a non-envelope summary.
export const plaintextPage = query({
  args: { cursor: v.union(v.string(), v.null()), serviceSecret: v.optional(v.string()) },
  handler: async (ctx, { cursor, serviceSecret }) => {
    requireServiceSecret(serviceSecret);
    requireMigrationEnabled();
    const page = await ctx.db.query("transcriptions").paginate({ cursor, numItems: 50 });
    return {
      isDone: page.isDone,
      continueCursor: page.continueCursor,
      items: page.page
        .filter((item) => item.textHash === undefined || (item.summary !== undefined && !item.summary.startsWith(envelopePrefix)))
        .map((item) => ({ id: item._id, text: item.text, summary: item.summary, ownerId: item.ownerId, clientId: item.clientId, operationId: item.operationId })),
    };
  },
});

export const applyCipher = mutation({
  args: {
    id: v.id("transcriptions"),
    text: v.optional(v.string()), textHash: v.optional(v.string()), expectedTextLength: v.optional(v.number()),
    operationId: v.optional(v.string()),
    summary: v.optional(v.string()), expectedSummaryLength: v.optional(v.number()),
    serviceSecret: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    requireServiceSecret(args.serviceSecret);
    requireMigrationEnabled();
    const item = await ctx.db.get(args.id);
    if (!item) return;
    const patch: { text?: string; textHash?: string; summary?: string; operationId?: string } = {};
    if (args.text !== undefined) {
      if (!args.text.startsWith(envelopePrefix) || args.text.length > maximumStoredTextLength) throw new Error("Invalid ciphertext.");
      if (args.textHash === undefined || !textHashPattern.test(args.textHash)) throw new Error("Invalid transcript digest.");
      // Patch only if the row is still the plaintext the script read.
      if (item.textHash === undefined && item.text.length === args.expectedTextLength) {
        patch.text = args.text;
        patch.textHash = args.textHash;
        // Legacy rows predating operation ids get one backfilled so the digest
        // stays bound to an operationId and the row is never reselected.
        if (item.operationId === undefined && args.operationId !== undefined) {
          if (!operationIdPattern.test(args.operationId)) throw new Error("Invalid operation identifier.");
          patch.operationId = args.operationId;
        }
      }
    }
    if (args.summary !== undefined) {
      if (!args.summary.startsWith(envelopePrefix)) throw new Error("Invalid summary ciphertext.");
      if (item.summary !== undefined && !item.summary.startsWith(envelopePrefix) && item.summary.length === args.expectedSummaryLength) {
        patch.summary = args.summary;
      }
    }
    if (Object.keys(patch).length) {
      await ctx.db.patch(args.id, patch);
      // Keep the per-owner storage aggregate consistent if a migration ever
      // runs after an owner's stats row exists (ciphertext is longer than the
      // plaintext it replaces).
      if (item.ownerId) {
        const textDelta = patch.text !== undefined ? patch.text.length - item.text.length : 0;
        const summaryDelta = patch.summary !== undefined ? patch.summary.length - (item.summary?.length ?? 0) : 0;
        await adjustOwnerStats(ctx, item.ownerId, 0, textDelta + summaryDelta);
      }
    }
  },
});
