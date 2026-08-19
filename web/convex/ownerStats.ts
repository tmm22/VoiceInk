import type { Doc } from "./_generated/dataModel";
import type { MutationCtx } from "./_generated/server";

// Shared maintenance for the per-owner `ownerStats` aggregate. Every mutation
// that inserts, deletes, or resizes an owned transcription keeps the aggregate
// in sync inside the same Convex transaction, so quota enforcement in
// transcriptions.save reads one tiny row instead of paging full ciphertext
// documents. These are plain helpers, not registered Convex functions.

export const ownerItemLimit = 50;
export const ownerStoredCharsLimit = 10_000_000;

// The 50-item cap has always bounded owned histories, so this comfortably
// covers any real account while keeping the one-time initialization read
// bounded. If an account somehow exceeds it, the truncated count still
// enforces the caps fail-closed (a partial count at this size is already
// far past every limit gate that consults it).
const initializationScanLimit = 200;

// Envelope characters a row contributes to the storage quota — text plus
// summary, matching the pre-aggregate math in transcriptions.save.
export function historyItemChars(item: { text: string; summary?: string }): number {
  return item.text.length + (item.summary?.length ?? 0);
}

async function findOwnerStats(ctx: MutationCtx, ownerId: string): Promise<Doc<"ownerStats"> | null> {
  return ctx.db
    .query("ownerStats")
    .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
    .unique();
}

// Read the aggregate, lazily initializing it from one bounded read of the
// owner's existing rows the first time an owner saves after this feature
// ships. Expired-but-not-yet-swept rows are counted, exactly as the previous
// take(51) quota read counted them; the sweep decrements when it deletes.
export async function ensureOwnerStats(ctx: MutationCtx, ownerId: string): Promise<Doc<"ownerStats">> {
  const existing = await findOwnerStats(ctx, ownerId);
  if (existing) return existing;
  const rows = await ctx.db
    .query("transcriptions")
    .withIndex("by_owner_created", (q) => q.eq("ownerId", ownerId))
    .take(initializationScanLimit);
  const id = await ctx.db.insert("ownerStats", {
    ownerId,
    itemCount: rows.length,
    storedChars: rows.reduce((total, item) => total + historyItemChars(item), 0),
  });
  return (await ctx.db.get(id))!;
}

// Apply a delta to an owner's aggregate. An absent row is a deliberate no-op:
// it means no save has initialized this owner yet, and the next save's lazy
// initialization reads ground truth, so skipping here can never cause drift.
// Values clamp at zero so a decrement can never make quota math negative.
export async function adjustOwnerStats(ctx: MutationCtx, ownerId: string, deltaItems: number, deltaChars: number): Promise<void> {
  if (deltaItems === 0 && deltaChars === 0) return;
  const stats = await findOwnerStats(ctx, ownerId);
  if (!stats) return;
  await ctx.db.patch(stats._id, {
    itemCount: Math.max(0, stats.itemCount + deltaItems),
    storedChars: Math.max(0, stats.storedChars + deltaChars),
  });
}

// Drop the aggregate row entirely (account deletion), alongside the retention
// setting, so nothing keyed to the identity outlives the account.
export async function removeOwnerStats(ctx: MutationCtx, ownerId: string): Promise<void> {
  const stats = await findOwnerStats(ctx, ownerId);
  if (stats) await ctx.db.delete(stats._id);
}
