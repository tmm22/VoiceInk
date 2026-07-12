import { mutationGeneric as mutation, queryGeneric as query } from "convex/server";
import { v } from "convex/values";

export const list = query({
  args: { clientId: v.string() },
  handler: async (ctx, { clientId }) => {
    const identity = await ctx.auth.getUserIdentity();
    if (identity) {
      return ctx.db
        .query("transcriptions")
        .withIndex("by_owner_created", (q) => q.eq("ownerId", identity.tokenIdentifier))
        .order("desc")
        .take(100);
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
    return ctx.db.insert("transcriptions", {
      ...transcription,
      ...(identity
        ? { ownerId: identity.tokenIdentifier }
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
