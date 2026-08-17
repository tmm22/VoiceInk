import { internalMutation } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";

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
      for (const item of page) {
        await ctx.db.delete(item._id);
        deleted += 1;
      }
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
      }
      await ctx.db.delete(item._id);
      expiredDeleted += 1;
    }

    const legacyAnonymous = await ctx.db
      .query("transcriptions")
      .filter((q) => q.and(
        q.eq(q.field("ownerId"), undefined),
        q.eq(q.field("expiresAt"), undefined),
      ))
      .order("asc")
      .take(cleanupBatchSize);
    let legacyDeleted = 0;
    for (const item of legacyAnonymous) {
      if (item.createdAt + anonymousRetentionMs > now) break;
      await ctx.db.delete(item._id);
      legacyDeleted += 1;
    }
    // Continue only after actually draining a complete deletable batch. Merely
    // reading 100 held or fresh records must not create a zero-delay spin loop.
    const scansLeft = Math.min(Math.max(pagesRemaining ?? cleanupScanPages, 1), cleanupScanPages);
    if (!expiredPage.isDone && scansLeft > 1) {
      await ctx.scheduler.runAfter(0, internal.cleanup.deleteExpiredTranscriptions, {
        cursor: expiredPage.continueCursor,
        pagesRemaining: scansLeft - 1,
      });
    } else if (expiredDeleted === cleanupBatchSize || legacyDeleted === cleanupBatchSize) {
      await ctx.scheduler.runAfter(0, internal.cleanup.deleteExpiredTranscriptions, {});
    }
    return { deleted: expiredDeleted + legacyDeleted };
  },
});
