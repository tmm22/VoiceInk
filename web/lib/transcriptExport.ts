type Cue = { index: number; startMs: number; endMs: number; text: string };

function cues(text: string, durationMs?: number): Cue[] {
  const sentences = (text.match(/[^.!?\n]+[.!?]?/g) ?? [])
    .map((sentence) => sentence.trim())
    .filter(Boolean);
  if (!sentences.length) return [];
  const totalMs = durationMs && durationMs > 0 ? durationMs : sentences.length * 4_000;
  const slice = totalMs / sentences.length;
  return sentences.map((sentence, index) => ({
    index: index + 1,
    startMs: Math.round(index * slice),
    endMs: index === sentences.length - 1 ? totalMs : Math.round((index + 1) * slice),
    text: sentence,
  }));
}

function timestamp(milliseconds: number, separator: "," | ".") {
  const value = Math.max(0, Math.round(milliseconds));
  const hours = Math.floor(value / 3_600_000);
  const minutes = Math.floor((value % 3_600_000) / 60_000);
  const seconds = Math.floor((value % 60_000) / 1_000);
  const ms = value % 1_000;
  return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}${separator}${String(ms).padStart(3, "0")}`;
}

export function buildSrt(text: string, durationMs?: number) {
  return cues(text, durationMs).map((cue) => [
    cue.index,
    `${timestamp(cue.startMs, ",")} --> ${timestamp(cue.endMs, ",")}`,
    cue.text,
  ].join("\n")).join("\n\n");
}

export function buildVtt(text: string, durationMs?: number) {
  const body = cues(text, durationMs).map((cue) =>
    `${timestamp(cue.startMs, ".")} --> ${timestamp(cue.endMs, ".")}\n${cue.text}`,
  ).join("\n\n");
  return `WEBVTT\n\n${body}`.trim();
}

export function downloadTranscript(text: string, extension: "txt" | "srt" | "vtt", durationMs?: number) {
  const content = extension === "srt" ? buildSrt(text, durationMs) : extension === "vtt" ? buildVtt(text, durationMs) : text;
  const type = extension === "vtt" ? "text/vtt;charset=utf-8" : "text/plain;charset=utf-8";
  const url = URL.createObjectURL(new Blob([content], { type }));
  const link = document.createElement("a");
  link.href = url;
  link.download = `voiceink-${new Date().toISOString().replace(/[:.]/g, "-")}.${extension}`;
  link.click();
  URL.revokeObjectURL(url);
}
