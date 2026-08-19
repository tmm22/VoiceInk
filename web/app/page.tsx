"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  clearTranscriptions,
  deleteTranscription,
  listTranscriptions,
  saveTranscription,
  saveTranscriptionSummary,
  setRetention,
  type RetentionDays,
  type TranscriptionHistoryItem,
} from "../lib/convex";
import { downloadTranscript } from "../lib/transcriptExport";
import {
  elapsedRecordingSeconds,
  readAudioDuration,
  recordingLimitSeconds,
  selectRecorderMimeType,
  uploadDurationError,
  uploadSizeError,
} from "../lib/recording";
import { requestTranscription, transcriptionFailureMessage } from "../lib/transcriptionRequest";
import { warmTranscriptionChallenge } from "../lib/turnstileClient";
import { AIEnhancementPanel } from "./ai-enhancement";
import { AccountControls, useAccountAuth } from "./providers";
import { HistoryView } from "./history-view";
import { TTSWorkspace } from "./tts-workspace";
import {
  MAXIMUM_AUDIO_BYTES,
  type TranscriptionSegment,
} from "../shared/transcriptionContract";

type Status = "idle" | "starting" | "recording" | "validating" | "transcribing" | "done" | "error";
type Theme = "editorial" | "mac";
type WorkspaceTab = "studio" | "history";
const transcriptionTimeoutMs = 5 * 60 * 1_000;

export default function Home() {
  const account = useAccountAuth();
  const isSignedInRef = useRef(account.isSignedIn);
  isSignedInRef.current = account.isSignedIn;
  const recorder = useRef<MediaRecorder | null>(null);
  const chunks = useRef<Blob[]>([]);
  const ticker = useRef<ReturnType<typeof setInterval> | null>(null);
  const audioFileInput = useRef<HTMLInputElement | null>(null);
  const elapsedRef = useRef(0);
  const recordingStartedAt = useRef(0);
  const recordedBytes = useRef(0);
  const recordingTooLarge = useRef(false);
  const recordingFailed = useRef(false);
  const audioOperationId = useRef<string | null>(null);
  const activeTranscription = useRef<{ id: string; controller: AbortController } | null>(null);
  const operationGeneration = useRef(0);
  const recordingStartPending = useRef(false);
  const [status, setStatus] = useState<Status>("idle");
  const [elapsed, setElapsed] = useState(0);
  const [audio, setAudio] = useState<Blob | null>(null);
  const [transcript, setTranscript] = useState("");
  const [transcriptSegments, setTranscriptSegments] = useState<TranscriptionSegment[]>([]);
  const [activeTranscriptionId, setActiveTranscriptionId] = useState<string | null>(null);
  const [summary, setSummary] = useState("");
  const [summaryLoading, setSummaryLoading] = useState(false);
  const [summaryError, setSummaryError] = useState("");
  const [error, setError] = useState("");
  const [copied, setCopied] = useState(false);
  const [history, setHistory] = useState<TranscriptionHistoryItem[]>([]);
  const [historyLoading, setHistoryLoading] = useState(true);
  const [historyCursor, setHistoryCursor] = useState<string | null>(null);
  const [speechText, setSpeechText] = useState("");
  const [theme, setTheme] = useState<Theme>("editorial");
  const [activeTab, setActiveTab] = useState<WorkspaceTab>("studio");
  const [retentionDays, setRetentionDays] = useState<RetentionDays>(90);
  const [retentionSaving, setRetentionSaving] = useState(false);
  const [retentionStatus, setRetentionStatus] = useState("");

  const refreshHistory = useCallback(async () => {
    setHistoryLoading(true);
    try {
      const token = await account.getConvexToken();
      const result = await listTranscriptions(token);
      setHistory(result.items);
      setHistoryCursor(result.nextCursor);
      if (account.isSignedIn && result.retentionDays !== null) setRetentionDays(result.retentionDays);
    } catch {
      setHistory([]);
      setError("History is temporarily unavailable. Recording and transcription can still be used.");
    } finally {
      setHistoryLoading(false);
    }
  }, [account]);

  async function loadMoreHistory() {
    if (!historyCursor || historyLoading) return;
    setHistoryLoading(true);
    try {
      const token = await account.getConvexToken();
      const result = await listTranscriptions(token, historyCursor);
      setHistory((items) => [...items, ...result.items.filter((item) => !items.some((existing) => existing._id === item._id))]);
      setHistoryCursor(result.nextCursor);
    } catch {
      setError("More history could not be loaded. Please try again.");
    } finally {
      setHistoryLoading(false);
    }
  }

  useEffect(() => {
    let themeUpdate: number | undefined;
    const savedTheme = window.localStorage.getItem("voiceink-theme");
    if (savedTheme === "mac" || savedTheme === "editorial") {
      themeUpdate = window.setTimeout(() => setTheme(savedTheme), 0);
      document.documentElement.dataset.theme = savedTheme;
    }
    return () => {
      if (themeUpdate !== undefined) window.clearTimeout(themeUpdate);
      if (ticker.current) clearInterval(ticker.current);
      const pendingTranscription = activeTranscription.current;
      activeTranscription.current = null;
      pendingTranscription?.controller.abort();
      operationGeneration.current += 1;
      const activeRecorder = recorder.current;
      recorder.current = null;
      if (activeRecorder) {
        activeRecorder.ondataavailable = null;
        activeRecorder.onerror = null;
        activeRecorder.onstop = null;
        if (activeRecorder.state === "recording") activeRecorder.stop();
        activeRecorder.stream.getTracks().forEach((track) => track.stop());
      }
      chunks.current = [];
    };
  }, []);

  useEffect(() => {
    if (account.isLoaded) {
      queueMicrotask(() => {
        void refreshHistory();
      });
    }
  }, [account.identityKey, account.isLoaded, refreshHistory]);

  function selectTheme(nextTheme: Theme) {
    setTheme(nextTheme);
    document.documentElement.dataset.theme = nextTheme;
    window.localStorage.setItem("voiceink-theme", nextTheme);
  }

  async function changeRetention(days: RetentionDays) {
    setRetentionDays(days);
    setRetentionSaving(true);
    setRetentionStatus("");
    try {
      const token = await account.getConvexToken();
      await setRetention(days, token);
      await refreshHistory();
      setRetentionStatus(days === 0 ? "History will be kept until you delete it." : `History older than ${days} days will be deleted automatically.`);
    } catch {
      setRetentionStatus("Retention could not be updated.");
    } finally {
      setRetentionSaving(false);
    }
  }

  async function startRecording() {
    if (recordingStartPending.current || recorder.current) return;
    recordingStartPending.current = true;
    warmTranscriptionChallenge(); // preload the Turnstile script/widget; single-use tokens are still acquired at stop time
    const generation = ++operationGeneration.current;
    let stream: MediaStream | undefined;
    try {
      const previousTranscription = activeTranscription.current;
      activeTranscription.current = null;
      previousTranscription?.controller.abort();
      setError("");
      setTranscript("");
      setTranscriptSegments([]);
      setActiveTranscriptionId(null);
      setSummary("");
      setAudio(null);
      setElapsed(0);
      setStatus("starting");
      elapsedRef.current = 0;
      const acquiredStream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true } });
      stream = acquiredStream;
      if (generation !== operationGeneration.current) {
        acquiredStream.getTracks().forEach((track) => track.stop());
        return;
      }
      const mimeType = selectRecorderMimeType((value) => MediaRecorder.isTypeSupported(value));
      let nextRecorder: MediaRecorder;
      try {
        nextRecorder = new MediaRecorder(acquiredStream, { ...(mimeType ? { mimeType } : {}), audioBitsPerSecond: 64_000 });
      } catch (recorderError) {
        acquiredStream.getTracks().forEach((track) => track.stop());
        throw recorderError;
      }
      chunks.current = [];
      recordedBytes.current = 0;
      recordingTooLarge.current = false;
      recordingFailed.current = false;
      recordingStartedAt.current = performance.now();
      audioOperationId.current = crypto.randomUUID();
      nextRecorder.ondataavailable = (event) => {
        if (generation !== operationGeneration.current || !event.data.size) return;
        recordedBytes.current += event.data.size;
        if (recordedBytes.current > MAXIMUM_AUDIO_BYTES) {
          recordingTooLarge.current = true;
          if (nextRecorder.state === "recording") nextRecorder.stop();
          return;
        }
        chunks.current.push(event.data);
      };
      nextRecorder.onstop = () => {
        if (ticker.current) clearInterval(ticker.current);
        ticker.current = null;
        const duration = elapsedRecordingSeconds(recordingStartedAt.current, performance.now());
        elapsedRef.current = duration;
        setElapsed(duration);
        const completedChunks = chunks.current;
        chunks.current = [];
        recorder.current = null;
        acquiredStream.getTracks().forEach((track) => track.stop());
        if (generation !== operationGeneration.current) return;
        if (recordingTooLarge.current) {
          setAudio(null);
          setError("The recording reached the 24 MB safety limit. Record a shorter clip and try again.");
          setStatus("error");
          return;
        }
        if (recordingFailed.current) {
          setAudio(null);
          setStatus("error");
          return;
        }
        const recording = new Blob(completedChunks, { type: nextRecorder.mimeType });
        setAudio(recording);
        void transcribe(recording, duration, audioOperationId.current ?? crypto.randomUUID());
      };
      nextRecorder.onerror = () => {
        if (generation !== operationGeneration.current) return;
        recordingFailed.current = true;
        setError("Recording stopped because the browser audio encoder failed.");
        if (nextRecorder.state === "recording") nextRecorder.stop();
      };
      nextRecorder.start(1_000);
      recorder.current = nextRecorder;
      setStatus("recording");
      ticker.current = setInterval(() => {
        elapsedRef.current = elapsedRecordingSeconds(recordingStartedAt.current, performance.now());
        setElapsed(elapsedRef.current);
        if (elapsedRef.current >= recordingLimitSeconds(isSignedInRef.current)) {
          if (ticker.current) clearInterval(ticker.current);
          ticker.current = null;
          recorder.current?.stop();
        }
      }, 1000);
    } catch {
      stream?.getTracks().forEach((track) => track.stop());
      if (generation === operationGeneration.current) {
        setError("Microphone access is required to record a transcription.");
        setStatus("error");
      }
    } finally {
      recordingStartPending.current = false;
    }
  }

  function stopRecording() {
    if (ticker.current) clearInterval(ticker.current);
    ticker.current = null;
    if (recorder.current?.state === "recording") recorder.current.stop();
  }

  async function transcribe(recording: Blob, durationSeconds: number, operationId = audioOperationId.current ?? crypto.randomUUID()) {
    activeTranscription.current?.controller.abort();
    const controller = new AbortController();
    const job = { id: crypto.randomUUID(), controller };
    activeTranscription.current = job;
    audioOperationId.current = operationId;
    const timeout = window.setTimeout(() => controller.abort(), transcriptionTimeoutMs);
    setStatus("transcribing");
    setError("");
    try {
      const result = await requestTranscription(recording, controller.signal);
      const transcribedText = result.text;
      const effectiveDuration = result.durationSeconds ?? durationSeconds;
      if (activeTranscription.current?.id !== job.id) return;
      setAudio(null);
      chunks.current = [];
      setTranscript(transcribedText);
      setTranscriptSegments(result.segments ?? []);
      setStatus("done");
      try {
        const token = await account.getConvexToken();
        const savedId = await saveTranscription({
          text: transcribedText,
          durationSeconds: effectiveDuration,
          model: result.model,
          detectedLanguage: result.detectedLanguage,
          operationId,
          segments: result.segments,
        }, token);
        if (activeTranscription.current?.id !== job.id) return;
        setActiveTranscriptionId(savedId ?? null);
        await refreshHistory();
      } catch {
        setError("The transcript is ready, but it could not be saved to history. Check your quota or retention settings.");
      }
    } catch (cause) {
      if (activeTranscription.current?.id !== job.id) return;
      if (controller.signal.aborted) {
        setError("Transcription timed out. Your recording is still available to retry.");
        setStatus("error");
        return;
      }
      setError(transcriptionFailureMessage(cause));
      setStatus("error");
    } finally {
      window.clearTimeout(timeout);
      if (activeTranscription.current?.id === job.id) activeTranscription.current = null;
    }
  }

  async function uploadAudio(file: File) {
    const sizeError = uploadSizeError(file.size, MAXIMUM_AUDIO_BYTES);
    if (sizeError) {
      setError(sizeError);
      return;
    }
    const generation = ++operationGeneration.current;
    const previousTranscription = activeTranscription.current;
    activeTranscription.current = null;
    previousTranscription?.controller.abort();
    setError("");
    setStatus("validating");
    setTranscript("");
    setTranscriptSegments([]);
    setActiveTranscriptionId(null);
    setSummary("");
    setSummaryError("");
    const duration = await readAudioDuration(file);
    if (generation !== operationGeneration.current) return;
    const durationError = uploadDurationError(duration, isSignedInRef.current);
    if (durationError || duration === null) {
      setError(durationError ?? "");
      setStatus("error");
      return;
    }
    setAudio(file);
    elapsedRef.current = duration;
    setElapsed(duration);
    audioOperationId.current = crypto.randomUUID();
    await transcribe(file, duration, audioOperationId.current);
  }

  async function removeHistoryItem(id: string) {
    try {
      const token = await account.getConvexToken();
      await deleteTranscription(id, token);
      setHistory((items) => items.filter((item) => item._id !== id));
    } catch {
      setError("That history item could not be deleted.");
    }
  }

  async function removeAllHistory() {
    try {
      const token = await account.getConvexToken();
      await clearTranscriptions(token);
      setHistory([]);
      setHistoryCursor(null);
    } catch {
      setError("History could not be cleared.");
    }
  }

  async function copyTranscript() {
    await navigator.clipboard.writeText(transcript);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }

  async function summarizeText(value = transcript, transcriptionId = activeTranscriptionId) {
    if (!value.trim() || summaryLoading) return;
    setSummaryLoading(true);
    setSummaryError("");
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
      if (transcriptionId) {
        const token = await account.getConvexToken();
        await saveTranscriptionSummary(transcriptionId, generatedSummary, token);
        setHistory((items) => items.map((item) => item._id === transcriptionId ? { ...item, summary: generatedSummary } : item));
      }
    } catch {
      setSummaryError("Summarizing failed. Try again.");
    } finally {
      setSummaryLoading(false);
    }
  }

  const time = `${String(Math.floor(elapsed / 60)).padStart(2, "0")}:${String(elapsed % 60).padStart(2, "0")}`;
  function openHistoryItem(item: TranscriptionHistoryItem) {
    setTranscript(item.text);
    setTranscriptSegments(item.segments ?? []);
    setActiveTranscriptionId(item._id);
    setSummary(item.summary ?? "");
    setSummaryError("");
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
          <div><h2>{status === "starting" ? "Requesting microphone…" : status === "recording" ? "Recording" : status === "validating" ? "Checking audio…" : status === "transcribing" ? "Transcribing…" : "Ready to record"}</h2></div>
          <span className="privacy">Audio deleted after transcription</span>
        </div>

        <div className="wave" aria-hidden="true">
          {Array.from({ length: 42 }, (_, index) => <span key={index} style={{ height: `${12 + ((index * 17) % 54)}px`, "--i": index } as React.CSSProperties} />)}
        </div>

        <div className="record-controls">
          {status !== "recording" ? (
            <button className="record-button" onClick={startRecording} disabled={status === "starting" || status === "validating" || status === "transcribing"} aria-label="Start recording"><span /></button>
          ) : (
            <button className="record-button stop" onClick={stopRecording} aria-label="Stop recording"><span /></button>
          )}
          <div><strong>{status === "recording" ? time : status === "transcribing" ? "Uploading and transcribing…" : "Press to record"}</strong><small>{status === "recording" ? "Stop to upload and transcribe" : status === "transcribing" ? "The transcript will be saved to history" : "Microphone access stays in this tab"}</small></div>
        </div>
        <div className="audio-upload">
          <span>or</span>
          <button type="button" onClick={() => audioFileInput.current?.click()} disabled={status === "starting" || status === "recording" || status === "validating" || status === "transcribing"}>Upload audio file</button>
          <small>MP3, WAV, M4A, WebM and other browser-supported audio · 24 MB maximum · {account.isSignedIn ? "up to 2 hours" : "up to 10 minutes for guests"}</small>
          <input ref={audioFileInput} type="file" accept="audio/*" hidden onChange={(event) => {
            const file = event.target.files?.[0];
            if (file) void uploadAudio(file);
            event.target.value = "";
          }} />
        </div>

        {audio && status === "error" && (
          <button className="primary" onClick={() => transcribe(audio, elapsedRef.current, audioOperationId.current ?? crypto.randomUUID())}>
            Retry transcription
          </button>
        )}
        {error && <p className="error" role="alert">{error}</p>}
      </section>

      <section className="transcript-card">
        <div className="transcript-head"><div><small>TRANSCRIPT</small><span>{transcript ? `${transcript.split(/\s+/).length} words` : "Waiting for audio"}</span></div>{transcript && <div className="transcript-tools"><button className="summarize" onClick={() => void summarizeText()} disabled={summaryLoading}>{summaryLoading ? "Summarizing…" : "Summarize"}</button><button onClick={copyTranscript}>{copied ? "Copied" : "Copy"}</button><button onClick={() => downloadTranscript(transcript, "txt")}>TXT</button><button disabled={!transcriptSegments.length} title={transcriptSegments.length ? "Download timed subtitles" : "Timing is unavailable after editing"} onClick={() => downloadTranscript(transcript, "srt", transcriptSegments)}>SRT</button><button disabled={!transcriptSegments.length} title={transcriptSegments.length ? "Download timed subtitles" : "Timing is unavailable after editing"} onClick={() => downloadTranscript(transcript, "vtt", transcriptSegments)}>VTT</button></div>}</div>
        <textarea aria-label="Transcript text" value={transcript} onChange={(event) => { setTranscript(event.target.value); setTranscriptSegments([]); }} placeholder="Your transcription will appear here…" />
      </section>

      {transcript && <AIEnhancementPanel text={transcript} onApply={(value) => { setTranscript(value); setTranscriptSegments([]); setSummary(""); setSummaryError(""); }} onNarrate={setSpeechText} />}

      {(summary || summaryLoading || summaryError) && <section className="summary-card"><div className="summary-head"><div><small>SUMMARY</small><span>Llama 3.2</span></div>{summary && <div><button onClick={() => void navigator.clipboard.writeText(summary)}>Copy</button><button onClick={() => setSpeechText(summary)}>Narrate summary</button></div>}</div>{summaryLoading ? <p className="summary-loading">Summarizing…</p> : summary ? <textarea aria-label="AI-generated transcript summary" value={summary} onChange={(event) => setSummary(event.target.value)} /> : <p className="error" role="alert">{summaryError}</p>}<p className="ai-note">AI-generated summaries can make mistakes. Check important details against the transcript.</p></section>}

      <TTSWorkspace transcript={transcript} text={speechText} onTextChange={setSpeechText} />

      </> : <HistoryView history={history} loading={historyLoading} hasMore={historyCursor !== null} isSignedIn={account.isSignedIn} retentionDays={retentionDays} retentionSaving={retentionSaving} retentionStatus={retentionStatus} onRefresh={() => void refreshHistory()} onLoadMore={() => void loadMoreHistory()} onRetentionChange={(days) => void changeRetention(days)} onOpen={openHistoryItem} onNarrate={setSpeechText} onSummarize={(item) => { setTranscript(item.text); setTranscriptSegments(item.segments ?? []); setActiveTranscriptionId(item._id); void summarizeText(item.text, item._id); }} onDelete={(id) => void removeHistoryItem(id)} onDeleteAll={() => void removeAllHistory()} />}

      <footer><span>VoiceInk Web 2.11.0</span><span>Deepgram Nova-3 · Whisper large-v3 turbo</span></footer>
    </main>
  );
}
