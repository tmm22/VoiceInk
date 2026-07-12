import { mutationGeneric as mutation, queryGeneric as query } from "convex/server";
import { v } from "convex/values";

export const list = query({
  args: { clientId: v.string() },
  handler: async (ctx, { clientId }) => ctx.db
    .query("transcriptions")
    .withIndex("by_client_created", (q) => q.eq("clientId", clientId))
    .order("desc")
    .take(30),
});

export const save = mutation({
  args: {
    clientId: v.string(), model: v.string(), text: v.string(), durationSeconds: v.number(),
  },
  handler: async (ctx, args) => ctx.db.insert("transcriptions", {
    ...args, status: "complete", createdAt: Date.now(),
  }),
});
