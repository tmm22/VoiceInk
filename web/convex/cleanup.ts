import { internalMutation } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";

const anonymousRetentionMs = 60 * 60 * 1000;
const dayMs = 24 * 60 * 60 * 1000;

export const applyRetentionPage = internalMutation({
  args: {
    ownerId: v.string(),
    days: v.union(v.literal(0), v.literal(7), v.literal(30), v.literal(90), v.literal(365)),
    cursor: v.union(v.string(), v.null()),
  },
  handler: async (ctx, { ownerId, days, cursor }) => {
    const page = await ctx.db
      .query("transcriptions")
      .withIndex("by_owner_created", (q) => q.eq("ownerId", ownerId))
      .paginate({ cursor, numItems: 50 });
    for (const item of page.page) {
      await ctx.db.patch(item._id, { expiresAt: days === 0 ? undefined : item.createdAt + days * dayMs });
    }
    if (!page.isDone) await ctx.scheduler.runAfter(0, internal.cleanup.applyRetentionPage, {
      ownerId,
      days,
      cursor: page.continueCursor,
    });
  },
});

export const deleteExpiredTranscriptions = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();
    const expired = await ctx.db
      .query("transcriptions")
      .withIndex("by_expires_at", (q) => q.gt("expiresAt", 0).lte("expiresAt", now))
      .take(100);
    for (const item of expired) await ctx.db.delete(item._id);

    const legacyAnonymous = await ctx.db
      .query("transcriptions")
      .filter((q) => q.and(
        q.eq(q.field("ownerId"), undefined),
        q.eq(q.field("expiresAt"), undefined),
      ))
      .order("asc")
      .take(100);
    let legacyDeleted = 0;
    for (const item of legacyAnonymous) {
      if (item.createdAt + anonymousRetentionMs > now) break;
      await ctx.db.delete(item._id);
      legacyDeleted += 1;
    }
    return { deleted: expired.length + legacyDeleted };
  },
});
