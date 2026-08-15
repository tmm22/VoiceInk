import type { TranscriptionSegment } from "../shared/transcriptionContract";

function timestamp(seconds: number, separator: "," | ".") {
  const value = Math.max(0, Math.round(seconds * 1_000));
  const hours = Math.floor(value / 3_600_000);
  const minutes = Math.floor((value % 3_600_000) / 60_000);
  const wholeSeconds = Math.floor((value % 60_000) / 1_000);
  const milliseconds = value % 1_000;
  return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(wholeSeconds).padStart(2, "0")}${separator}${String(milliseconds).padStart(3, "0")}`;
}

export function buildSrt(segments: TranscriptionSegment[]) {
  return segments.map((segment, index) => [
    index + 1,
    `${timestamp(segment.start, ",")} --> ${timestamp(segment.end, ",")}`,
    segment.text,
  ].join("\n")).join("\n\n");
}

export function buildVtt(segments: TranscriptionSegment[]) {
  const body = segments.map((segment) =>
    `${timestamp(segment.start, ".")} --> ${timestamp(segment.end, ".")}\n${segment.text}`,
  ).join("\n\n");
  return `WEBVTT\n\n${body}`.trim();
}

export function downloadTranscript(text: string, extension: "txt" | "srt" | "vtt", segments?: TranscriptionSegment[]) {
  const content = extension === "srt" ? buildSrt(segments ?? []) : extension === "vtt" ? buildVtt(segments ?? []) : text;
  const type = extension === "vtt" ? "text/vtt;charset=utf-8" : "text/plain;charset=utf-8";
  const url = URL.createObjectURL(new Blob([content], { type }));
  const link = document.createElement("a");
  link.href = url;
  link.download = `voiceink-${new Date().toISOString().replace(/[:.]/g, "-")}.${extension}`;
  link.click();
  URL.revokeObjectURL(url);
}
