// Shared fakes for exercising the ASR Worker's fetch handler in Node.
export const TEST_ASR_KEY = "test-asr-key";

// Workers accept a streamed Request body without options; Node's fetch
// requires `duplex: "half"`. Route code is written for Workers, so tests
// supply the Node-only option instead of the production code.
export function allowStreamedRequestBodies() {
  const NativeRequest = globalThis.Request;
  if (NativeRequest.voiceinkStreamedBodies) return;
  class StreamingRequest extends NativeRequest {
    constructor(input, init) {
      super(input, init?.body instanceof ReadableStream ? { duplex: "half", ...init } : init);
    }
  }
  StreamingRequest.voiceinkStreamedBodies = true;
  globalThis.Request = StreamingRequest;
}

export function wavBytes(byteLength = 64) {
  const bytes = new Uint8Array(byteLength);
  bytes.set(new TextEncoder().encode("RIFF"), 0);
  bytes.set(new TextEncoder().encode("WAVE"), 8);
  return bytes;
}

// A body delivered in several chunks so tests exercise real stream reads.
export function chunkedStream(bytes, chunkSize = 16) {
  let offset = 0;
  return new ReadableStream({
    pull(controller) {
      if (offset >= bytes.byteLength) {
        controller.close();
        return;
      }
      controller.enqueue(bytes.slice(offset, offset + chunkSize));
      offset += chunkSize;
    },
  });
}

export function transcriptionRequest({
  bytes = wavBytes(),
  declaredBytes = bytes.byteLength,
  contentType = "audio/wav",
  authorization = `Bearer ${TEST_ASR_KEY}`,
  headers = {},
} = {}) {
  return new Request("https://asr.internal/v1/transcriptions", {
    method: "POST",
    headers: {
      authorization,
      "content-type": contentType,
      "x-voiceink-body-length": String(declaredBytes),
      "x-voiceink-client-key": "client-pseudonym",
      ...headers,
    },
    body: chunkedStream(bytes),
    duplex: "half",
  });
}

export function novaResult({ transcript = "Hello there.", languages = ["en"], duration = 3 } = {}) {
  return {
    metadata: { duration },
    results: {
      channels: [{
        alternatives: [{ transcript, ...(languages ? { languages } : {}) }],
      }],
    },
  };
}

export function whisperResult({ text = "Hola a todos.", duration = 3, language } = {}) {
  return {
    text,
    transcription_info: { duration, ...(language ? { language } : {}) },
    segments: [{ start: 0, end: duration, text }],
  };
}

// Records every model call (including how many audio bytes each one read) and
// every ledger operation, so tests can assert routing and settlement exactly.
// swallowStreamErrors mimics a binding that returns output for the bytes it
// received even though its input stream errored (observed under wrangler dev).
export function fakeAsrEnv({ models = {}, admission = { ok: true, id: "reservation-1" }, swallowStreamErrors = false } = {}) {
  const calls = [];
  const ledger = [];
  const pending = [];
  const env = {
    ASR_API_KEY: TEST_ASR_KEY,
    AI: {
      async run(model, input, options) {
        const call = { model, input, bytesRead: 0, signal: options?.signal };
        calls.push(call);
        if (input?.audio?.body) {
          const reader = input.audio.body.getReader();
          try {
            for (;;) {
              const { done, value } = await reader.read();
              if (done) break;
              call.bytesRead += value.byteLength;
            }
          } catch (error) {
            if (!swallowStreamErrors) throw error;
          }
        }
        const handler = models[model];
        if (!handler) throw new Error(`unexpected model ${model}`);
        return handler(call);
      },
    },
    SPEND_LEDGER: {
      idFromName: (name) => name,
      get: () => ({
        async reserve(request) {
          ledger.push({ op: "reserve", request });
          return admission;
        },
        async commit(id, micros, seconds) {
          ledger.push({ op: "commit", id, micros, seconds });
        },
        async release(id) {
          ledger.push({ op: "release", id });
        },
      }),
    },
  };
  const executionContext = {
    waitUntil(promise) { pending.push(promise); },
    passThroughOnException() {},
  };
  return {
    env,
    executionContext,
    calls,
    ledger,
    settled: () => Promise.all(pending),
  };
}
