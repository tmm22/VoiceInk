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
    serviceSecret: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity && (!process.env.CONVEX_WEB_API_SECRET || args.serviceSecret !== process.env.CONVEX_WEB_API_SECRET)) {
      throw new Error("Anonymous history writes must use the web service.");
    }
    const text = args.text.trim();
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(args.clientId)) throw new Error("Invalid client identifier.");
    if (!text || text.length > 200_000) throw new Error("Transcript length is invalid.");
    if (args.model !== "whisper-large-v3-turbo") throw new Error("Unsupported transcription model.");
    if (!Number.isFinite(args.durationSeconds) || args.durationSeconds < 0 || args.durationSeconds > 21_600) throw new Error("Invalid recording duration.");
    const createdAt = Date.now();
    const { clientId } = args;
    const transcription = { model: args.model, text: args.text, durationSeconds: args.durationSeconds };
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
      text,
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

export const saveSummary = mutation({
  args: { id: v.id("transcriptions"), clientId: v.string(), summary: v.string() },
  handler: async (ctx, { id, clientId, summary }) => {
    const item = await ctx.db.get(id);
    if (!item) throw new Error("Transcription not found.");
    const identity = await ctx.auth.getUserIdentity();
    const ownsAccountItem = identity && item.ownerId === identity.tokenIdentifier;
    const ownsAnonymousItem = !identity && item.clientId === clientId && !item.ownerId;
    if (!ownsAccountItem && !ownsAnonymousItem) throw new Error("Not authorized to update this transcription.");
    await ctx.db.patch(id, { summary: summary.trim().slice(0, 20_000) });
  },
});
