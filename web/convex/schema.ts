import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  transcriptions: defineTable({
    clientId: v.optional(v.string()),
    ownerId: v.optional(v.string()),
    model: v.string(),
    text: v.string(),
    durationSeconds: v.number(),
    status: v.union(v.literal("processing"), v.literal("complete"), v.literal("failed")),
    createdAt: v.number(),
    expiresAt: v.optional(v.number()),
  })
    .index("by_client_created", ["clientId", "createdAt"])
    .index("by_owner_created", ["ownerId", "createdAt"]),
});
