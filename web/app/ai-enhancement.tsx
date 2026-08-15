"use client";

import { useState } from "react";

type EnhancementMode = "clean" | "concise" | "professional" | "notes";

const enhancementModes: Array<{ id: EnhancementMode; title: string; description: string }> = [
  { id: "clean", title: "Clean up", description: "Fix grammar, punctuation, and filler words" },
  { id: "concise", title: "Concise", description: "Tighten repetition while preserving every fact" },
  { id: "professional", title: "Professional", description: "Polish the tone for work and client communication" },
  { id: "notes", title: "Structured notes", description: "Organize key points, decisions, and action items" },
];

type Props = {
  text: string;
  onApply: (value: string) => void;
  onNarrate: (value: string) => void;
};

export function AIEnhancementPanel({ text, onApply, onNarrate }: Props) {
  const [mode, setMode] = useState<EnhancementMode>("clean");
  const [enhancedText, setEnhancedText] = useState("");
  const [sourceText, setSourceText] = useState("");
  const [isEnhancing, setIsEnhancing] = useState(false);
  const [error, setError] = useState("");
  const [copied, setCopied] = useState(false);

  async function enhance() {
    if (!text.trim() || isEnhancing) return;
    setIsEnhancing(true);
    setError("");
    setEnhancedText("");
    try {
      const response = await fetch("/api/enhance", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ text, mode }),
      });
      const result = await response.json() as { enhanced?: string; error?: string };
      if (!response.ok || !result.enhanced) throw new Error(result.error ?? "Enhancement failed");
      setEnhancedText(result.enhanced);
      setSourceText(text);
    } catch {
      setError("The text could not be enhanced. Your original transcript is unchanged.");
    } finally {
      setIsEnhancing(false);
    }
  }

  async function copyEnhancedText() {
    await navigator.clipboard.writeText(enhancedText);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1_500);
  }

  const sourceHasChanged = Boolean(enhancedText) && sourceText !== text;

  return (
    <section className="ai-enhancement-card">
      <div className="enhancement-head">
        <div><small>AI TEXT ENHANCEMENT</small><span>Cloudflare Workers AI · Llama 3.2</span></div>
        <span className="cloud-pill">Runs on request</span>
      </div>
      <div className="enhancement-controls">
        <div className="enhancement-mode-grid" role="radiogroup" aria-label="Enhancement style">
          {enhancementModes.map((item) => (
            <button
              key={item.id}
              type="button"
              role="radio"
              aria-checked={mode === item.id}
              className={mode === item.id ? "active" : ""}
              onClick={() => setMode(item.id)}
            >
              <strong>{item.title}</strong>
              <span>{item.description}</span>
            </button>
          ))}
        </div>
        <button className="enhance-button" type="button" onClick={() => void enhance()} disabled={isEnhancing || !text.trim()}>
          {isEnhancing ? "Enhancing…" : "Enhance transcript"}
        </button>
      </div>
      {enhancedText && (
        <div className="enhancement-result">
          <div className="enhancement-result-head">
            <span>Enhanced result</span>
            <div>
              <button type="button" onClick={() => void copyEnhancedText()}>{copied ? "Copied" : "Copy"}</button>
              <button type="button" onClick={() => onNarrate(enhancedText)}>Narrate</button>
              <button className="apply" type="button" onClick={() => onApply(enhancedText)} disabled={sourceHasChanged}>Replace transcript</button>
            </div>
          </div>
          <textarea aria-label="AI-enhanced transcript" value={enhancedText} onChange={(event) => setEnhancedText(event.target.value)} />
          {sourceHasChanged && <p className="enhancement-stale" role="status">The transcript changed after this result was generated. Enhance it again before replacing the transcript.</p>}
        </div>
      )}
      {error && <p className="error" role="alert">{error}</p>}
      <p className="ai-note">Your original stays untouched until you choose Replace transcript. AI output can make mistakes, so check important details.</p>
    </section>
  );
}
