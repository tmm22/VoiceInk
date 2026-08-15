// Signed-in users keep the full limits; anonymous visitors get a trial-sized
// tier so a costly transcription always has an accountable identity behind it.
export const SIGNED_IN_RECORDING_SECONDS = 30 * 60;
export const SIGNED_IN_UPLOAD_SECONDS = 2 * 60 * 60;
export const ANONYMOUS_AUDIO_SECONDS = 10 * 60;

export function recordingLimitSeconds(isSignedIn: boolean) {
  return isSignedIn ? SIGNED_IN_RECORDING_SECONDS : ANONYMOUS_AUDIO_SECONDS;
}

export function uploadLimitSeconds(isSignedIn: boolean) {
  return isSignedIn ? SIGNED_IN_UPLOAD_SECONDS : ANONYMOUS_AUDIO_SECONDS;
}

export function uploadSizeError(fileBytes: number, maximumBytes: number) {
  return fileBytes > maximumBytes ? "Audio files must be smaller than 24 MB." : null;
}

export function uploadDurationError(durationSeconds: number | null, isSignedIn: boolean) {
  if (durationSeconds === null) return "The browser could not read this audio file or determine its duration.";
  if (durationSeconds <= uploadLimitSeconds(isSignedIn)) return null;
  return isSignedIn
    ? "Audio files must be two hours or shorter."
    : "Guest uploads are limited to 10 minutes of audio. Sign in to upload up to two hours.";
}

const preferredRecorderTypes = [
  "audio/webm;codecs=opus",
  "audio/ogg;codecs=opus",
  "audio/mp4",
] as const;

export function selectRecorderMimeType(isSupported: (mimeType: string) => boolean) {
  return preferredRecorderTypes.find(isSupported);
}

export function audioFileExtension(mimeType: string) {
  const normalized = mimeType.toLowerCase();
  if (normalized.includes("ogg")) return "ogg";
  if (normalized.includes("mp4") || normalized.includes("m4a")) return "m4a";
  if (normalized.includes("wav")) return "wav";
  if (normalized.includes("mpeg") || normalized.includes("mp3")) return "mp3";
  return "webm";
}

export function elapsedRecordingSeconds(startedAt: number, now: number) {
  return Math.max(0, Math.round((now - startedAt) / 1_000));
}

export async function readAudioDuration(file: File, timeoutMs = 10_000) {
  const url = URL.createObjectURL(file);
  try {
    return await new Promise<number | null>((resolve) => {
      const audio = new Audio();
      audio.preload = "metadata";
      let settled = false;
      const finish = (value: number | null) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        audio.onloadedmetadata = null;
        audio.onerror = null;
        audio.removeAttribute("src");
        audio.load();
        resolve(value);
      };
      const timeout = setTimeout(() => finish(null), timeoutMs);
      audio.onloadedmetadata = () => finish(Number.isFinite(audio.duration) && audio.duration > 0 ? Math.round(audio.duration) : null);
      audio.onerror = () => finish(null);
      audio.src = url;
    });
  } finally {
    URL.revokeObjectURL(url);
  }
}
