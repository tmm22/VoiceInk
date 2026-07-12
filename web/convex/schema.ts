import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  transcriptions: defineTable({
    clientId: v.string(),
    model: v.string(),
    text: v.string(),
    durationSeconds: v.number(),
    status: v.union(v.literal("processing"), v.literal("complete"), v.literal("failed")),
    createdAt: v.number(),
  }).index("by_client_created", ["clientId", "createdAt"]),
});
