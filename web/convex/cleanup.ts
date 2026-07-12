import { internalMutation } from "./_generated/server";

const anonymousRetentionMs = 60 * 60 * 1000;

export const deleteExpiredAnonymousTranscriptions = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();
    const anonymous = await ctx.db
      .query("transcriptions")
      .filter((q) => q.eq(q.field("ownerId"), undefined))
      .order("asc")
      .take(100);

    let deleted = 0;
    for (const item of anonymous) {
      const expiresAt = item.expiresAt ?? item.createdAt + anonymousRetentionMs;
      if (expiresAt > now) break;
      await ctx.db.delete(item._id);
      deleted += 1;
    }
    return { deleted };
  },
});
