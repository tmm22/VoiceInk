"use client";

import { useEffect, useRef, useState, type Dispatch, type SetStateAction } from "react";
import { saveTranscription, type TranscriptionHistoryItem } from "../lib/convex";
import {
  elapsedRecordingSeconds,
  readAudioDuration,
  recordingLimitSeconds,
  uploadDurationError,
  uploadSizeError,
} from "../lib/recording";
import { requestTranscription, transcriptionFailureMessage } from "../lib/transcriptionRequest";
import { beginTranscriptionTokenHold, releaseTranscriptionTokenHold } from "../lib/turnstileClient";
import { MAXIMUM_AUDIO_BYTES, type TranscriptionSegment } from "../shared/transcriptionContract";
import type { AccountAuth } from "./providers";
import { useRecordingSession } from "./use-recording-session";

export type Status = "idle" | "starting" | "recording" | "validating" | "stopping" | "verifying" | "transcribing" | "saving" | "done" | "error";

// Where the session delivers transcript state owned by the page.
export type TranscriptSink = {
  clear: (options: { summaryError: boolean }) => void;
  show: (text: string, segments: TranscriptionSegment[]) => void;
  saved: (id: string | null) => void;
};

const transcriptionTimeoutMs = 5 * 60 * 1_000;

// One recording-or-upload operation at a time: record/upload → verify →
// transcribe → save to history. A newer operation supersedes an older one
// through operationGeneration (recording) and activeTranscription (jobs).
export function useTranscriptionSession({ account, setHistory, setError, transcript }: {
  account: AccountAuth;
  setHistory: Dispatch<SetStateAction<TranscriptionHistoryItem[]>>;
  setError: (message: string) => void;
  transcript: TranscriptSink;
}) {
  const isSignedInRef = useRef(account.isSignedIn);
  isSignedInRef.current = account.isSignedIn;
  const recording = useRecordingSession(() => recordingLimitSeconds(isSignedInRef.current));
  const audioOperationId = useRef<string | null>(null);
  const activeTranscription = useRef<{ id: string; controller: AbortController } | null>(null);
  const operationGeneration = useRef(0);
  const recordingStartPending = useRef(false);
  const transcribeTicker = useRef<ReturnType<typeof setInterval> | null>(null);
  // The in-flight history save for the current transcript, so a summary
  // generated during that window serializes its PATCH after the save settles.
  const pendingSave = useRef<Promise<string | null> | null>(null);
  const [status, setStatus] = useState<Status>("idle");
  const [transcribeElapsed, setTranscribeElapsed] = useState(0);
  const [audio, setAudio] = useState<Blob | null>(null);

  useEffect(() => () => {
    if (transcribeTicker.current) clearInterval(transcribeTicker.current);
    releaseTranscriptionTokenHold();
    const pendingTranscription = activeTranscription.current;
    activeTranscription.current = null;
    pendingTranscription?.controller.abort();
    operationGeneration.current += 1;
  }, []);

  // Elapsed-seconds ticker for the transcribing stage (same pattern as the
  // recording ticker). No fake progress — only real elapsed time.
  function startTranscribeTicker() {
    stopTranscribeTicker();
    const startedAt = performance.now();
    transcribeTicker.current = setInterval(() => setTranscribeElapsed(elapsedRecordingSeconds(startedAt, performance.now())), 1000);
  }
  function stopTranscribeTicker() {
    if (transcribeTicker.current) clearInterval(transcribeTicker.current);
    transcribeTicker.current = null;
    setTranscribeElapsed(0);
  }

  function supersedeActiveTranscription() {
    const previousTranscription = activeTranscription.current;
    activeTranscription.current = null;
    previousTranscription?.controller.abort();
    pendingSave.current = null;
  }

  async function startRecording() {
    if (recordingStartPending.current || recording.isActive()) return;
    recordingStartPending.current = true;
    // Pre-execute the Turnstile challenge and hold the single-use token for
    // the stop click; the widget re-executes on expiry during long recordings.
    beginTranscriptionTokenHold();
    const generation = ++operationGeneration.current;
    const isCurrent = () => generation === operationGeneration.current;
    try {
      supersedeActiveTranscription();
      setError("");
      transcript.clear({ summaryError: false });
      setAudio(null);
      setStatus("starting");
      await recording.begin({
        isCurrent,
        onRecording: () => {
          audioOperationId.current = crypto.randomUUID();
          setStatus("recording");
        },
        onStopping: () => setStatus("stopping"),
        onEncoderError: () => setError("Recording stopped because the browser audio encoder failed."),
        onFinished: (outcome) => {
          if (outcome.kind !== "recorded") {
            releaseTranscriptionTokenHold();
            setAudio(null);
            if (outcome.kind === "too-large") setError("The recording reached the 24 MB safety limit. Record a shorter clip and try again.");
            setStatus("error");
            return;
          }
          setAudio(outcome.recording);
          void transcribe(outcome.recording, outcome.durationSeconds, audioOperationId.current ?? crypto.randomUUID());
        },
      });
    } catch {
      if (isCurrent()) {
        releaseTranscriptionTokenHold();
        setError("Microphone access is required to record a transcription.");
        setStatus("error");
      }
    } finally {
      recordingStartPending.current = false;
    }
  }

  function stopRecording() {
    // Synchronous stop-click feedback; the pipeline replaces it with its stages.
    if (recording.isRecording()) setStatus("stopping");
    recording.stop();
  }

  async function transcribe(recordingBlob: Blob, durationSeconds: number, operationId = audioOperationId.current ?? crypto.randomUUID()) {
    activeTranscription.current?.controller.abort();
    const controller = new AbortController();
    const job = { id: crypto.randomUUID(), controller };
    activeTranscription.current = job;
    audioOperationId.current = operationId;
    const timeout = window.setTimeout(() => controller.abort(), transcriptionTimeoutMs);
    // Warm-up only: start a Convex token fetch now so Clerk's token cache is
    // primed while upload and inference run. The save path below fetches its
    // own fresh token — this result is never consumed, and the marker only
    // prevents an unhandled rejection when transcription fails first.
    const convexToken = account.getConvexToken();
    convexToken.catch(() => {});
    setStatus("verifying");
    setError("");
    try {
      const result = await requestTranscription(recordingBlob, controller.signal, (stage) => {
        if (activeTranscription.current?.id !== job.id) return;
        setStatus(stage);
        if (stage === "transcribing") startTranscribeTicker();
      });
      const transcribedText = result.text;
      const effectiveDuration = result.durationSeconds ?? durationSeconds;
      if (activeTranscription.current?.id !== job.id) return;
      stopTranscribeTicker();
      setAudio(null);
      transcript.show(transcribedText, result.segments ?? []);
      setStatus("saving");
      const savePromise = (async () => {
        // Fetch the token fresh at save time: Clerk session JWTs live about a
        // minute while upload+inference can run for several, so the warm-up
        // token above may already be expired server-side — Convex would then
        // resolve a null identity and silently file the row as anonymous.
        // Clerk caches tokens, so this call is near-free while still valid.
        const token = await account.getConvexToken();
        const savedId = await saveTranscription({
          text: transcribedText,
          durationSeconds: effectiveDuration,
          model: result.model,
          detectedLanguage: result.detectedLanguage,
          operationId,
          segments: result.segments,
        }, token);
        return savedId ?? null;
      })();
      // A summary requested before the save settles serializes on this.
      pendingSave.current = savePromise.then((id) => id, () => null);
      try {
        const savedId = await savePromise;
        if (activeTranscription.current?.id !== job.id) return;
        transcript.saved(savedId);
        // Prepend the saved row locally instead of refetching the whole page.
        if (savedId) {
          const savedItem: TranscriptionHistoryItem = { _id: savedId, text: transcribedText, durationSeconds: effectiveDuration, model: result.model, detectedLanguage: result.detectedLanguage, operationId, segments: result.segments, status: "complete", createdAt: Date.now() };
          setHistory((items) => items.some((item) => item._id === savedId) ? items : [savedItem, ...items]);
        }
      } catch {
        setError("The transcript is ready, but it could not be saved to history. Check your quota or retention settings.");
      } finally {
        if (activeTranscription.current?.id === job.id) setStatus("done");
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
      stopTranscribeTicker();
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
    supersedeActiveTranscription();
    setError("");
    setStatus("validating");
    transcript.clear({ summaryError: true });
    const duration = await readAudioDuration(file);
    if (generation !== operationGeneration.current) return;
    const durationError = uploadDurationError(duration, isSignedInRef.current);
    if (durationError || duration === null) {
      setError(durationError ?? "");
      setStatus("error");
      return;
    }
    setAudio(file);
    recording.setElapsedSeconds(duration);
    audioOperationId.current = crypto.randomUUID();
    await transcribe(file, duration, audioOperationId.current);
  }

  function retryTranscription() {
    if (audio) void transcribe(audio, recording.elapsedRef.current, audioOperationId.current ?? crypto.randomUUID());
  }

  return {
    status,
    elapsed: recording.elapsed,
    transcribeElapsed,
    audio,
    pendingSave,
    startRecording,
    stopRecording,
    uploadAudio,
    retryTranscription,
  };
}
