import {
  boundedDurationSeconds,
  ENGLISH_TRANSCRIPTION_MODEL_ID,
  ENGLISH_TRANSCRIPTION_MODEL_NAME,
  isEnglishLanguageTag,
  isSupportedAudioMediaType,
  isValidLanguageTag,
  LANGUAGE_HINT_HEADER,
  MULTILINGUAL_TRANSCRIPTION_MODEL_ID,
  MULTILINGUAL_TRANSCRIPTION_MODEL_NAME,
  normalizeAudioMediaType,
  parseLanguageHint,
  parseTranscriptionResponse,
} from "../../shared/transcriptionContract.ts";
import {
  actualTranscriptionMicros,
  ENGLISH_TRANSCRIPTION_MICROS_PER_MINUTE,
  estimateTranscriptionMicros,
  INFERENCE_TIMEOUT_MS,
  MULTILINGUAL_TRANSCRIPTION_MICROS_PER_MINUTE,
  worstCaseAudioSeconds,
} from "./budget.ts";
import { admissionDenial, reserveSpendLogged, type AsrEnv } from "./admission.ts";
import { openAudioUpload } from "./audioUpload.ts";
import { extractDeepgramTranscription } from "./deepgram.ts";
import { characterBucket, internalBodyLength, json, logInferenceFailure, requestClientKey } from "./http.ts";
import { commitSpend, releaseSpend } from "./ledgerClient.ts";

// Whisper's supported language codes (the ISO 639-1 subset of its tokenizer).
const WHISPER_LANGUAGES = new Set(("af am ar as az ba be bg bn bo br bs ca cs cy da de el en es et eu fa fi fo fr gl gu ha haw he hi hr ht hu hy id is it ja jw ka kk km kn ko la lb ln lo lt lv mg mi mk ml mn mr ms mt my ne nl nn no oc pa pl ps pt ro ru sa sd si sk sl sn so sq sr su sv sw ta te tg th tk tl tr tt uk ur uz vi yi yo yue zh").split(" "));

export function whisperLanguageCode(tag: string | undefined) {
  const primary = tag?.split("-", 1)[0]?.toLowerCase();
  return primary && WHISPER_LANGUAGES.has(primary) ? primary : undefined;
}

export async function handleTranscription(request: Request, env: AsrEnv, executionContext: ExecutionContext): Promise<Response> {
  const declaredBytes = internalBodyLength(request);
  if (declaredBytes === null) {
    return json({ error: "The declared request size is invalid" }, { status: 400 });
  }
  const mediaType = normalizeAudioMediaType(request.headers.get("content-type") ?? "");
  if (!isSupportedAudioMediaType(mediaType)) {
    return json({ error: "Only supported audio uploads are accepted" }, { status: 415 });
  }
  // The deadline bounds the whole paid pipeline — upload and inference —
  // below the reservation-expiry window, so a live request always settles
  // before its reservation can be swept, and a stalled or trickled upload is
  // aborted here rather than pinning the worker for minutes.
  const deadline = AbortSignal.any([request.signal, AbortSignal.timeout(INFERENCE_TIMEOUT_MS)]);

  // Admission prices the declared bytes at the worst-case (lowest) bitrate,
  // and the upload stream errors before it can deliver more than that. Both
  // inputs to the reservation are known before the body arrives, so the
  // ledger round trip overlaps reading the signature prefix. Inference starts
  // only after admission.ok and streams the rest of the upload as it arrives;
  // an admitted reservation whose upload then fails validation is released
  // (or settled, if a model had already run).
  //
  // A confident non-English language hint (see
  // confidentNonEnglishLanguageHint) skips nova-3 entirely: the upload
  // streams once into whisper and admission prices whisper alone.
  const languageHint = parseLanguageHint(request.headers.get(LANGUAGE_HINT_HEADER));
  const estimatedSeconds = worstCaseAudioSeconds(declaredBytes);
  const [upload, admission] = await Promise.all([
    openAudioUpload(request.body, mediaType, declaredBytes, deadline),
    reserveSpendLogged(env, request, {
      estimateMicros: languageHint
        ? estimateTranscriptionMicros(declaredBytes, MULTILINGUAL_TRANSCRIPTION_MICROS_PER_MINUTE)
        : estimateTranscriptionMicros(declaredBytes),
      secondsEstimate: estimatedSeconds,
      clientKey: requestClientKey(request),
    }),
  ]);
  if (!upload) {
    if (admission.ok) executionContext.waitUntil(releaseSpend(env, admission.id));
    return json({ error: "The uploaded audio format is invalid" }, { status: 415 });
  }
  if (!admission.ok) {
    void upload.stream.cancel().catch(() => {});
    return admissionDenial(admission);
  }
  // One branch feeds nova-3 as the upload streams in; the other holds the
  // same chunks (one copy, never re-concatenated) only in case the request
  // falls back to whisper, and is cancelled as soon as nova-3 settles it.
  // A hinted request has no nova-3 branch, so nothing is held.
  const [englishAudio, fallbackAudio] = languageHint ? [null, upload.stream] : upload.stream.tee();

  // A body that ran past or short of its declared length is rejected even if
  // a model already returned output for the bytes it did receive (bindings
  // are not guaranteed to fail when their input stream errors). Spend for a
  // model that did run is still settled, never released.
  const invalidUpload = (billedMicros: number, billedSeconds: number) => {
    void fallbackAudio.cancel().catch(() => {});
    executionContext.waitUntil(billedMicros > 0
      ? commitSpend(env, admission.id, billedMicros, Math.round(billedSeconds))
      : releaseSpend(env, admission.id));
    return json({ error: "The uploaded audio format is invalid" }, { status: 415 });
  };

  // English-first routing: nova-3 transcribes with language detection and
  // smart formatting. Non-English audio (and any nova-3 failure) falls back
  // to whisper, which covers the long tail of languages. The reservation
  // already priced both models, so the fallback never exceeds admission.
  let english: ReturnType<typeof extractDeepgramTranscription> = null;
  let englishBilled = false;
  if (englishAudio) {
    try {
      const raw = await env.AI.run(ENGLISH_TRANSCRIPTION_MODEL_ID, {
        audio: { body: englishAudio, contentType: mediaType },
        detect_language: true,
        smart_format: true,
        punctuate: true,
        paragraphs: true,
      }, { signal: deadline });
      englishBilled = true;
      english = extractDeepgramTranscription(raw);
    } catch (error) {
      if (request.signal.aborted || deadline.aborted) {
        void fallbackAudio.cancel().catch(() => {});
        executionContext.waitUntil(releaseSpend(env, admission.id));
        return json({ error: "Transcription generation failed" }, { status: 502 });
      }
      // Drop the nova-3 branch so tee() stops queueing chunks for it while
      // whisper reads the fallback branch.
      void englishAudio.cancel().catch(() => {});
      logInferenceFailure("voiceink_english_inference_failed", error);
    }
  }

  const englishSeconds = english?.durationSeconds ?? estimatedSeconds;
  const englishMicros = englishBilled ? actualTranscriptionMicros(englishSeconds, ENGLISH_TRANSCRIPTION_MICROS_PER_MINUTE) : 0;
  if (upload.rejected()) return invalidUpload(englishMicros, englishBilled ? englishSeconds : 0);

  // Nova-3 reports every spoken language; any non-English tag routes the
  // request to whisper. Missing detection deliberately counts as English.
  const detectedLanguages = english?.detectedLanguages ?? [];
  const nonEnglishLanguage = detectedLanguages.find((tag) => !isEnglishLanguageTag(tag));
  if (english && nonEnglishLanguage === undefined) {
    if (!upload.completed()) return invalidUpload(englishMicros, englishSeconds);
    void fallbackAudio.cancel().catch(() => {});
    const detectedLanguage = detectedLanguages[0];
    executionContext.waitUntil(commitSpend(env, admission.id, englishMicros, Math.round(englishSeconds)));
    const response = parseTranscriptionResponse({
      text: english.text,
      model: ENGLISH_TRANSCRIPTION_MODEL_NAME,
      ...(english.durationSeconds !== undefined ? { durationSeconds: english.durationSeconds } : {}),
      ...(detectedLanguage ? { detectedLanguage } : {}),
    });
    if (!response) {
      console.error("voiceink_transcription_invalid_output", {
        model: ENGLISH_TRANSCRIPTION_MODEL_NAME,
        textCharacters: characterBucket(english.text.length),
      });
      return json({ error: "Transcription generation failed" }, { status: 502 });
    }
    console.log("voiceink_transcription_route", {
      model: response.model,
      detectedLanguage: detectedLanguage ?? null,
    });
    return json(response);
  }

  try {
    const forcedLanguage = whisperLanguageCode(nonEnglishLanguage);
    const result = await env.AI.run(MULTILINGUAL_TRANSCRIPTION_MODEL_ID, {
      audio: { body: fallbackAudio, contentType: mediaType },
      task: "transcribe",
      // Only a language nova-3 actually detected is forced; a browser hint can
      // be wrong (an English speaker on a German browser), and forcing the
      // wrong language garbles speech that whisper would otherwise auto-detect.
      ...(forcedLanguage ? { language: forcedLanguage } : {}),
      vad_filter: true,
      beam_size: 5,
      // Both settings trade a little cross-segment context for fewer
      // fabricated repeats and fewer phrases invented over long silences.
      condition_on_previous_text: false,
      hallucination_silence_threshold: 2,
    }, { signal: deadline });

    const text = typeof result.text === "string" ? result.text.trim() : "";
    const duration = boundedDurationSeconds(result.transcription_info?.duration);
    const whisperLanguage = isValidLanguageTag(result.transcription_info?.language)
      ? result.transcription_info.language.toLowerCase()
      : undefined;
    const detectedLanguage = nonEnglishLanguage ?? whisperLanguage;
    const settledSeconds = duration ?? estimatedSeconds;
    // nova-3 inference that completed is still billed even when its output
    // was routed away from, so the ledger reflects true provider spend.
    const settledMicros = actualTranscriptionMicros(settledSeconds, MULTILINGUAL_TRANSCRIPTION_MICROS_PER_MINUTE)
      + (englishBilled ? actualTranscriptionMicros(settledSeconds, ENGLISH_TRANSCRIPTION_MICROS_PER_MINUTE) : 0);
    if (upload.rejected() || !upload.completed()) return invalidUpload(settledMicros, settledSeconds);
    executionContext.waitUntil(commitSpend(env, admission.id, settledMicros, Math.round(settledSeconds)));
    const response = parseTranscriptionResponse({
      text,
      model: MULTILINGUAL_TRANSCRIPTION_MODEL_NAME,
      ...(duration !== undefined ? { durationSeconds: duration } : {}),
      ...(detectedLanguage ? { detectedLanguage } : {}),
      ...(Array.isArray(result.segments) ? { segments: result.segments } : {}),
    });
    if (!response) {
      console.error("voiceink_transcription_invalid_output", {
        model: MULTILINGUAL_TRANSCRIPTION_MODEL_NAME,
        hasText: Boolean(text),
        textCharacters: characterBucket(text.length),
        durationType: typeof duration,
        segmentCount: Array.isArray(result.segments) ? result.segments.length : null,
      });
      return json({ error: "Transcription generation failed" }, { status: 502 });
    }
    console.log("voiceink_transcription_route", {
      model: response.model,
      detectedLanguage: detectedLanguage ?? null,
      englishModelRan: englishBilled,
      languageHinted: languageHint !== null,
    });
    return json(response);
  } catch (error) {
    if (upload.rejected()) return invalidUpload(englishMicros, englishSeconds);
    // A completed nova-3 run is still real provider spend even when the
    // whisper fallback fails, so settle it rather than releasing everything.
    if (englishBilled) {
      executionContext.waitUntil(commitSpend(env, admission.id, englishMicros, Math.round(englishSeconds)));
    } else {
      executionContext.waitUntil(releaseSpend(env, admission.id));
    }
    logInferenceFailure("voiceink_transcription_inference_failed", error);
    return json({ error: "Transcription generation failed" }, { status: 502 });
  }
}
