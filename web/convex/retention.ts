import { mutationGeneric as mutation, queryGeneric as query } from "convex/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import { requireServiceSecret } from "./serviceAuth";

const retentionDays = v.union(v.literal(0), v.literal(7), v.literal(30), v.literal(90), v.literal(365));
const defaultRetentionDays = 90 as const;
type RetentionDays = 0 | 7 | 30 | 90 | 365;

function requiresMigrationHold(previousDays: RetentionDays, nextDays: RetentionDays, migrationInProgress: boolean) {
  if (migrationInProgress) return true;
  if (nextDays === 0) return true;
  return previousDays !== 0 && nextDays > previousDays;
}

export const get = query({
  args: { serviceSecret: v.optional(v.string()) },
  handler: async (ctx, { serviceSecret }) => {
    requireServiceSecret(serviceSecret);
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
  args: { days: retentionDays, serviceSecret: v.optional(v.string()) },
  handler: async (ctx, { days, serviceSecret }) => {
    requireServiceSecret(serviceSecret);
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new Error("Sign in to change history retention.");
    const ownerId = identity.tokenIdentifier;
    const existing = await ctx.db
      .query("retentionSettings")
      .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
      .unique();
    const revision = Math.max(Date.now(), (existing?.updatedAt ?? 0) + 1);
    const holdCleanup = requiresMigrationHold(
      existing?.days ?? defaultRetentionDays,
      days,
      existing?.migrationRevision !== undefined,
    );
    const nextSetting = {
      days,
      updatedAt: revision,
      migrationRevision: holdCleanup ? revision : undefined,
    };
    if (existing) await ctx.db.patch(existing._id, nextSetting);
    else await ctx.db.insert("retentionSettings", { ownerId, ...nextSetting });

    await ctx.scheduler.runAfter(0, internal.cleanup.applyRetentionPage, { ownerId, days, cursor: null, revision });
    return { days };
  },
});
