"use client";

// Summary generation and persistence state for the Home page. Extracted from
// app/page.tsx so both files stay reviewable and under the size cap.
//
// Generation and persistence are decoupled: the generated summary is revealed
// as soon as the model returns it, while the history PATCH continues in the
// background and surfaces a non-blocking notice on failure. A summary
// requested while the transcript's own history save is still in flight
// serializes its PATCH on that save's promise so it is never dropped.

import { useState, type Dispatch, type SetStateAction } from "react";
import { saveTranscriptionSummary, type TranscriptionHistoryItem } from "../lib/convex";
import type { AccountAuth } from "./providers";

type SetHistory = Dispatch<SetStateAction<TranscriptionHistoryItem[]>>;

export function useTranscriptSummary(account: AccountAuth, setHistory: SetHistory) {
  const [summary, setSummary] = useState("");
  const [summaryLoading, setSummaryLoading] = useState(false);
  // The history row a summary is currently being generated for, so the
  // History tab can show that row's immediate pending state.
  const [summarizingId, setSummarizingId] = useState<string | null>(null);
  const [summaryError, setSummaryError] = useState("");
  const [summaryNotice, setSummaryNotice] = useState("");
  const [summaryCopied, setSummaryCopied] = useState(false);

  async function summarizeText(value: string, transcriptionId: string | null, pendingSave: Promise<string | null> | null = null) {
    if (!value.trim() || summaryLoading) return;
    // If the transcript's history save is still in flight, remember it so
    // the summary PATCH can attach to the saved id once the save settles.
    const pendingSavedId = transcriptionId ? null : pendingSave;
    setSummaryLoading(true);
    setSummarizingId(transcriptionId);
    setSummaryError("");
    setSummaryNotice("");
    setSummary("");
    try {
      const response = await fetch("/api/summarize", {
        method: "POST",
        cache: "no-store",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ text: value }),
      });
      const result = await response.json() as { summary?: string; error?: string };
      if (!response.ok || !result.summary) throw new Error(result.error ?? "Summary generation failed");
      const generatedSummary = result.summary;
      setSummary(generatedSummary);
      // The summary is revealed immediately; persistence continues in the
      // background with a non-blocking notice if it fails.
      void persistSummary(transcriptionId, pendingSavedId, generatedSummary);
    } catch {
      setSummaryError("Summarizing failed. Try again.");
    } finally {
      setSummaryLoading(false);
      setSummarizingId(null);
    }
  }

  async function persistSummary(transcriptionId: string | null, pendingSavedId: Promise<string | null> | null, generatedSummary: string) {
    const targetId = transcriptionId ?? (pendingSavedId ? await pendingSavedId : null);
    if (!targetId) {
      if (pendingSavedId) setSummaryNotice("The summary could not be saved to history because the transcript was not saved.");
      return;
    }
    try {
      const token = await account.getConvexToken();
      await saveTranscriptionSummary(targetId, generatedSummary, token);
      setHistory((items) => items.map((item) => item._id === targetId ? { ...item, summary: generatedSummary } : item));
    } catch {
      setSummaryNotice("The summary is shown here but could not be saved to history.");
    }
  }

  async function copySummary() {
    await navigator.clipboard.writeText(summary);
    setSummaryCopied(true);
    setTimeout(() => setSummaryCopied(false), 1500);
  }

  return {
    summary,
    setSummary,
    summaryLoading,
    summarizingId,
    summaryError,
    setSummaryError,
    summaryNotice,
    setSummaryNotice,
    summaryCopied,
    summarizeText,
    copySummary,
  };
}
