// Per-identity cache of NON-SENSITIVE history shape metadata so the History
// workspace can paint correctly shaped skeleton placeholder rows at boot,
// before the first /api/history round trip completes. Real rows replace the
// skeleton as soon as the fetch lands.
//
// ENCRYPTION INVARIANT (AGENTS.md): transcript and summary TEXT must never be
// cached client-side. This module therefore whitelists shape metadata only —
// ids, timestamps, durations, model names, an item count, and a boolean
// summary flag — building each stored entry field by field so no other field
// can ever reach storage, and the decoder drops everything it does not know.

type StringStore = Pick<Storage, "getItem" | "setItem" | "removeItem">;

export type HistoryShapeItem = {
  id: string;
  createdAt: number;
  durationSeconds: number;
  model: string;
  hasSummary: boolean;
};

// Structural subset of TranscriptionHistoryItem; only these fields are read.
type HistoryShapeSource = {
  _id: string;
  createdAt: number;
  durationSeconds: number;
  model: string;
  summary?: string;
};

const shapeKeyPrefix = "voiceink-history-shape:";
// Points at the identity whose shape was written last, so a hinted boot can
// find the signed-in cache before clerk-js has resolved the session id.
const lastIdentityPointerKey = "voiceink-history-shape-last";
export const maximumShapeItems = 20;

function browserStore(): StringStore | null {
  try {
    return typeof window === "undefined" ? null : window.localStorage;
  } catch {
    return null;
  }
}

export function historyShapeKey(identityKey: string): string {
  return `${shapeKeyPrefix}${identityKey}`;
}

export function encodeHistoryShape(items: readonly HistoryShapeSource[]): string {
  const shaped: HistoryShapeItem[] = items.slice(0, maximumShapeItems).map((item) => ({
    id: item._id,
    createdAt: item.createdAt,
    durationSeconds: item.durationSeconds,
    model: item.model,
    hasSummary: typeof item.summary === "string" && item.summary.length > 0,
  }));
  return JSON.stringify({ count: items.length, items: shaped });
}

export function decodeHistoryShape(raw: string | null): HistoryShapeItem[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw) as { items?: unknown };
    if (!parsed || !Array.isArray(parsed.items)) return [];
    const items: HistoryShapeItem[] = [];
    for (const entry of parsed.items.slice(0, maximumShapeItems)) {
      if (!entry || typeof entry !== "object") return [];
      const candidate = entry as Record<string, unknown>;
      if (
        typeof candidate.id !== "string" ||
        typeof candidate.createdAt !== "number" || !Number.isFinite(candidate.createdAt) ||
        typeof candidate.durationSeconds !== "number" || !Number.isFinite(candidate.durationSeconds) ||
        typeof candidate.model !== "string" ||
        typeof candidate.hasSummary !== "boolean"
      ) return [];
      items.push({
        id: candidate.id,
        createdAt: candidate.createdAt,
        durationSeconds: candidate.durationSeconds,
        model: candidate.model,
        hasSummary: candidate.hasSummary,
      });
    }
    return items;
  } catch {
    return [];
  }
}

export function saveHistoryShape(
  identityKey: string,
  items: readonly HistoryShapeSource[],
  store: StringStore | null = browserStore(),
): void {
  if (!store) return;
  try {
    store.setItem(historyShapeKey(identityKey), encodeHistoryShape(items));
    store.setItem(lastIdentityPointerKey, identityKey);
  } catch {
    // Quota or privacy-mode failures only lose the skeleton warm start.
  }
}

export function clearHistoryShape(identityKey: string, store: StringStore | null = browserStore()): void {
  if (!store) return;
  try {
    store.removeItem(historyShapeKey(identityKey));
    if (store.getItem(lastIdentityPointerKey) === identityKey) store.removeItem(lastIdentityPointerKey);
  } catch {
    // Losing the cleanup is harmless; the cache holds shape metadata only.
  }
}

// Boot read. With a Clerk session hint the signed-in identityKey is unknown
// until clerk-js resolves, so follow the last-written pointer (skipping an
// anonymous pointer — an anonymous shape must not stand in for a signed-in
// account); without a hint the identity is the anonymous one.
export function loadBootHistoryShape(
  sessionHinted: boolean,
  store: StringStore | null = browserStore(),
): HistoryShapeItem[] {
  if (!store) return [];
  try {
    let identityKey: string | null = "anonymous";
    if (sessionHinted) {
      const pointer = store.getItem(lastIdentityPointerKey);
      identityKey = pointer && pointer !== "anonymous" ? pointer : null;
    }
    if (!identityKey) return [];
    return decodeHistoryShape(store.getItem(historyShapeKey(identityKey)));
  } catch {
    return [];
  }
}
