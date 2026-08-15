"use client";

import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import {
  deleteTranscription,
  getRetention,
  listTranscriptions,
  saveTranscription,
  saveTranscriptionSummary,
  setRetention,
  type RetentionDays,
  type TranscriptionHistoryItem,
} from "../lib/convex";
import {
  getBrowserSpeechController,
  loadBrowserVoices,
  type BrowserVoice,
} from "../lib/browserSpeech";
import { downloadTranscript } from "../lib/transcriptExport";
import { AIEnhancementPanel } from "./ai-enhancement";
import { AccountControls, useAccountAuth } from "./providers";
import { HistoryView } from "./history-view";

type Status = "idle" | "recording" | "transcribing" | "done" | "error";
type Theme = "editorial" | "mac";
type WorkspaceTab = "studio" | "history";
const maximumRecordingSeconds = 30 * 60;
const maximumUploadSeconds = 2 * 60 * 60;

async function readAudioDuration(file: File) {
  const url = URL.createObjectURL(file);
  try {
    return await new Promise<number>((resolve) => {
      const audio = new Audio();
      audio.preload = "metadata";
      audio.onloadedmetadata = () => resolve(Number.isFinite(audio.duration) ? Math.round(audio.duration) : 0);
      audio.onerror = () => resolve(0);
      audio.src = url;
    });
  } finally {
    URL.revokeObjectURL(url);
  }
}

export default function Home() {
  const account = useAccountAuth();
  const recorder = useRef<MediaRecorder | null>(null);
  const chunks = useRef<Blob[]>([]);
  const ticker = useRef<ReturnType<typeof setInterval> | null>(null);
  const audioFileInput = useRef<HTMLInputElement | null>(null);
  const elapsedRef = useRef(0);
  const [status, setStatus] = useState<Status>("idle");
  const [elapsed, setElapsed] = useState(0);
  const [audio, setAudio] = useState<Blob | null>(null);
  const [transcript, setTranscript] = useState("");
  const [transcriptDuration, setTranscriptDuration] = useState(0);
  const [activeTranscriptionId, setActiveTranscriptionId] = useState<string | null>(null);
  const [summary, setSummary] = useState("");
  const [summaryLoading, setSummaryLoading] = useState(false);
  const [summaryError, setSummaryError] = useState("");
  const [error, setError] = useState("");
  const [copied, setCopied] = useState(false);
  const [history, setHistory] = useState<TranscriptionHistoryItem[]>([]);
  const [historyLoading, setHistoryLoading] = useState(true);
  const [voices, setVoices] = useState<BrowserVoice[]>([]);
  const [voiceId, setVoiceId] = useState("");
  const [speechRate, setSpeechRate] = useState(1);
  const [speechPitch, setSpeechPitch] = useState(1);
  const [speechVolume, setSpeechVolume] = useState(0.8);
  const [playback, setPlayback] = useState<"idle" | "playing" | "paused">("idle");
  const [speechError, setSpeechError] = useState("");
  const [speechText, setSpeechText] = useState("");
  const [importUrl, setImportUrl] = useState("");
  const [importStatus, setImportStatus] = useState("");
  const [isImporting, setIsImporting] = useState(false);
  const [theme, setTheme] = useState<Theme>("editorial");
  const [activeTab, setActiveTab] = useState<WorkspaceTab>("studio");
  const [retentionDays, setRetentionDays] = useState<RetentionDays>(90);
  const [retentionSaving, setRetentionSaving] = useState(false);
  const [retentionStatus, setRetentionStatus] = useState("");

  const refreshHistory = useCallback(async () => {
    try {
      const token = await account.getConvexToken();
      setHistory(await listTranscriptions(token));
    } finally {
      setHistoryLoading(false);
    }
  }, [account]);

  const refreshRetention = useCallback(async () => {
    if (!account.isSignedIn) return;
    const token = await account.getConvexToken();
    const days = await getRetention(token);
    if (days !== null) setRetentionDays(days);
  }, [account]);

  useEffect(() => {
    let themeUpdate: number | undefined;
    const savedTheme = window.localStorage.getItem("voiceink-theme");
    if (savedTheme === "mac" || savedTheme === "editorial") {
      themeUpdate = window.setTimeout(() => setTheme(savedTheme), 0);
      document.documentElement.dataset.theme = savedTheme;
    }
    void loadBrowserVoices().then((available) => {
      setVoices(available);
      setVoiceId(available.find((voice) => voice.isDefault)?.id ?? available[0]?.id ?? "");
    });
    return () => {
      if (themeUpdate !== undefined) window.clearTimeout(themeUpdate);
      if (ticker.current) clearInterval(ticker.current);
      recorder.current?.stream.getTracks().forEach((track) => track.stop());
      if ("speechSynthesis" in window) window.speechSynthesis.cancel();
    };
  }, []);

  useEffect(() => {
    if (account.isLoaded) {
      queueMicrotask(() => {
        void refreshHistory();
        void refreshRetention();
      });
    }
  }, [account.identityKey, account.isLoaded, refreshHistory, refreshRetention]);

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
    try {
      setError("");
      setTranscript("");
      setActiveTranscriptionId(null);
      setSummary("");
      setAudio(null);
      setElapsed(0);
      elapsedRef.current = 0;
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const nextRecorder = new MediaRecorder(stream);
      chunks.current = [];
      nextRecorder.ondataavailable = (event) => {
        if (event.data.size) chunks.current.push(event.data);
      };
      nextRecorder.onstop = () => {
        const recording = new Blob(chunks.current, { type: nextRecorder.mimeType });
        setAudio(recording);
        stream.getTracks().forEach((track) => track.stop());
        void transcribe(recording, elapsedRef.current);
      };
      nextRecorder.start(250);
      recorder.current = nextRecorder;
      setStatus("recording");
      ticker.current = setInterval(() => {
        elapsedRef.current += 1;
        setElapsed(elapsedRef.current);
        if (elapsedRef.current >= maximumRecordingSeconds) {
          if (ticker.current) clearInterval(ticker.current);
          ticker.current = null;
          recorder.current?.stop();
        }
      }, 1000);
    } catch {
      setError("Microphone access is required to record a transcription.");
      setStatus("error");
    }
  }

  function stopRecording() {
    if (ticker.current) clearInterval(ticker.current);
    ticker.current = null;
    recorder.current?.stop();
  }

  async function transcribe(recording: Blob, durationSeconds: number) {
    setStatus("transcribing");
    setError("");
    try {
      const form = new FormData();
      form.append("audio", recording, "recording.webm");
      form.append("model", "whisper-large-v3-turbo");
      const response = await fetch("/api/transcribe", { method: "POST", body: form });
      if (!response.ok) throw new Error("Transcription failed");
      const result = (await response.json()) as { text: string };
      const transcribedText = result.text?.trim();
      if (!transcribedText) throw new Error("No speech was detected");
      setTranscript(transcribedText);
      setTranscriptDuration(durationSeconds);
      setStatus("done");
      try {
        const token = await account.getConvexToken();
        const savedId = await saveTranscription({
          text: transcribedText,
          durationSeconds,
          model: "whisper-large-v3-turbo",
        }, token);
        setActiveTranscriptionId(savedId ?? null);
        await refreshHistory();
      } catch {
        setError("The transcript is ready, but it could not be saved to history. Check your quota or retention settings.");
      }
    } catch {
      setError("The transcription service could not be reached. Your recording is still available to retry.");
      setStatus("error");
    }
  }

  async function uploadAudio(file: File) {
    if (file.size > 24 * 1024 * 1024) {
      setError("Audio files must be smaller than 24 MB.");
      return;
    }
    setError("");
    setTranscript("");
    setActiveTranscriptionId(null);
    setSummary("");
    setSummaryError("");
    const duration = await readAudioDuration(file);
    if (duration > maximumUploadSeconds) {
      setError("Audio files must be two hours or shorter.");
      return;
    }
    setAudio(file);
    elapsedRef.current = duration;
    setElapsed(duration);
    await transcribe(file, duration);
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
      setSummaryError("The AI summary could not be generated. Please try again.");
    } finally {
      setSummaryLoading(false);
    }
  }

  async function playSpeechText() {
    if (!speechText.trim()) return;
    setSpeechError("");
    setPlayback("playing");
    try {
      await getBrowserSpeechController().speak({
        text: speechText,
        voiceId,
        rate: speechRate,
        pitch: speechPitch,
        volume: speechVolume,
      });
      setPlayback("idle");
    } catch (speechFailure) {
      const message = speechFailure instanceof Error ? speechFailure.message : "Speech playback failed";
      if (message !== "canceled" && message !== "interrupted") setSpeechError(message);
      setPlayback("idle");
    }
  }

  function pauseSpeech() {
    getBrowserSpeechController().pause();
    setPlayback("paused");
  }

  function resumeSpeech() {
    getBrowserSpeechController().resume();
    setPlayback("playing");
  }

  function stopSpeech() {
    getBrowserSpeechController().cancel();
    setPlayback("idle");
  }

  async function importContent(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!importUrl.trim()) return;
    setIsImporting(true);
    setImportStatus("Fetching readable content…");
    try {
      const response = await fetch("/api/import", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ url: importUrl.trim() }),
      });
      const result = await response.json() as { title?: string; content?: string; error?: string };
      if (!response.ok || !result.content) throw new Error(result.error ?? "No readable content was found.");
      stopSpeech();
      setSpeechText(result.content);
      setImportStatus(`${result.title ?? "Article"} loaded into the text-to-speech editor.`);
      setImportUrl("");
    } catch (importError) {
      setImportStatus(importError instanceof Error ? importError.message : "The page could not be imported.");
    } finally {
      setIsImporting(false);
    }
  }

  const time = `${String(Math.floor(elapsed / 60)).padStart(2, "0")}:${String(elapsed % 60).padStart(2, "0")}`;
  function openHistoryItem(item: TranscriptionHistoryItem) {
    setTranscript(item.text);
    setTranscriptDuration(item.durationSeconds);
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
          <div className="model-pill"><span /> Whisper V3 Turbo <b>multilingual</b></div>
        </div>
      </header>

      {activeTab === "studio" ? <>
      <section className="hero">
        <div className="eyebrow"><i /> PRIVATE-BY-DESIGN TRANSCRIPTION</div>
        <h1>Your voice, <span>made clear.</span></h1>
        <p>Fast, focused transcription powered by Cloudflare Workers AI. Record in your browser and keep control of what happens next.</p>
      </section>

      <section className={`recorder-card ${status === "recording" ? "is-recording" : ""}`}>
        <div className="card-header">
          <div><small>TRANSCRIPTION STUDIO</small><h2>{status === "recording" ? "Listening…" : status === "transcribing" ? "Creating your transcript…" : "Ready when you are"}</h2></div>
          <span className="privacy"><i /> Audio deleted after transcription</span>
        </div>

        <div className="wave" aria-hidden="true">
          {Array.from({ length: 42 }, (_, index) => <span key={index} style={{ height: `${12 + ((index * 17) % 54)}px` }} />)}
        </div>

        <div className="record-controls">
          {status !== "recording" ? (
            <button className="record-button" onClick={startRecording} disabled={status === "transcribing"} aria-label="Start recording"><span /></button>
          ) : (
            <button className="record-button stop" onClick={stopRecording} aria-label="Stop recording"><span /></button>
          )}
          <div><strong>{status === "recording" ? time : status === "transcribing" ? "Uploading automatically…" : "Press to record"}</strong><small>{status === "recording" ? "Stop to upload and transcribe" : status === "transcribing" ? "The transcript will be saved to history" : "Microphone access stays in this tab"}</small></div>
        </div>
        <div className="audio-upload">
          <span>or</span>
          <button type="button" onClick={() => audioFileInput.current?.click()} disabled={status === "recording" || status === "transcribing"}>Upload audio file</button>
          <small>MP3, WAV, M4A, WebM and other browser-supported audio · 24 MB maximum</small>
          <input ref={audioFileInput} type="file" accept="audio/*" hidden onChange={(event) => {
            const file = event.target.files?.[0];
            if (file) void uploadAudio(file);
            event.target.value = "";
          }} />
        </div>

        {audio && status === "error" && (
          <button className="primary" onClick={() => transcribe(audio, elapsedRef.current)}>
            Retry transcription
          </button>
        )}
        {error && <p className="error" role="alert">{error}</p>}
      </section>

      <section className="transcript-card">
        <div className="transcript-head"><div><small>TRANSCRIPT</small><span>{transcript ? `${transcript.split(/\s+/).length} words` : "Waiting for audio"}</span></div>{transcript && <div className="transcript-tools"><button className="summarize" onClick={() => void summarizeText()} disabled={summaryLoading}>{summaryLoading ? "Summarizing…" : "AI summary"}</button><button onClick={copyTranscript}>{copied ? "Copied" : "Copy"}</button><button onClick={() => downloadTranscript(transcript, "txt")}>TXT</button><button onClick={() => downloadTranscript(transcript, "srt", transcriptDuration * 1000)}>SRT</button><button onClick={() => downloadTranscript(transcript, "vtt", transcriptDuration * 1000)}>VTT</button></div>}</div>
        <textarea aria-label="Transcript text" value={transcript} onChange={(event) => setTranscript(event.target.value)} placeholder="Your transcription will appear here…" />
      </section>

      {transcript && <AIEnhancementPanel text={transcript} onApply={(value) => { setTranscript(value); setSummary(""); setSummaryError(""); }} onNarrate={setSpeechText} />}

      {(summary || summaryLoading || summaryError) && <section className="summary-card"><div className="summary-head"><div><small>AI SUMMARY</small><span>Cloudflare Workers AI · Llama 3.2</span></div>{summary && <div><button onClick={() => void navigator.clipboard.writeText(summary)}>Copy</button><button onClick={() => setSpeechText(summary)}>Narrate summary</button></div>}</div>{summaryLoading ? <p className="summary-loading">Finding the key points…</p> : summary ? <textarea aria-label="AI-generated transcript summary" value={summary} onChange={(event) => setSummary(event.target.value)} /> : <p className="error" role="alert">{summaryError}</p>}<p className="ai-note">AI-generated summaries can make mistakes. Check important details against the transcript.</p></section>}

      <section className="tts-card">
        <div className="tts-head">
          <div><small>TEXT TO SPEECH</small><span>{speechText ? `${speechText.length.toLocaleString()} characters` : "Paste or type anything to read aloud"}</span></div>
          <div className="tts-tools">
            {transcript && <button onClick={() => setSpeechText(transcript)}>Use transcript</button>}
            <span className="local-pill">No API key</span>
          </div>
        </div>
        <form className="import-content" onSubmit={importContent}>
          <label htmlFor="import-url">Import content from a webpage</label>
          <div>
            <input id="import-url" type="url" value={importUrl} onChange={(event) => setImportUrl(event.target.value)} placeholder="https://example.com/article" required />
            <button type="submit" disabled={isImporting}>{isImporting ? "Importing…" : "Import article"}</button>
          </div>
          {importStatus && <p role="status">{importStatus}</p>}
        </form>
        <textarea className="tts-text-editor" aria-label="Text to read aloud" value={speechText} onChange={(event) => setSpeechText(event.target.value)} placeholder="Paste or type text here. This editor is separate from your transcription…" />
        <div className="tts-grid">
          <label className="voice-field">
            <span>Voice</span>
            <select value={voiceId} onChange={(event) => setVoiceId(event.target.value)} disabled={!voices.length}>
              {!voices.length && <option>Loading system voices…</option>}
              {voices.map((voice) => <option key={voice.id} value={voice.id}>{voice.name} · {voice.language}{voice.isLocal ? " · local" : ""}</option>)}
            </select>
          </label>
          <label><span>Speed <b>{speechRate.toFixed(1)}×</b></span><input type="range" min="0.5" max="2" step="0.1" value={speechRate} onChange={(event) => setSpeechRate(Number(event.target.value))} /></label>
          <label><span>Pitch <b>{speechPitch.toFixed(1)}</b></span><input type="range" min="0.5" max="2" step="0.1" value={speechPitch} onChange={(event) => setSpeechPitch(Number(event.target.value))} /></label>
          <label><span>Volume <b>{Math.round(speechVolume * 100)}%</b></span><input type="range" min="0" max="1" step="0.05" value={speechVolume} onChange={(event) => setSpeechVolume(Number(event.target.value))} /></label>
        </div>
        <div className="playback-buttons">
          {playback === "idle" && <button className="play" onClick={playSpeechText} disabled={!speechText.trim() || !voices.length}>▶ Read text</button>}
          {playback === "playing" && <button onClick={pauseSpeech}>Ⅱ Pause</button>}
          {playback === "paused" && <button className="play" onClick={resumeSpeech}>▶ Resume</button>}
          {playback !== "idle" && <button onClick={stopSpeech}>■ Stop</button>}
        </div>
        {speechError && <p className="error" role="alert">{speechError}</p>}
      </section>

      </> : <HistoryView history={history} loading={historyLoading} isSignedIn={account.isSignedIn} retentionDays={retentionDays} retentionSaving={retentionSaving} retentionStatus={retentionStatus} onRefresh={() => void refreshHistory()} onRetentionChange={(days) => void changeRetention(days)} onOpen={openHistoryItem} onNarrate={setSpeechText} onSummarize={(item) => { setTranscript(item.text); setTranscriptDuration(item.durationSeconds); setActiveTranscriptionId(item._id); void summarizeText(item.text, item._id); }} onDelete={(id) => void removeHistoryItem(id)} />}

      <footer><span>VoiceInk Web 2.11.0</span><span>Cloudflare edge</span><span>Convex realtime data</span><span>Whisper V3 Turbo</span></footer>
    </main>
  );
}
