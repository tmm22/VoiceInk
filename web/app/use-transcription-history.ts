"use client";

// History state for the Home page: boot fetch scheduling, pagination,
// optimistic deletes, retention, and the boot skeleton shape cache. Extracted
// from app/page.tsx so both files stay reviewable and under the size cap.

import { useCallback, useEffect, useRef, useState } from "react";
import {
  clearTranscriptions,
  deleteTranscription,
  insertSortedByCreatedAt,
  listTranscriptions,
  setRetention,
  type RetentionDays,
  type TranscriptionHistoryItem,
} from "../lib/convex";
import {
  clearHistoryShape,
  loadBootHistoryShape,
  saveHistoryShape,
  type HistoryShapeItem,
} from "../lib/historyMetadataCache";
import { hasClerkSessionHint, type AccountAuth } from "./providers";

const accountsConfigured = Boolean(
  process.env.NEXT_PUBLIC_CONVEX_URL && process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY,
);
// If Clerk never resolves the hinted session (blocked clerk-js, failed
// chunk), fall back to the fail-closed anonymous history fetch instead of
// leaving the skeleton up forever. Generous against ~1s worst-case loads.
const hintedSessionFallbackMs = 8_000;

export function useTranscriptionHistory(account: AccountAuth, onError: (message: string) => void) {
  // Latest-value refs keep refreshHistory identity-stable so the boot effect
  // depends on primitives only and cannot double-fetch. Synced in an effect
  // (declared before every effect that reads them) because the hooks lint
  // forbids ref writes during render.
  const accountRef = useRef(account);
  const onErrorRef = useRef(onError);
  useEffect(() => {
    accountRef.current = account;
    onErrorRef.current = onError;
  });

  const [history, setHistory] = useState<TranscriptionHistoryItem[]>([]);
  const [historyLoading, setHistoryLoading] = useState(true);
  const [historyCursor, setHistoryCursor] = useState<string | null>(null);
  const [bootShape, setBootShape] = useState<HistoryShapeItem[]>([]);
  const [retentionDays, setRetentionDays] = useState<RetentionDays>(90);
  const [retentionSaving, setRetentionSaving] = useState(false);
  const [retentionStatus, setRetentionStatus] = useState("");

  const refreshHistory = useCallback(async () => {
    const snapshot = accountRef.current;
    setHistoryLoading(true);
    try {
      const token = await snapshot.getConvexToken();
      const result = await listTranscriptions(token);
      setHistory(result.items);
      setHistoryCursor(result.nextCursor);
      if (snapshot.isSignedIn && result.retentionDays !== null) setRetentionDays(result.retentionDays);
      // Shape metadata only (ids/timestamps/durations/models/summary flags);
      // the cache module whitelists fields so no transcript text is stored.
      saveHistoryShape(snapshot.identityKey, result.items);
    } catch {
      setHistory([]);
      onErrorRef.current("History is temporarily unavailable. Recording and transcription can still be used.");
    } finally {
      setHistoryLoading(false);
    }
  }, []);

  // Boot skeleton: read the cached shape after mount (it must not affect the
  // hydration markup, and the lint rules forbid synchronous setState in an
  // effect — same deferred pattern as the saved-theme read).
  useEffect(() => {
    const shapeLoad = window.setTimeout(() => {
      setBootShape(loadBootHistoryShape(hasClerkSessionHint()));
    }, 0);
    return () => window.clearTimeout(shapeLoad);
  }, []);

  // Sign-out drops the signed-in identity's cached shape metadata.
  const previousIdentity = useRef(account.identityKey);
  useEffect(() => {
    const previous = previousIdentity.current;
    if (previous === account.identityKey) return;
    previousIdentity.current = account.identityKey;
    if (account.identityKey === "anonymous" && previous !== "anonymous") clearHistoryShape(previous);
  }, [account.identityKey]);

  // Boot fetch scheduling. When the Clerk session-hint cookie is present at
  // boot, the signed-in identity is about to replace the anonymous one, so
  // the anonymous boot fetch is skipped (the history area keeps its
  // loading/skeleton state) and the effect refire once the bridge publishes a
  // loaded identity performs the single fetch. Once the Clerk bridge has
  // published any identity (account.enabled) — signed in, signed out, or the
  // hint turned out stale — every later change fetches normally, and a
  // fallback timer restores the fail-closed anonymous fetch if Clerk never
  // resolves at all. Visitors without the cookie keep today's behavior: one
  // immediate anonymous fetch.
  const awaitingHintedSession = useRef<boolean | null>(null);
  useEffect(() => {
    if (awaitingHintedSession.current === null) {
      awaitingHintedSession.current = accountsConfigured && !accountRef.current.enabled && hasClerkSessionHint();
    }
    if (account.isLoaded && (!awaitingHintedSession.current || account.enabled)) {
      awaitingHintedSession.current = false;
      queueMicrotask(() => {
        void refreshHistory();
      });
      return;
    }
    if (!awaitingHintedSession.current) return;
    const fallback = window.setTimeout(() => {
      if (!awaitingHintedSession.current) return;
      awaitingHintedSession.current = false;
      void refreshHistory();
    }, hintedSessionFallbackMs);
    return () => window.clearTimeout(fallback);
  }, [account.enabled, account.isLoaded, account.identityKey, refreshHistory]);

  async function loadMoreHistory() {
    if (!historyCursor || historyLoading) return;
    setHistoryLoading(true);
    try {
      const token = await account.getConvexToken();
      const result = await listTranscriptions(token, historyCursor);
      setHistory((items) => [...items, ...result.items.filter((item) => !items.some((existing) => existing._id === item._id))]);
      setHistoryCursor(result.nextCursor);
    } catch {
      onError("More history could not be loaded. Please try again.");
    } finally {
      setHistoryLoading(false);
    }
  }

  // Optimistic delete: drop the row immediately, confirm over the network;
  // on failure re-insert it (sorted by createdAt) and surface the banner.
  async function removeHistoryItem(id: string) {
    const removed = history.find((item) => item._id === id);
    setHistory((items) => items.filter((item) => item._id !== id));
    try {
      const token = await account.getConvexToken();
      await deleteTranscription(id, token);
    } catch {
      if (removed) setHistory((items) => (items.some((item) => item._id === id) ? items : insertSortedByCreatedAt(items, removed)));
      onError("That history item could not be deleted.");
    }
  }

  // Already confirm-gated by the caller: snapshot, clear immediately, and
  // restore the snapshot when the network call fails.
  async function removeAllHistory() {
    const snapshotItems = history;
    const snapshotCursor = historyCursor;
    setHistory([]);
    setHistoryCursor(null);
    try {
      const token = await account.getConvexToken();
      await clearTranscriptions(token);
      clearHistoryShape(account.identityKey);
    } catch {
      setHistory(snapshotItems);
      setHistoryCursor(snapshotCursor);
      onError("History could not be cleared.");
    }
  }

  // Retention saves settle as soon as the server accepts them; the follow-up
  // history refresh runs unawaited in the background, and a failure rolls the
  // optimistic selection back instead of leaving it stale.
  async function changeRetention(days: RetentionDays) {
    const previousDays = retentionDays;
    setRetentionDays(days);
    setRetentionSaving(true);
    setRetentionStatus("");
    try {
      const token = await account.getConvexToken();
      await setRetention(days, token);
      setRetentionSaving(false);
      setRetentionStatus(days === 0 ? "History will be kept until you delete it." : `History older than ${days} days will be deleted automatically.`);
      void refreshHistory();
    } catch {
      setRetentionDays(previousDays);
      setRetentionSaving(false);
      setRetentionStatus("Retention could not be updated.");
    }
  }

  return {
    history,
    setHistory,
    historyLoading,
    historyCursor,
    bootShape,
    retentionDays,
    retentionSaving,
    retentionStatus,
    refreshHistory,
    loadMoreHistory,
    removeHistoryItem,
    removeAllHistory,
    changeRetention,
  };
}
