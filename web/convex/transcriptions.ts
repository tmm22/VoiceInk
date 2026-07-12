import { mutationGeneric as mutation, queryGeneric as query } from "convex/server";
import { v } from "convex/values";

const dayMs = 24 * 60 * 60 * 1000;
const defaultRetentionDays = 90;

export const list = query({
  args: { clientId: v.string() },
  handler: async (ctx, { clientId }) => {
    const identity = await ctx.auth.getUserIdentity();
    if (identity) {
      const items = await ctx.db
        .query("transcriptions")
        .withIndex("by_owner_created", (q) => q.eq("ownerId", identity.tokenIdentifier))
        .order("desc")
        .take(100);
      const now = Date.now();
      return items.filter((item) => item.expiresAt === undefined || item.expiresAt > now);
    }

    const now = Date.now();
    const items = await ctx.db
      .query("transcriptions")
      .withIndex("by_client_created", (q) => q.eq("clientId", clientId))
      .order("desc")
      .take(30);
    return items.filter((item) => (item.expiresAt ?? item.createdAt + 60 * 60 * 1000) > now);
  },
});

export const save = mutation({
  args: {
    clientId: v.string(), model: v.string(), text: v.string(), durationSeconds: v.number(),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    const createdAt = Date.now();
    const { clientId, ...transcription } = args;
    let accountRetentionDays = defaultRetentionDays;
    if (identity) {
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
    }
    return ctx.db.insert("transcriptions", {
      ...transcription,
      ...(identity
        ? {
            ownerId: identity.tokenIdentifier,
            ...(accountRetentionDays === 0 ? {} : { expiresAt: createdAt + accountRetentionDays * dayMs }),
          }
        : { clientId, expiresAt: createdAt + 60 * 60 * 1000 }),
      status: "complete",
      createdAt,
    });
  },
});

export const remove = mutation({
  args: { id: v.id("transcriptions"), clientId: v.string() },
  handler: async (ctx, { id, clientId }) => {
    const item = await ctx.db.get(id);
    if (!item) return;
    const identity = await ctx.auth.getUserIdentity();
    const ownsAccountItem = identity && item.ownerId === identity.tokenIdentifier;
    const ownsAnonymousItem = !identity && item.clientId === clientId && !item.ownerId;
    if (!ownsAccountItem && !ownsAnonymousItem) throw new Error("Not authorized to delete this transcription.");
    await ctx.db.delete(id);
  },
});
