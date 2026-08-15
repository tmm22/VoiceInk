import { mutationGeneric as mutation, queryGeneric as query } from "convex/server";
import { v } from "convex/values";

const dayMs = 24 * 60 * 60 * 1000;
const defaultRetentionDays = 90;
const clientIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function requireServiceSecret(value?: string) {
  if (!process.env.CONVEX_WEB_API_SECRET || value !== process.env.CONVEX_WEB_API_SECRET) throw new Error("This operation must use the protected web service.");
}

export const list = query({
  args: { clientId: v.string(), serviceSecret: v.optional(v.string()) },
  handler: async (ctx, { clientId, serviceSecret }) => {
    requireServiceSecret(serviceSecret);
    if (!clientIdPattern.test(clientId)) throw new Error("Invalid client identifier.");
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
    requireServiceSecret(args.serviceSecret);
    const text = args.text.trim();
    if (!clientIdPattern.test(args.clientId)) throw new Error("Invalid client identifier.");
    if (!text || text.length > 200_000) throw new Error("Transcript length is invalid.");
    if (args.model !== "whisper-large-v3-turbo") throw new Error("Unsupported transcription model.");
    if (!Number.isFinite(args.durationSeconds) || args.durationSeconds < 0 || args.durationSeconds > 21_600) throw new Error("Invalid recording duration.");
    const createdAt = Date.now();
    const { clientId } = args;
    const transcription = { model: args.model, text: args.text, durationSeconds: args.durationSeconds };
    let accountRetentionDays = defaultRetentionDays;
    if (identity) {
      const history = await ctx.db.query("transcriptions").withIndex("by_owner_created", (q) => q.eq("ownerId", identity.tokenIdentifier)).order("desc").take(1001);
      if (history.length >= 1000) throw new Error("Account history limit reached. Delete older items or shorten retention.");
      if (history.filter((item) => item.createdAt > createdAt - 60_000).length >= 10) throw new Error("Transcription write limit reached. Please wait.");
      if (history.filter((item) => item.createdAt > createdAt - dayMs).length >= 100) throw new Error("Daily transcription limit reached.");
      if (history.reduce((total, item) => total + item.text.length + (item.summary?.length ?? 0), 0) + text.length > 10_000_000) throw new Error("Account storage limit reached.");
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
    } else {
      const recent = await ctx.db.query("transcriptions").withIndex("by_client_created", (q) => q.eq("clientId", clientId)).order("desc").take(31);
      if (recent.filter((item) => (item.expiresAt ?? 0) > createdAt).length >= 30) throw new Error("Anonymous history limit reached. Sign in or wait for older items to expire.");
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
  args: { id: v.id("transcriptions"), clientId: v.string(), serviceSecret: v.optional(v.string()) },
  handler: async (ctx, { id, clientId, serviceSecret }) => {
    requireServiceSecret(serviceSecret);
    if (!clientIdPattern.test(clientId)) throw new Error("Invalid client identifier.");
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
  args: { id: v.id("transcriptions"), clientId: v.string(), summary: v.string(), serviceSecret: v.optional(v.string()) },
  handler: async (ctx, { id, clientId, summary, serviceSecret }) => {
    requireServiceSecret(serviceSecret);
    if (!clientIdPattern.test(clientId)) throw new Error("Invalid client identifier.");
    const normalizedSummary = summary.trim();
    if (!normalizedSummary || normalizedSummary.length > 20_000) throw new Error("Summary length is invalid.");
    const item = await ctx.db.get(id);
    if (!item) throw new Error("Transcription not found.");
    const identity = await ctx.auth.getUserIdentity();
    const ownsAccountItem = identity && item.ownerId === identity.tokenIdentifier;
    const ownsAnonymousItem = !identity && item.clientId === clientId && !item.ownerId;
    if (!ownsAccountItem && !ownsAnonymousItem) throw new Error("Not authorized to update this transcription.");
    await ctx.db.patch(id, { summary: normalizedSummary });
  },
});
