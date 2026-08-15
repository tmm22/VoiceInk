"use client";

import { useMemo, useState } from "react";
import type { RetentionDays, TranscriptionHistoryItem } from "../lib/convex";
import { downloadTranscript } from "../lib/transcriptExport";

type Props = {
  history: TranscriptionHistoryItem[];
  loading: boolean;
  isSignedIn: boolean;
  retentionDays: RetentionDays;
  retentionSaving: boolean;
  retentionStatus: string;
  onRefresh: () => void;
  onRetentionChange: (days: RetentionDays) => void;
  onOpen: (item: TranscriptionHistoryItem) => void;
  onNarrate: (text: string) => void;
  onSummarize: (item: TranscriptionHistoryItem) => void;
  onDelete: (id: string) => void;
};

export function HistoryView(props: Props) {
  const [search, setSearch] = useState("");
  const visible = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return props.history;
    return props.history.filter((item) => `${item.text} ${item.summary ?? ""}`.toLowerCase().includes(query));
  }, [props.history, search]);

  return (
    <section className="history-workspace">
      <div className="history-title">
        <div><small>TRANSCRIPTION LIBRARY</small><h1>History</h1><p>Review transcripts and their AI summaries away from the recording studio.</p></div>
        <div className="history-actions"><input aria-label="Search transcription history" type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search transcripts and summaries" /><button onClick={props.onRefresh} disabled={props.loading}>{props.loading ? "Loading…" : "Refresh"}</button></div>
      </div>
      <div className="history-card history-library">
        <div className="history-head"><div><small>SAVED ITEMS</small><span>{props.isSignedIn ? "Synced across your devices" : "Anonymous history expires after one hour"}</span></div><strong>{visible.length} item{visible.length === 1 ? "" : "s"}</strong></div>
        {props.isSignedIn && <div className="retention-settings"><label htmlFor="retention-days">Automatically delete history after</label><select id="retention-days" value={props.retentionDays} disabled={props.retentionSaving} onChange={(event) => props.onRetentionChange(Number(event.target.value) as RetentionDays)}><option value={7}>7 days</option><option value={30}>30 days</option><option value={90}>90 days</option><option value={365}>1 year</option><option value={0}>Never automatically</option></select>{props.retentionSaving && <span>Saving…</span>}{props.retentionStatus && <span>{props.retentionStatus}</span>}</div>}
        {visible.length ? <div className="history-library-list">{visible.map((item) => <article className="history-library-item" key={item._id}><div className="history-item-meta"><span>{new Date(item.createdAt).toLocaleString()}</span><span>{item.durationSeconds}s · {item.model}</span></div><h2>Transcript</h2><p className="history-transcript">{item.text}</p><h2>AI summary</h2>{item.summary ? <p className="history-summary">{item.summary}</p> : <p className="history-summary empty">No summary generated yet.</p>}<div className="history-library-tools"><button onClick={() => props.onOpen(item)}>Open in studio</button><button onClick={() => props.onSummarize(item)}>{item.summary ? "Regenerate summary" : "Generate summary"}</button><button onClick={() => props.onNarrate(item.summary ?? item.text)}>Narrate {item.summary ? "summary" : "transcript"}</button><button onClick={() => downloadTranscript(item.text, "txt")}>TXT</button><button className="delete" onClick={() => props.onDelete(item._id)}>Delete</button></div></article>)}</div> : <p className="history-empty">{search ? "No transcripts or summaries match your search." : "Your completed recordings will appear here automatically."}</p>}
      </div>
    </section>
  );
}
