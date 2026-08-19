import { internalMutation, internalQuery } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";
import { adjustOwnerStats, historyItemChars, removeOwnerStats } from "./ownerStats";

const anonymousRetentionMs = 60 * 60 * 1000;
const dayMs = 24 * 60 * 60 * 1000;
const cleanupBatchSize = 100;
const cleanupScanPages = 10;
const staleMigrationMs = 60 * 60 * 1000;

export const applyRetentionPage = internalMutation({
  args: {
    ownerId: v.string(),
    days: v.union(v.literal(0), v.literal(7), v.literal(30), v.literal(90), v.literal(365)),
    cursor: v.union(v.string(), v.null()),
    revision: v.number(),
  },
  handler: async (ctx, { ownerId, days, cursor, revision }) => {
    const setting = await ctx.db.query("retentionSettings").withIndex("by_owner", (q) => q.eq("ownerId", ownerId)).unique();
    if (!setting || setting.updatedAt !== revision || setting.days !== days) return;
    const page = await ctx.db
      .query("transcriptions")
      .withIndex("by_owner_created", (q) => q.eq("ownerId", ownerId))
      .paginate({ cursor, numItems: 50 });
    for (const item of page.page) {
      await ctx.db.patch(item._id, { expiresAt: days === 0 ? undefined : item.createdAt + days * dayMs });
    }
    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.cleanup.applyRetentionPage, {
        ownerId,
        days,
        cursor: page.continueCursor,
        revision,
      });
    } else if (setting.migrationRevision === revision) {
      // Deletion may resume only after every record has the current policy.
      await ctx.db.patch(setting._id, { migrationRevision: undefined });
    }
  },
});

// Bounded, self-rescheduling purge of a user's complete history. Drives both
// the user-facing "delete all history" action and Clerk account-deletion
// cleanup; `removeSettings` also drops the retention row once the history is gone.
export const purgeHistoryPage = internalMutation({
  args: { ownerId: v.optional(v.string()), clientId: v.optional(v.string()), removeSettings: v.optional(v.boolean()) },
  handler: async (ctx, args) => {
    let deleted = 0;
    if (args.ownerId !== undefined) {
      const ownerId = args.ownerId;
      const page = await ctx.db.query("transcriptions")
        .withIndex("by_owner_created", (q) => q.eq("ownerId", ownerId))
        .take(cleanupBatchSize);
      let deletedChars = 0;
      for (const item of page) {
        await ctx.db.delete(item._id);
        deletedChars += historyItemChars(item);
        deleted += 1;
      }
      await adjustOwnerStats(ctx, ownerId, -deleted, -deletedChars);
    } else if (args.clientId !== undefined) {
      const clientId = args.clientId;
      const page = await ctx.db.query("transcriptions")
        .withIndex("by_client_created", (q) => q.eq("clientId", clientId))
        .take(cleanupBatchSize);
      for (const item of page) {
        if (item.ownerId) continue;
        await ctx.db.delete(item._id);
        deleted += 1;
      }
    }
    if (deleted === cleanupBatchSize) {
      await ctx.scheduler.runAfter(0, internal.cleanup.purgeHistoryPage, args);
      return;
    }
    if (args.ownerId !== undefined && args.removeSettings) {
      const ownerId = args.ownerId;
      const setting = await ctx.db.query("retentionSettings")
        .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
        .unique();
      if (setting) await ctx.db.delete(setting._id);
      // Account deletion: the per-owner aggregate goes with the history so no
      // row keyed to the identity outlives the account.
      await removeOwnerStats(ctx, ownerId);
    }
  },
});

export const deleteExpiredTranscriptions = internalMutation({
  args: { cursor: v.optional(v.union(v.string(), v.null())), pagesRemaining: v.optional(v.number()) },
  handler: async (ctx, { cursor, pagesRemaining }) => {
    const now = Date.now();
    const expiredPage = await ctx.db
      .query("transcriptions")
      .withIndex("by_expires_at", (q) => q.gt("expiresAt", 0).lte("expiresAt", now))
      .paginate({ cursor: cursor ?? null, numItems: cleanupBatchSize });
    const retentionSettings = new Map<string, { days: 0 | 7 | 30 | 90 | 365; updatedAt: number; migrationRevision?: number } | null>();
    const restartedMigrations = new Set<string>();
    const ownerDeltas = new Map<string, { items: number; chars: number }>();
    let expiredDeleted = 0;
    for (const item of expiredPage.page) {
      if (item.ownerId) {
        const ownerId = item.ownerId;
        let setting = retentionSettings.get(ownerId);
        if (setting === undefined) {
          setting = await ctx.db
            .query("retentionSettings")
            .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
            .unique();
          retentionSettings.set(ownerId, setting);
        }
        if (setting?.migrationRevision !== undefined) {
          if (now - setting.updatedAt > staleMigrationMs && !restartedMigrations.has(ownerId)) {
            restartedMigrations.add(ownerId);
            await ctx.scheduler.runAfter(0, internal.cleanup.applyRetentionPage, {
              ownerId,
              days: setting.days,
              cursor: null,
              revision: setting.migrationRevision,
            });
          }
          continue;
        }
        const delta = ownerDeltas.get(ownerId) ?? { items: 0, chars: 0 };
        delta.items += 1;
        delta.chars += historyItemChars(item);
        ownerDeltas.set(ownerId, delta);
      }
      await ctx.db.delete(item._id);
      expiredDeleted += 1;
    }
    for (const [ownerId, delta] of ownerDeltas) {
      await adjustOwnerStats(ctx, ownerId, -delta.items, -delta.chars);
    }

    // Continue only after actually draining a complete deletable batch. Merely
    // reading 100 held or fresh records must not create a zero-delay spin loop.
    const scansLeft = Math.min(Math.max(pagesRemaining ?? cleanupScanPages, 1), cleanupScanPages);
    if (!expiredPage.isDone && scansLeft > 1) {
      await ctx.scheduler.runAfter(0, internal.cleanup.deleteExpiredTranscriptions, {
        cursor: expiredPage.continueCursor,
        pagesRemaining: scansLeft - 1,
      });
    } else if (expiredDeleted === cleanupBatchSize) {
      await ctx.scheduler.runAfter(0, internal.cleanup.deleteExpiredTranscriptions, {});
    }
    return { deleted: expiredDeleted };
  },
});

// Legacy pre-`expiresAt` anonymous rows (no ownerId AND no expiresAt) used to
// be swept by an unindexed full-table `.filter` on every cron tick. That scan
// is gone: the two functions below let an operator check for and drain any
// remaining legacy rows once (before or right after deploy); after the
// backfill stamps `expiresAt`, the indexed `by_expires_at` sweep above owns
// them like every other anonymous row. Both walk the `by_expires_at` index at
// `expiresAt === undefined` — a bounded range, not a table scan — and skip the
// owned keep-until-deleted rows that legitimately live there.

export const countLegacyAnonymous = internalQuery({
  args: { limit: v.optional(v.number()) },
  handler: async (ctx, { limit }) => {
    const bounded = Math.min(Math.max(Math.trunc(limit ?? cleanupBatchSize), 1), 1_000);
    const rows = await ctx.db
      .query("transcriptions")
      .withIndex("by_expires_at", (q) => q.eq("expiresAt", undefined))
      .take(bounded);
    return {
      legacyAnonymous: rows.filter((item) => item.ownerId === undefined).length,
      scanned: rows.length,
      // More unexpired-`expiresAt` rows exist past the bound; re-run with a
      // larger limit (or just backfill) for the full picture.
      truncated: rows.length === bounded,
    };
  },
});

export const backfillLegacyAnonymous = internalMutation({
  args: { cursor: v.optional(v.union(v.string(), v.null())) },
  handler: async (ctx, { cursor }) => {
    const page = await ctx.db
      .query("transcriptions")
      .withIndex("by_expires_at", (q) => q.eq("expiresAt", undefined))
      .paginate({ cursor: cursor ?? null, numItems: cleanupBatchSize });
    let stamped = 0;
    for (const item of page.page) {
      if (item.ownerId !== undefined) continue;
      // The anonymous retention policy these rows predate: one hour from
      // creation. Rows already past it become immediately eligible for the
      // indexed expiry sweep.
      await ctx.db.patch(item._id, { expiresAt: item.createdAt + anonymousRetentionMs });
      stamped += 1;
    }
    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.cleanup.backfillLegacyAnonymous, { cursor: page.continueCursor });
    }
    return { stamped, isDone: page.isDone };
  },
});
