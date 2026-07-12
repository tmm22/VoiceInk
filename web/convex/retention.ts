import { mutationGeneric as mutation, queryGeneric as query } from "convex/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";

const retentionDays = v.union(v.literal(0), v.literal(7), v.literal(30), v.literal(90), v.literal(365));
const defaultRetentionDays = 90 as const;

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

    await ctx.scheduler.runAfter(0, internal.cleanup.applyRetentionPage, { ownerId, days, cursor: null });
    return { days };
  },
});
