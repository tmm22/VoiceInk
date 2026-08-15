"use client";

import { useEffect, useState, type FormEvent } from "react";
import { getBrowserSpeechController, loadBrowserVoices, type BrowserVoice } from "../lib/browserSpeech";

type Props = {
  transcript: string;
  text: string;
  onTextChange: (value: string) => void;
};

export function TTSWorkspace({ transcript, text, onTextChange }: Props) {
  const [voices, setVoices] = useState<BrowserVoice[]>([]);
  const [voiceId, setVoiceId] = useState("");
  const [speechRate, setSpeechRate] = useState(1);
  const [speechPitch, setSpeechPitch] = useState(1);
  const [speechVolume, setSpeechVolume] = useState(0.8);
  const [playback, setPlayback] = useState<"idle" | "playing" | "paused">("idle");
  const [speechError, setSpeechError] = useState("");
  const [importUrl, setImportUrl] = useState("");
  const [importStatus, setImportStatus] = useState("");
  const [isImporting, setIsImporting] = useState(false);

  useEffect(() => {
    void loadBrowserVoices().then((available) => {
      setVoices(available);
      setVoiceId(available.find((voice) => voice.isDefault)?.id ?? available[0]?.id ?? "");
    });
    return () => { if ("speechSynthesis" in window) window.speechSynthesis.cancel(); };
  }, []);

  async function play() {
    if (!text.trim()) return;
    setSpeechError("");
    setPlayback("playing");
    try {
      await getBrowserSpeechController().speak({ text, voiceId, rate: speechRate, pitch: speechPitch, volume: speechVolume });
      setPlayback("idle");
    } catch (failure) {
      const message = failure instanceof Error ? failure.message : "Speech playback failed";
      if (message !== "canceled" && message !== "interrupted") setSpeechError(message);
      setPlayback("idle");
    }
  }

  function stop() {
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
        cache: "no-store",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ url: importUrl.trim() }),
      });
      const result = await response.json() as { title?: string; content?: string; error?: string };
      if (!response.ok || !result.content) throw new Error(result.error ?? "No readable content was found.");
      stop();
      onTextChange(result.content);
      setImportStatus(`${result.title ?? "Article"} loaded into the text-to-speech editor.`);
      setImportUrl("");
    } catch (error) {
      setImportStatus(error instanceof Error ? error.message : "The page could not be imported.");
    } finally {
      setIsImporting(false);
    }
  }

  return (
    <section className="tts-card">
      <div className="tts-head">
        <div><small>TEXT TO SPEECH</small><span>{text ? `${text.length.toLocaleString()} characters` : "Paste or type anything to read aloud"}</span></div>
        <div className="tts-tools">{transcript && <button onClick={() => onTextChange(transcript)}>Use transcript</button>}<span className="local-pill">On-device voices</span></div>
      </div>
      <form className="import-content" onSubmit={importContent}>
        <label htmlFor="import-url">Import content from a webpage</label>
        <div><input id="import-url" type="url" value={importUrl} onChange={(event) => setImportUrl(event.target.value)} placeholder="https://example.com/article" required /><button type="submit" disabled={isImporting}>{isImporting ? "Importing…" : "Import article"}</button></div>
        {importStatus && <p role="status">{importStatus}</p>}
      </form>
      <textarea className="tts-text-editor" aria-label="Text to read aloud" value={text} onChange={(event) => onTextChange(event.target.value)} placeholder="Paste or type text here. This editor is separate from your transcription…" />
      <div className="tts-grid">
        <label className="voice-field"><span>Voice</span><select value={voiceId} onChange={(event) => setVoiceId(event.target.value)} disabled={!voices.length}>{!voices.length && <option>Loading system voices…</option>}{voices.map((voice) => <option key={voice.id} value={voice.id}>{voice.name} · {voice.language}{voice.isLocal ? " · local" : ""}</option>)}</select></label>
        <label><span>Speed <b>{speechRate.toFixed(1)}×</b></span><input type="range" min="0.5" max="2" step="0.1" value={speechRate} onChange={(event) => setSpeechRate(Number(event.target.value))} /></label>
        <label><span>Pitch <b>{speechPitch.toFixed(1)}</b></span><input type="range" min="0.5" max="2" step="0.1" value={speechPitch} onChange={(event) => setSpeechPitch(Number(event.target.value))} /></label>
        <label><span>Volume <b>{Math.round(speechVolume * 100)}%</b></span><input type="range" min="0" max="1" step="0.05" value={speechVolume} onChange={(event) => setSpeechVolume(Number(event.target.value))} /></label>
      </div>
      <div className="playback-buttons">
        {playback === "idle" && <button className="play" onClick={() => void play()} disabled={!text.trim() || !voices.length}>Play</button>}
        {playback === "playing" && <button onClick={() => { getBrowserSpeechController().pause(); setPlayback("paused"); }}>Pause</button>}
        {playback === "paused" && <button className="play" onClick={() => { getBrowserSpeechController().resume(); setPlayback("playing"); }}>Resume</button>}
        {playback !== "idle" && <button onClick={stop}>Stop</button>}
      </div>
      {speechError && <p className="error" role="alert">{speechError}</p>}
    </section>
  );
}
