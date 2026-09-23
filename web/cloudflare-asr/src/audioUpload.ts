import { hasMatchingAudioSignature, MAXIMUM_AUDIO_BYTES } from "../../shared/transcriptionContract.ts";

// Enough leading bytes for every signature hasMatchingAudioSignature checks.
const SIGNATURE_BYTES = 16;

export type AudioUpload = {
  // The complete upload, re-emitting the signature prefix. It errors (and so
  // fails whichever model is reading it) the moment the body exceeds its
  // declared length or MAXIMUM_AUDIO_BYTES, ends short of the declared length,
  // or the deadline aborts — the byte count a reservation priced is never
  // exceeded, and a truncated upload never completes as a transcript.
  stream: ReadableStream<Uint8Array>;
  // True once the body was rejected for its length (as opposed to aborted),
  // so the caller can answer 415 instead of an inference failure.
  rejected(): boolean;
  // True once the whole declared body was delivered and the stream closed.
  // A model that returns without reading to the end has not had the upload's
  // length validated, so its output must not be accepted.
  completed(): boolean;
};

// Streams the request body instead of buffering it, so inference can start
// while the upload is still arriving and peak memory stays near one copy of
// the audio. Only the signature prefix is read before returning; null means
// the upload is missing, aborted, or does not match its declared media type.
export async function openAudioUpload(
  body: ReadableStream<Uint8Array> | null,
  mediaType: string,
  declaredBytes: number,
  signal: AbortSignal,
): Promise<AudioUpload | null> {
  if (!body || signal.aborted) return null;
  const reader = body.getReader();
  const limit = Math.min(declaredBytes, MAXIMUM_AUDIO_BYTES);
  const prefix: Uint8Array[] = [];
  let received = 0;
  let sourceDone = false;
  let lengthRejected = false;
  let lengthVerified = false;

  const cancelSource = () => void reader.cancel().catch(() => {});
  // The deadline also bounds the prefix read, so a client that stalls before
  // sending the signature bytes cannot pin the request past INFERENCE_TIMEOUT_MS.
  signal.addEventListener("abort", cancelSource, { once: true });
  try {
    while (received < SIGNATURE_BYTES) {
      const { done, value } = await reader.read();
      if (done) {
        sourceDone = true;
        break;
      }
      received += value.byteLength;
      prefix.push(value);
      if (received > limit) {
        cancelSource();
        return null;
      }
    }
  } catch {
    return null;
  } finally {
    signal.removeEventListener("abort", cancelSource);
  }
  if (signal.aborted || !hasMatchingAudioSignature(mediaType, concatenate(prefix, SIGNATURE_BYTES))) {
    cancelSource();
    return null;
  }
  if (sourceDone && received !== declaredBytes) return null;

  let onAbort: (() => void) | null = null;
  const detach = () => {
    if (onAbort) signal.removeEventListener("abort", onAbort);
    onAbort = null;
  };
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      onAbort = () => {
        detach();
        controller.error(signal.reason ?? new Error("Upload aborted"));
        cancelSource();
      };
      signal.addEventListener("abort", onAbort, { once: true });
    },
    async pull(controller) {
      const buffered = prefix.shift();
      if (buffered) {
        controller.enqueue(buffered);
        return;
      }
      if (sourceDone) {
        detach();
        lengthVerified = true;
        controller.close();
        return;
      }
      let chunk: ReadableStreamReadResult<Uint8Array>;
      try {
        chunk = await reader.read();
      } catch (error) {
        detach();
        controller.error(error);
        return;
      }
      if (chunk.done) {
        detach();
        if (received !== declaredBytes) {
          lengthRejected = true;
          controller.error(new Error("Upload ended before its declared length"));
        } else {
          lengthVerified = true;
          controller.close();
        }
        return;
      }
      received += chunk.value.byteLength;
      if (received > limit) {
        lengthRejected = true;
        detach();
        controller.error(new Error("Upload exceeded its declared length"));
        cancelSource();
        return;
      }
      controller.enqueue(chunk.value);
    },
    cancel() {
      detach();
      cancelSource();
    },
  });
  return { stream, rejected: () => lengthRejected, completed: () => lengthVerified };
}

function concatenate(chunks: Uint8Array[], maximumBytes: number) {
  const bytes = new Uint8Array(Math.min(maximumBytes, chunks.reduce((total, chunk) => total + chunk.byteLength, 0)));
  let offset = 0;
  for (const chunk of chunks) {
    if (offset >= bytes.byteLength) break;
    const slice = chunk.subarray(0, bytes.byteLength - offset);
    bytes.set(slice, offset);
    offset += slice.byteLength;
  }
  return bytes;
}
