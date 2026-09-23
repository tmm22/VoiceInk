import type { Status } from "./use-transcription-session";

const stageHeadings: Partial<Record<Status, string>> = { starting: "Requesting microphone…", recording: "Recording", validating: "Checking audio…", stopping: "Processing audio…", verifying: "Verifying…", transcribing: "Transcribing…", saving: "Saving to history…" };

// The recorder card's copy for each pipeline stage. Elapsed values are real
// timers; there is no simulated progress.
export function recordingStage(status: Status, elapsed: number, transcribeElapsed: number) {
  const time = `${String(Math.floor(elapsed / 60)).padStart(2, "0")}:${String(elapsed % 60).padStart(2, "0")}`;
  const stageDetails: Partial<Record<Status, [string, string]>> = {
    recording: [time, "Stop to upload and transcribe"],
    stopping: ["Processing audio…", "Preparing the recording for upload"],
    verifying: ["Verifying…", "Running the security check before upload"],
    transcribing: [`Transcribing… ${transcribeElapsed}s`, "The transcript will be saved to history"],
    saving: ["Saving…", "Adding the transcript to history"],
  };
  const [strong, small] = stageDetails[status] ?? ["Press to record", "Microphone access stays in this tab"];
  return {
    heading: stageHeadings[status] ?? "Ready to record",
    strong,
    small,
    busy: status === "starting" || status === "validating" || status === "stopping" || status === "verifying" || status === "transcribing" || status === "saving",
  };
}
