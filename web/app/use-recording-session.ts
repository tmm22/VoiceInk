"use client";

import { useEffect, useRef, useState } from "react";
import { elapsedRecordingSeconds, selectRecorderMimeType } from "../lib/recording";
import { MAXIMUM_AUDIO_BYTES } from "../shared/transcriptionContract";

export type RecordingOutcome =
  | { kind: "recorded"; recording: Blob; durationSeconds: number }
  | { kind: "too-large" }
  | { kind: "failed" };

export type RecordingHandlers = {
  // False once a newer operation superseded this recording; its events are ignored.
  isCurrent: () => boolean;
  onRecording: () => void;
  // The duration limit stopped the recorder; the outcome follows.
  onStopping: () => void;
  onEncoderError: () => void;
  onFinished: (outcome: RecordingOutcome) => void;
};

// Owns the microphone stream, MediaRecorder, and elapsed-time ticker for one
// recording at a time. Chunks stay in memory and are bounded by
// MAXIMUM_AUDIO_BYTES; the recorder stops itself at the size or time limit.
export function useRecordingSession(limitSeconds: () => number) {
  const recorder = useRef<MediaRecorder | null>(null);
  const chunks = useRef<Blob[]>([]);
  const ticker = useRef<ReturnType<typeof setInterval> | null>(null);
  const elapsedRef = useRef(0);
  const recordingStartedAt = useRef(0);
  const recordedBytes = useRef(0);
  const recordingTooLarge = useRef(false);
  const recordingFailed = useRef(false);
  const [elapsed, setElapsed] = useState(0);

  useEffect(() => () => {
    if (ticker.current) clearInterval(ticker.current);
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
  }, []);

  function clearTicker() {
    if (ticker.current) clearInterval(ticker.current);
    ticker.current = null;
  }

  function setElapsedSeconds(seconds: number) {
    elapsedRef.current = seconds;
    setElapsed(seconds);
  }

  // Throws when the microphone or encoder is unavailable; the caller reports it.
  async function begin(handlers: RecordingHandlers) {
    setElapsedSeconds(0);
    let stream: MediaStream | undefined;
    try {
      const acquiredStream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true } });
      stream = acquiredStream;
      if (!handlers.isCurrent()) {
        acquiredStream.getTracks().forEach((track) => track.stop());
        return;
      }
      const mimeType = selectRecorderMimeType((value) => MediaRecorder.isTypeSupported(value));
      const nextRecorder = new MediaRecorder(acquiredStream, { ...(mimeType ? { mimeType } : {}), audioBitsPerSecond: 64_000 });
      chunks.current = [];
      recordedBytes.current = 0;
      recordingTooLarge.current = false;
      recordingFailed.current = false;
      recordingStartedAt.current = performance.now();
      nextRecorder.ondataavailable = (event) => {
        if (!handlers.isCurrent() || !event.data.size) return;
        recordedBytes.current += event.data.size;
        if (recordedBytes.current > MAXIMUM_AUDIO_BYTES) {
          recordingTooLarge.current = true;
          if (nextRecorder.state === "recording") nextRecorder.stop();
          return;
        }
        chunks.current.push(event.data);
      };
      nextRecorder.onstop = () => {
        clearTicker();
        const duration = elapsedRecordingSeconds(recordingStartedAt.current, performance.now());
        setElapsedSeconds(duration);
        const completedChunks = chunks.current;
        chunks.current = [];
        recorder.current = null;
        acquiredStream.getTracks().forEach((track) => track.stop());
        if (!handlers.isCurrent()) return;
        if (recordingTooLarge.current) return handlers.onFinished({ kind: "too-large" });
        if (recordingFailed.current) return handlers.onFinished({ kind: "failed" });
        handlers.onFinished({ kind: "recorded", recording: new Blob(completedChunks, { type: nextRecorder.mimeType }), durationSeconds: duration });
      };
      nextRecorder.onerror = () => {
        if (!handlers.isCurrent()) return;
        recordingFailed.current = true;
        handlers.onEncoderError();
        if (nextRecorder.state === "recording") nextRecorder.stop();
      };
      nextRecorder.start(1_000);
      recorder.current = nextRecorder;
      handlers.onRecording();
      ticker.current = setInterval(() => {
        setElapsedSeconds(elapsedRecordingSeconds(recordingStartedAt.current, performance.now()));
        if (elapsedRef.current >= limitSeconds()) {
          clearTicker();
          if (recorder.current) handlers.onStopping();
          recorder.current?.stop();
        }
      }, 1000);
    } catch (cause) {
      stream?.getTracks().forEach((track) => track.stop());
      throw cause;
    }
  }

  function stop() {
    clearTicker();
    if (recorder.current?.state === "recording") recorder.current.stop();
  }

  return {
    elapsed,
    elapsedRef,
    setElapsedSeconds,
    isActive: () => recorder.current !== null,
    isRecording: () => recorder.current?.state === "recording",
    begin,
    stop,
  };
}
