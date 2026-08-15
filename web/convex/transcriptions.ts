import { paginationOptsValidator } from "convex/server";
import { v } from "convex/values";
import { mutation, query } from "./_generated/server";

const dayMs = 24 * 60 * 60 * 1000;
const defaultRetentionDays = 90;
const clientIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const operationIdPattern = clientIdPattern;

function requireServiceSecret(value?: string) {
  if (!process.env.CONVEX_WEB_API_SECRET || value !== process.env.CONVEX_WEB_API_SECRET) throw new Error("This operation must use the protected web service.");
}

function publicHistoryItem(item: {
  _id: unknown; model: string; text: string; summary?: string; durationSeconds: number;
  segments?: Array<{ start: number; end: number; text: string }>; operationId?: string;
  status: "processing" | "complete" | "failed"; createdAt: number;
}) {
  return {
    _id: item._id,
    model: item.model,
    text: item.text,
    ...(item.summary ? { summary: item.summary } : {}),
    durationSeconds: item.durationSeconds,
    ...(item.segments?.length ? { segments: item.segments } : {}),
    ...(item.operationId ? { operationId: item.operationId } : {}),
    status: item.status,
    createdAt: item.createdAt,
  };
}

export const list = query({
  args: { clientId: v.string(), paginationOpts: paginationOptsValidator, serviceSecret: v.optional(v.string()) },
  handler: async (ctx, { clientId, paginationOpts, serviceSecret }) => {
    requireServiceSecret(serviceSecret);
    if (!clientIdPattern.test(clientId)) throw new Error("Invalid client identifier.");
    const identity = await ctx.auth.getUserIdentity();
    if (identity) {
      const result = await ctx.db
        .query("transcriptions")
        .withIndex("by_owner_created", (q) => q.eq("ownerId", identity.tokenIdentifier))
        .order("desc")
        .paginate({ ...paginationOpts, numItems: Math.min(paginationOpts.numItems, 25) });
      const now = Date.now();
      return { ...result, page: result.page.filter((item) => item.expiresAt === undefined || item.expiresAt > now).map(publicHistoryItem) };
    }

    const now = Date.now();
    const items = await ctx.db
      .query("transcriptions")
      .withIndex("by_client_created", (q) => q.eq("clientId", clientId))
      .order("desc")
      .take(30);
    return {
      page: items.filter((item) => (item.expiresAt ?? item.createdAt + 60 * 60 * 1000) > now).map(publicHistoryItem),
      isDone: true,
      continueCursor: "",
    };
  },
});

export const save = mutation({
  args: {
    clientId: v.string(), model: v.string(), text: v.string(), durationSeconds: v.number(), operationId: v.string(),
    segments: v.optional(v.array(v.object({ start: v.number(), end: v.number(), text: v.string() }))),
    serviceSecret: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    requireServiceSecret(args.serviceSecret);
    const text = args.text.trim();
    if (!clientIdPattern.test(args.clientId)) throw new Error("Invalid client identifier.");
    if (!operationIdPattern.test(args.operationId)) throw new Error("Invalid operation identifier.");
    if (!text || text.length > 200_000) throw new Error("Transcript length is invalid.");
    if (args.model !== "whisper-large-v3-turbo") throw new Error("Unsupported transcription model.");
    if (!Number.isFinite(args.durationSeconds) || args.durationSeconds < 0 || args.durationSeconds > 21_600) throw new Error("Invalid recording duration.");
    if (args.segments && (args.segments.length > 5_000 || args.segments.some((segment, index) =>
      !segment.text.trim() || segment.text.length > 2_000 || !Number.isFinite(segment.start) || !Number.isFinite(segment.end)
      || segment.start < 0 || segment.end <= segment.start || segment.end > 21_600
      || (index > 0 && segment.start < args.segments![index - 1].start)))) throw new Error("Invalid transcription timing.");
    const createdAt = Date.now();
    const { clientId } = args;
    const existingOperation = identity
      ? await ctx.db.query("transcriptions")
        .withIndex("by_owner_operation", (q) => q.eq("ownerId", identity.tokenIdentifier).eq("operationId", args.operationId)).unique()
      : await ctx.db.query("transcriptions")
        .withIndex("by_client_operation", (q) => q.eq("clientId", clientId).eq("operationId", args.operationId)).unique();
    if (existingOperation) {
      if (existingOperation.text !== text || existingOperation.model !== args.model || existingOperation.durationSeconds !== args.durationSeconds) {
        throw new Error("Operation identifier was already used for different content.");
      }
      return existingOperation._id;
    }
    const transcription = { model: args.model, text: args.text, durationSeconds: args.durationSeconds, operationId: args.operationId, ...(args.segments?.length ? { segments: args.segments } : {}) };
    let accountRetentionDays = defaultRetentionDays;
    if (identity) {
      const history = await ctx.db.query("transcriptions").withIndex("by_owner_created", (q) => q.eq("ownerId", identity.tokenIdentifier)).order("desc").take(51);
      if (history.length >= 50) throw new Error("Account history limit reached. Delete older items or shorten retention.");
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
