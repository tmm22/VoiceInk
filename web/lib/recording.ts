export const maximumRecordingSeconds = 30 * 60;
export const maximumUploadSeconds = 2 * 60 * 60;

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
