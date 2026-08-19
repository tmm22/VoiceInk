import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  transcriptions: defineTable({
    clientId: v.optional(v.string()),
    ownerId: v.optional(v.string()),
    model: v.string(),
    detectedLanguage: v.optional(v.string()),
    text: v.string(),
    textHash: v.optional(v.string()),
    summary: v.optional(v.string()),
    durationSeconds: v.number(),
    operationId: v.optional(v.string()),
    segments: v.optional(v.array(v.object({ start: v.number(), end: v.number(), text: v.string() }))),
    status: v.union(v.literal("processing"), v.literal("complete"), v.literal("failed")),
    createdAt: v.number(),
    expiresAt: v.optional(v.number()),
  })
    .index("by_client_created", ["clientId", "createdAt"])
    .index("by_owner_created", ["ownerId", "createdAt"])
    .index("by_client_operation", ["clientId", "operationId"])
    .index("by_owner_operation", ["ownerId", "operationId"])
    .index("by_expires_at", ["expiresAt"]),
  retentionSettings: defineTable({
    ownerId: v.string(),
    days: v.union(v.literal(0), v.literal(7), v.literal(30), v.literal(90), v.literal(365)),
    updatedAt: v.number(),
    migrationRevision: v.optional(v.number()),
  }).index("by_owner", ["ownerId"]),
  // Per-owner aggregate maintained transactionally by every mutation that
  // inserts, deletes, or resizes an owned transcription (save, remove,
  // clearAll, saveSummary, and the cleanup deletions), so quota checks on save
  // read one tiny row instead of every ciphertext document. Lazily initialized
  // from a bounded read of the owner's existing rows; counts stored envelope
  // characters (text + summary), matching the pre-aggregate quota math.
  ownerStats: defineTable({
    ownerId: v.string(),
    itemCount: v.number(),
    storedChars: v.number(),
  }).index("by_owner", ["ownerId"]),
});
