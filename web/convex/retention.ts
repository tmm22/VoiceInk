import { mutationGeneric as mutation, queryGeneric as query } from "convex/server";
import { v } from "convex/values";

const retentionDays = v.union(v.literal(0), v.literal(7), v.literal(30), v.literal(90), v.literal(365));
const defaultRetentionDays = 90 as const;
const dayMs = 24 * 60 * 60 * 1000;

export const get = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return null;
    const setting = await ctx.db
      .query("retentionSettings")
      .withIndex("by_owner", (q) => q.eq("ownerId", identity.tokenIdentifier))
      .unique();
    return { days: setting?.days ?? defaultRetentionDays };
  },
});

export const set = mutation({
  args: { days: retentionDays },
  handler: async (ctx, { days }) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new Error("Sign in to change history retention.");
    const ownerId = identity.tokenIdentifier;
    const existing = await ctx.db
      .query("retentionSettings")
      .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
      .unique();
    if (existing) await ctx.db.patch(existing._id, { days, updatedAt: Date.now() });
    else await ctx.db.insert("retentionSettings", { ownerId, days, updatedAt: Date.now() });

    const history = await ctx.db
      .query("transcriptions")
      .withIndex("by_owner_created", (q) => q.eq("ownerId", ownerId))
      .take(100);
    for (const item of history) {
      await ctx.db.patch(item._id, {
        expiresAt: days === 0 ? undefined : item.createdAt + days * dayMs,
      });
    }
    return { days, updated: history.length };
  },
});
