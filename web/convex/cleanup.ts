import { internalMutation } from "./_generated/server";

const anonymousRetentionMs = 60 * 60 * 1000;

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
