"use client";

import { useRef, useState } from "react";
import type { TranscriptionHistoryItem } from "../lib/convex";
import { downloadTranscript } from "../lib/transcriptExport";
import { TEXT_GENERATION_MODEL_LABEL } from "../shared/textGenerationContract";
import type { TranscriptionSegment } from "../shared/transcriptionContract";
import { AIEnhancementPanel } from "./ai-enhancement";
import { AccountControls } from "./account-controls";
import { useAccountAuth } from "./providers";
import { HistoryView } from "./history-view";
import { recordingStage } from "./recording-stage";
import { TTSWorkspace } from "./tts-workspace";
import { useTheme } from "./use-theme";
import { useTranscriptionHistory } from "./use-transcription-history";
import { useTranscriptionSession } from "./use-transcription-session";
import { useTranscriptSummary } from "./use-transcript-summary";

type WorkspaceTab = "studio" | "history";

export default function Home() {
  const account = useAccountAuth();
  const audioFileInput = useRef<HTMLInputElement | null>(null);
  const [transcript, setTranscript] = useState("");
  const [transcriptSegments, setTranscriptSegments] = useState<TranscriptionSegment[]>([]);
  const [activeTranscriptionId, setActiveTranscriptionId] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [copied, setCopied] = useState(false);
  const [speechText, setSpeechText] = useState("");
  const [activeTab, setActiveTab] = useState<WorkspaceTab>("studio");
  const { theme, selectTheme } = useTheme();
  const {
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
  } = useTranscriptionHistory(account, setError);
  const {
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
  } = useTranscriptSummary(account, setHistory);
  const session = useTranscriptionSession({
    account,
    setHistory,
    setError,
    transcript: {
      clear: ({ summaryError: clearSummaryError }) => {
        setTranscript("");
        setTranscriptSegments([]);
        setActiveTranscriptionId(null);
        setSummary("");
        if (clearSummaryError) setSummaryError("");
        setSummaryNotice("");
      },
      show: (text, segments) => {
        setTranscript(text);
        setTranscriptSegments(segments);
      },
      saved: setActiveTranscriptionId,
    },
  });
  const { status } = session;
  const stage = recordingStage(status, session.elapsed, session.transcribeElapsed);

  async function copyTranscript() {
    await navigator.clipboard.writeText(transcript);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }

  function openHistoryItem(item: TranscriptionHistoryItem) {
    setTranscript(item.text);
    setTranscriptSegments(item.segments ?? []);
    setActiveTranscriptionId(item._id);
    setSummary(item.summary ?? "");
    setSummaryError("");
    setSummaryNotice("");
    setActiveTab("studio");
  }

  return (
    <main>
      <header className="topbar">
        <a className="brand" href="#" aria-label="VoiceInk Web home">
          <span className="brand-mark">V</span><span>VoiceInk <em>web</em></span>
        </a>
        <div className="header-actions">
          <nav className="workspace-tabs" aria-label="Workspace">
            <button className={activeTab === "studio" ? "active" : ""} onClick={() => setActiveTab("studio")} aria-current={activeTab === "studio" ? "page" : undefined}>Studio</button>
            <button className={activeTab === "history" ? "active" : ""} onClick={() => setActiveTab("history")} aria-current={activeTab === "history" ? "page" : undefined}>History</button>
          </nav>
          <AccountControls />
          <div className="theme-switch" aria-label="Appearance" role="group">
            <button className={theme === "editorial" ? "active" : ""} onClick={() => selectTheme("editorial")} aria-pressed={theme === "editorial"}>Original</button>
            <button className={theme === "mac" ? "active" : ""} onClick={() => selectTheme("mac")} aria-pressed={theme === "mac"}>Mac</button>
          </div>
        </div>
      </header>

      {activeTab === "studio" ? <>
      <section className="hero">
        <h1>Transcription</h1>
        <p>Record or upload audio and get an editable transcript. Audio is processed in the cloud.</p>
      </section>

      <section className={`recorder-card ${status === "recording" ? "is-recording" : ""}`}>
        <div className="card-header">
          <div><h2>{stage.heading}</h2></div>
          <span className="privacy">Audio deleted after transcription</span>
        </div>

        <div className="wave" aria-hidden="true">
          {Array.from({ length: 42 }, (_, index) => <span key={index} style={{ height: `${12 + ((index * 17) % 54)}px`, "--i": index } as React.CSSProperties} />)}
        </div>

        <div className="record-controls">
          {status !== "recording" ? (
            <button className="record-button" onClick={() => void session.startRecording()} disabled={stage.busy} aria-label="Start recording"><span /></button>
          ) : (
            <button className="record-button stop" onClick={session.stopRecording} aria-label="Stop recording"><span /></button>
          )}
          <div><strong>{stage.strong}</strong><small>{stage.small}</small></div>
        </div>
        <div className="audio-upload">
          <span>or</span>
          <button type="button" onClick={() => audioFileInput.current?.click()} disabled={stage.busy || status === "recording"}>Upload audio file</button>
          <small>MP3, WAV, M4A, WebM and other browser-supported audio · 24 MB maximum · {account.isSignedIn ? "up to 2 hours" : "up to 10 minutes for guests"}</small>
          <input ref={audioFileInput} type="file" accept="audio/*" hidden onChange={(event) => {
            const file = event.target.files?.[0];
            if (file) void session.uploadAudio(file);
            event.target.value = "";
          }} />
        </div>

        {session.audio && status === "error" && (
          <button className="primary" onClick={session.retryTranscription}>
            Retry transcription
          </button>
        )}
        {error && <p className="error" role="alert">{error}</p>}
      </section>

      <section className="transcript-card">
        <div className="transcript-head"><div><small>TRANSCRIPT</small><span>{transcript ? `${transcript.split(/\s+/).length} words` : "Waiting for audio"}</span></div>{transcript && <div className="transcript-tools"><button className="summarize" onClick={() => void summarizeText(transcript, activeTranscriptionId, session.pendingSave.current)} disabled={summaryLoading}>{summaryLoading ? "Summarizing…" : "Summarize"}</button><button onClick={copyTranscript}>{copied ? "Copied" : "Copy"}</button><button onClick={() => downloadTranscript(transcript, "txt")}>TXT</button><button disabled={!transcriptSegments.length} title={transcriptSegments.length ? "Download timed subtitles" : "Timing is unavailable after editing"} onClick={() => downloadTranscript(transcript, "srt", transcriptSegments)}>SRT</button><button disabled={!transcriptSegments.length} title={transcriptSegments.length ? "Download timed subtitles" : "Timing is unavailable after editing"} onClick={() => downloadTranscript(transcript, "vtt", transcriptSegments)}>VTT</button></div>}</div>
        <textarea aria-label="Transcript text" value={transcript} onChange={(event) => { setTranscript(event.target.value); setTranscriptSegments([]); }} placeholder="Your transcription will appear here…" />
      </section>

      {transcript && <AIEnhancementPanel text={transcript} onApply={(value) => { setTranscript(value); setTranscriptSegments([]); setSummary(""); setSummaryError(""); setSummaryNotice(""); }} onNarrate={setSpeechText} />}

      {(summary || summaryLoading || summaryError) && <section className="summary-card"><div className="summary-head"><div><small>SUMMARY</small><span>{TEXT_GENERATION_MODEL_LABEL}</span></div>{summary && <div><button onClick={() => void copySummary()}>{summaryCopied ? "Copied" : "Copy"}</button><button onClick={() => setSpeechText(summary)}>Narrate summary</button></div>}</div>{summaryLoading ? <div className="result-placeholder" role="status" aria-label="Summarizing"><span /><span /><span /></div> : summary ? <textarea aria-label="AI-generated transcript summary" value={summary} onChange={(event) => setSummary(event.target.value)} /> : <p className="error" role="alert">{summaryError}</p>}{summaryNotice && <p className="summary-notice" role="status">{summaryNotice}</p>}<p className="ai-note">AI-generated summaries can make mistakes. Check important details against the transcript.</p></section>}

      <TTSWorkspace transcript={transcript} text={speechText} onTextChange={setSpeechText} />

      </> : <HistoryView history={history} loading={historyLoading} bootShape={bootShape} summarizingId={summarizingId} hasMore={historyCursor !== null} isSignedIn={account.isSignedIn} retentionDays={retentionDays} retentionSaving={retentionSaving} retentionStatus={retentionStatus} onRefresh={() => void refreshHistory()} onLoadMore={() => void loadMoreHistory()} onRetentionChange={(days) => void changeRetention(days)} onOpen={openHistoryItem} onNarrate={setSpeechText} onSummarize={(item) => { setTranscript(item.text); setTranscriptSegments(item.segments ?? []); setActiveTranscriptionId(item._id); setActiveTab("studio"); void summarizeText(item.text, item._id); }} onDelete={(id) => void removeHistoryItem(id)} onDeleteAll={() => void removeAllHistory()} />}

      <footer><span>VoiceInk Web 2.11.0</span><span>Deepgram Nova-3 · Whisper large-v3 turbo · {TEXT_GENERATION_MODEL_LABEL}</span></footer>
    </main>
  );
}
