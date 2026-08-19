import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  clearHistoryShape,
  decodeHistoryShape,
  encodeHistoryShape,
  historyShapeKey,
  loadBootHistoryShape,
  maximumShapeItems,
  saveHistoryShape,
} from "../lib/historyMetadataCache.ts";

const root = new URL("../", import.meta.url);
const source = (path) => readFile(new URL(path, root), "utf8");

function memoryStore(overrides = {}) {
  const map = new Map();
  return {
    map,
    getItem: (key) => (map.has(key) ? map.get(key) : null),
    setItem: (key, value) => {
      map.set(key, String(value));
    },
    removeItem: (key) => {
      map.delete(key);
    },
    ...overrides,
  };
}

const sampleItem = (overrides = {}) => ({
  _id: "rec_1",
  text: "SECRET TRANSCRIPT CONTENT",
  summary: "SECRET SUMMARY CONTENT",
  segments: [{ start: 0, end: 1, text: "SECRET SEGMENT" }],
  durationSeconds: 42,
  model: "nova-3",
  operationId: "op-1",
  status: "complete",
  createdAt: 1_700_000_000_000,
  ...overrides,
});

test("history shape cache persists metadata only — never transcript or summary text", () => {
  const store = memoryStore();
  saveHistoryShape("sess_abc", [sampleItem(), sampleItem({ _id: "rec_2", summary: undefined })], store);
  const raw = store.map.get(historyShapeKey("sess_abc"));
  assert.ok(raw, "shape must be stored under the identity-namespaced key");
  // The encryption invariant: no transcript, summary, or segment text at rest.
  assert.doesNotMatch(raw, /SECRET/);
  const parsed = JSON.parse(raw);
  assert.equal(parsed.count, 2);
  // Whitelisted fields only, nothing else survives encoding.
  assert.deepEqual(parsed.items[0], { id: "rec_1", createdAt: 1_700_000_000_000, durationSeconds: 42, model: "nova-3", hasSummary: true });
  assert.deepEqual(parsed.items[1], { id: "rec_2", createdAt: 1_700_000_000_000, durationSeconds: 42, model: "nova-3", hasSummary: false });
});

test("decoding validates entries, drops unknown fields, and caps the item count", () => {
  const items = decodeHistoryShape(JSON.stringify({
    count: 1,
    items: [{ id: "rec_1", createdAt: 1, durationSeconds: 2, model: "nova-3", hasSummary: false, text: "INJECTED" }],
  }));
  assert.equal(items.length, 1);
  assert.deepEqual(Object.keys(items[0]).sort(), ["createdAt", "durationSeconds", "hasSummary", "id", "model"]);
  // Malformed payloads yield an empty shape, never a crash or partial trust.
  assert.deepEqual(decodeHistoryShape("not json"), []);
  assert.deepEqual(decodeHistoryShape(JSON.stringify({ items: [{ id: 5 }] })), []);
  assert.deepEqual(decodeHistoryShape(JSON.stringify({ items: [{ id: "a", createdAt: Number.NaN, durationSeconds: 1, model: "m", hasSummary: true }] })), []);
  assert.deepEqual(decodeHistoryShape(null), []);
  // Saving many items stores at most the cap.
  const many = Array.from({ length: 60 }, (_, index) => sampleItem({ _id: `rec_${index}` }));
  const capped = decodeHistoryShape(encodeHistoryShape(many));
  assert.equal(capped.length, maximumShapeItems);
});

test("boot shape load follows the hinted identity pointer and falls back safely", () => {
  const store = memoryStore();
  // Signed-in shape saved last: a hinted boot finds it via the pointer even
  // though the session id is not yet known.
  saveHistoryShape("anonymous", [sampleItem({ _id: "anon_1" })], store);
  saveHistoryShape("sess_abc", [sampleItem()], store);
  assert.equal(loadBootHistoryShape(true, store)[0]?.id, "rec_1");
  // Without a hint, the anonymous shape is the right one.
  assert.equal(loadBootHistoryShape(false, store)[0]?.id, "anon_1");
  // A hinted boot must never present an anonymous shape as account history.
  const anonymousOnly = memoryStore();
  saveHistoryShape("anonymous", [sampleItem({ _id: "anon_1" })], anonymousOnly);
  assert.deepEqual(loadBootHistoryShape(true, anonymousOnly), []);
  // No store (SSR/private-mode) reports an empty shape.
  assert.deepEqual(loadBootHistoryShape(true, null), []);
});

test("clearing removes the namespaced entry and its pointer, and storage failures are swallowed", () => {
  const store = memoryStore();
  saveHistoryShape("sess_abc", [sampleItem()], store);
  clearHistoryShape("sess_abc", store);
  assert.deepEqual(loadBootHistoryShape(true, store), []);
  assert.equal(store.map.size, 0, "the shape entry and the matching pointer are both removed");
  // Clearing one identity leaves another identity's pointer alone.
  saveHistoryShape("sess_abc", [sampleItem()], store);
  clearHistoryShape("sess_other", store);
  assert.equal(loadBootHistoryShape(true, store).length, 1);
  // Quota/privacy-mode style failures never throw out of the cache helpers.
  const throwing = memoryStore({
    getItem: () => { throw new Error("denied"); },
    setItem: () => { throw new Error("denied"); },
    removeItem: () => { throw new Error("denied"); },
  });
  saveHistoryShape("sess_abc", [sampleItem()], throwing);
  clearHistoryShape("sess_abc", throwing);
  assert.deepEqual(loadBootHistoryShape(true, throwing), []);
});

test("boot skips the anonymous history fetch when a Clerk session is hinted", async () => {
  const hook = await source("app/use-transcription-history.ts");
  // The skip decision reads the same cookie hint the Clerk mount gate uses.
  assert.match(hook, /import \{ hasClerkSessionHint, type AccountAuth \} from "\.\/providers"/);
  assert.match(hook, /awaitingHintedSession/);
  // Hardened deps: primitives plus the identity-stable refreshHistory only,
  // so a new account object cannot double-fetch on boot.
  assert.match(hook, /\}, \[account\.enabled, account\.isLoaded, account\.identityKey, refreshHistory\]\);/);
  assert.match(hook, /const refreshHistory = useCallback\([\s\S]*?\}, \[\]\);/);
  // Fail-closed anonymous fallback: if Clerk never resolves the hinted
  // session, a timer restores today's anonymous fetch (and is cleaned up).
  assert.match(hook, /hintedSessionFallbackMs = 8_000/);
  assert.match(hook, /window\.setTimeout\(\(\) => \{\s*if \(!awaitingHintedSession\.current\) return;/);
  assert.match(hook, /return \(\) => window\.clearTimeout\(fallback\);/);
  // Once the Clerk bridge publishes any identity, fetching resumes normally.
  assert.match(hook, /account\.isLoaded && \(!awaitingHintedSession\.current \|\| account\.enabled\)/);
  // The page consumes the hook instead of duplicating history state.
  const page = await source("app/page.tsx");
  assert.match(page, /useTranscriptionHistory\(account, setError\)/);
  assert.doesNotMatch(page, /listTranscriptions/);
});

test("history deletes are optimistic with sorted re-insert on failure", async () => {
  const hook = await source("app/use-transcription-history.ts");
  const removeOne = hook.slice(hook.indexOf("async function removeHistoryItem"), hook.indexOf("async function removeAllHistory"));
  const optimistic = removeOne.indexOf("setHistory((items) => items.filter((item) => item._id !== id))");
  const network = removeOne.indexOf("await deleteTranscription(id, token)");
  assert.ok(optimistic !== -1 && network !== -1 && optimistic < network, "the row must disappear before the network call");
  assert.match(removeOne, /insertSortedByCreatedAt\(items, removed\)/);
  assert.match(removeOne, /That history item could not be deleted\./);
  const removeAll = hook.slice(hook.indexOf("async function removeAllHistory"), hook.indexOf("async function changeRetention"));
  const cleared = removeAll.indexOf("setHistory([])");
  const clearCall = removeAll.indexOf("await clearTranscriptions(token)");
  assert.ok(cleared !== -1 && clearCall !== -1 && cleared < clearCall, "delete-all clears immediately after the confirm gate");
  assert.match(removeAll, /setHistory\(snapshotItems\);/);
  assert.match(removeAll, /setHistoryCursor\(snapshotCursor\);/);
  // Re-inserts keep newest-first ordering by createdAt.
  const { insertSortedByCreatedAt } = await import("../lib/convex.ts");
  const rows = [{ _id: "b", createdAt: 200 }, { _id: "d", createdAt: 50 }];
  assert.deepEqual(insertSortedByCreatedAt(rows, { _id: "c", createdAt: 100 }).map((row) => row._id), ["b", "c", "d"]);
});

test("retention saves settle immediately, refresh in the background, and roll back on failure", async () => {
  const hook = await source("app/use-transcription-history.ts");
  const body = hook.slice(hook.indexOf("async function changeRetention"), hook.indexOf("return {"));
  assert.match(body, /const previousDays = retentionDays;/);
  const saved = body.indexOf("await setRetention(days, token)");
  const released = body.indexOf("setRetentionSaving(false)");
  const backgroundRefresh = body.indexOf("void refreshHistory()");
  assert.ok(saved !== -1 && released !== -1 && saved < released, "saving clears as soon as setRetention resolves");
  assert.ok(backgroundRefresh !== -1 && released < backgroundRefresh, "the history refresh runs unawaited after the UI settles");
  assert.doesNotMatch(body, /await refreshHistory\(\)/);
  assert.match(body, /setRetentionDays\(previousDays\);/, "failure rolls the optimistic selection back");
});

test("summarizing from history gives immediate pending feedback", async () => {
  const [page, summaryHook, historyView] = await Promise.all([
    source("app/page.tsx"),
    source("app/use-transcript-summary.ts"),
    source("app/history-view.tsx"),
  ]);
  // Like openHistoryItem, the History-tab summarize action lands the visitor
  // in the studio where the summary card shows its loading state...
  assert.match(page, /setActiveTranscriptionId\(item\._id\); setActiveTab\("studio"\); void summarizeText\(item\.text, item\._id\);/);
  // ...and the pending row itself is disabled with a Summarizing… label if
  // the visitor returns to the History tab mid-generation.
  assert.match(summaryHook, /setSummarizingId\(transcriptionId\);/);
  assert.match(summaryHook, /setSummarizingId\(null\);/);
  assert.match(historyView, /disabled=\{props\.summarizingId === item\._id\}/);
  assert.match(historyView, /props\.summarizingId === item\._id \? "Summarizing…"/);
});

test("boot skeleton rows are obviously placeholders shaped by metadata, never text", async () => {
  const [historyView, hook, css] = await Promise.all([
    source("app/history-view.tsx"),
    source("app/use-transcription-history.ts"),
    source("app/globals.css"),
  ]);
  // Skeleton renders only while the first load is in flight with no rows yet.
  assert.match(historyView, /props\.loading && !props\.history\.length \? props\.bootShape : \[\]/);
  // Shimmer bars only — hidden from assistive tech, no strings that could
  // read as transcript or summary content.
  const skeleton = historyView.slice(historyView.indexOf("function HistorySkeletonList"), historyView.indexOf("export function HistoryView"));
  assert.match(skeleton, /aria-hidden="true"/);
  assert.match(skeleton, /history-skeleton-bar/);
  assert.doesNotMatch(skeleton, /\{item\.(text|summary|model)\}|toLocaleString/);
  assert.match(skeleton, /item\.hasSummary &&/);
  assert.match(css, /history-skeleton-shimmer/);
  assert.match(css, /prefers-reduced-motion/);
  // The cache is refreshed after successful loads and cleared on the
  // delete-all and sign-out paths.
  assert.match(hook, /saveHistoryShape\(snapshot\.identityKey, result\.items\);/);
  assert.match(hook, /clearHistoryShape\(account\.identityKey\);/);
  assert.match(hook, /account\.identityKey === "anonymous" && previous !== "anonymous"\) clearHistoryShape\(previous\);/);
});
