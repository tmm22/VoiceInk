import {
  parseTranscriptionResponse,
  TURNSTILE_TOKEN_HEADER,
  type TranscriptionResponse,
} from "../shared/transcriptionContract";
import { acquireTranscriptionToken, takeHeldTranscriptionToken } from "./turnstileClient";

export type TranscriptionStage = "verifying" | "transcribing";

export async function requestTranscription(
  recording: Blob,
  signal: AbortSignal,
  onStage?: (stage: TranscriptionStage) => void,
): Promise<TranscriptionResponse> {
  onStage?.("verifying");
  // The token pre-executed at recording start is consumed when present
  // (single-use, never reused); otherwise fall back to stop-time acquisition.
  const turnstileToken = takeHeldTranscriptionToken() ?? await acquireTranscriptionToken();
  signal.throwIfAborted();
  onStage?.("transcribing");
  const response = await fetch("/api/transcribe", {
    method: "POST",
    headers: {
      "content-type": recording.type,
      ...(turnstileToken ? { [TURNSTILE_TOKEN_HEADER]: turnstileToken } : {}),
    },
    body: recording,
    cache: "no-store",
    signal,
  });
  if (response.status === 403) throw new Error("verification-failed");
  if (response.status === 429) throw new Error("capacity-reached");
  if (!response.ok) throw new Error("Transcription failed");
  const result = parseTranscriptionResponse(await response.json());
  if (!result) throw new Error("No speech was detected");
  return result;
}

export function transcriptionFailureMessage(cause: unknown) {
  const reason = cause instanceof Error ? cause.message : "";
  if (reason === "verification-failed") {
    return "Security verification did not pass. Your recording is still available — please try again.";
  }
  if (reason === "capacity-reached") {
    return "The daily transcription capacity has been reached. Your recording is still available to retry later.";
  }
  return "The transcription service could not be reached. Your recording is still available to retry.";
}
