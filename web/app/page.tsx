"use client";

import { useEffect, useRef, useState } from "react";
import {
  listTranscriptions,
  saveTranscription,
  type TranscriptionHistoryItem,
} from "../lib/convex";
import {
  getBrowserSpeechController,
  loadBrowserVoices,
  type BrowserVoice,
} from "../lib/browserSpeech";
import { AccountControls, useAccountAuth } from "./providers";

type Status = "idle" | "recording" | "transcribing" | "done" | "error";
type Theme = "editorial" | "mac";

const demoTranscript =
  "VoiceInk Web keeps the recording workflow focused: capture your voice, transcribe it with Parakeet, then copy or refine the result.";

export default function Home() {
  const account = useAccountAuth();
  const recorder = useRef<MediaRecorder | null>(null);
  const chunks = useRef<Blob[]>([]);
  const ticker = useRef<ReturnType<typeof setInterval> | null>(null);
  const elapsedRef = useRef(0);
  const [status, setStatus] = useState<Status>("idle");
  const [elapsed, setElapsed] = useState(0);
  const [audio, setAudio] = useState<Blob | null>(null);
  const [transcript, setTranscript] = useState("");
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
  const [theme, setTheme] = useState<Theme>("editorial");

  useEffect(() => {
    const savedTheme = window.localStorage.getItem("voiceink-theme");
    if (savedTheme === "mac" || savedTheme === "editorial") {
      setTheme(savedTheme);
      document.documentElement.dataset.theme = savedTheme;
    }
    void refreshHistory();
    void loadBrowserVoices().then((available) => {
      setVoices(available);
      setVoiceId(available.find((voice) => voice.isDefault)?.id ?? available[0]?.id ?? "");
    });
    return () => {
      if (ticker.current) clearInterval(ticker.current);
      recorder.current?.stream.getTracks().forEach((track) => track.stop());
      if ("speechSynthesis" in window) window.speechSynthesis.cancel();
    };
  }, []);

  useEffect(() => {
    if (account.isLoaded) void refreshHistory();
  }, [account.identityKey, account.isLoaded]);

  function selectTheme(nextTheme: Theme) {
    setTheme(nextTheme);
    document.documentElement.dataset.theme = nextTheme;
    window.localStorage.setItem("voiceink-theme", nextTheme);
  }

  async function refreshHistory() {
    try {
      const token = await account.getConvexToken();
      setHistory(await listTranscriptions(token));
    } finally {
      setHistoryLoading(false);
    }
  }

  async function startRecording() {
    try {
      setError("");
      setTranscript("");
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
      setTranscript(result.text || demoTranscript);
      const token = await account.getConvexToken();
      await saveTranscription({
        text: result.text || demoTranscript,
        durationSeconds,
        model: "whisper-large-v3-turbo",
      }, token);
      await refreshHistory();
      setStatus("done");
    } catch {
      setError("The transcription service could not be reached. Your recording is still available to retry.");
      setStatus("error");
    }
  }

  async function copyTranscript() {
    await navigator.clipboard.writeText(transcript);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
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

  const time = `${String(Math.floor(elapsed / 60)).padStart(2, "0")}:${String(elapsed % 60).padStart(2, "0")}`;

  return (
    <main>
      <header className="topbar">
        <a className="brand" href="#" aria-label="VoiceInk Web home">
          <span className="brand-mark">V</span><span>VoiceInk <em>web</em></span>
        </a>
        <div className="header-actions">
          <AccountControls />
          <div className="theme-switch" aria-label="Appearance" role="group">
            <button className={theme === "editorial" ? "active" : ""} onClick={() => selectTheme("editorial")} aria-pressed={theme === "editorial"}>Original</button>
            <button className={theme === "mac" ? "active" : ""} onClick={() => selectTheme("mac")} aria-pressed={theme === "mac"}>Mac</button>
          </div>
          <div className="model-pill"><span /> Whisper V3 Turbo <b>multilingual</b></div>
        </div>
      </header>

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

        {audio && status === "error" && (
          <button className="primary" onClick={() => transcribe(audio, elapsedRef.current)}>
            Retry transcription
          </button>
        )}
        {error && <p className="error" role="alert">{error}</p>}
      </section>

      <section className="transcript-card">
        <div className="transcript-head"><div><small>TRANSCRIPT</small><span>{transcript ? `${transcript.split(/\s+/).length} words` : "Waiting for audio"}</span></div>{transcript && <button onClick={copyTranscript}>{copied ? "Copied" : "Copy text"}</button>}</div>
        <textarea aria-label="Transcript text" value={transcript} onChange={(event) => setTranscript(event.target.value)} placeholder="Your transcription will appear here…" />
      </section>

      <section className="tts-card">
        <div className="tts-head">
          <div><small>TEXT TO SPEECH</small><span>{speechText ? `${speechText.length.toLocaleString()} characters` : "Paste or type anything to read aloud"}</span></div>
          <div className="tts-tools">
            {transcript && <button onClick={() => setSpeechText(transcript)}>Use transcript</button>}
            <span className="local-pill">No API key</span>
          </div>
        </div>
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

      <section className="history-card">
        <div className="history-head">
          <div><small>RECENT HISTORY</small><span>{account.isSignedIn ? "Synced to your account across devices" : "Anonymous history expires after one hour"}</span></div>
          <button onClick={refreshHistory} disabled={historyLoading}>{historyLoading ? "Loading…" : "Refresh"}</button>
        </div>
        {history.length ? (
          <div className="history-list">
            {history.map((item) => (
              <button className="history-item" key={item._id} onClick={() => setTranscript(item.text)}>
                <span>{item.text}</span>
                <small>{new Date(item.createdAt).toLocaleString()} · {item.durationSeconds}s</small>
              </button>
            ))}
          </div>
        ) : (
          <p className="history-empty">Your completed recordings will appear here automatically.</p>
        )}
      </section>

      <footer><span>Cloudflare edge</span><span>Convex realtime data</span><span>Whisper V3 Turbo</span></footer>
    </main>
  );
}
