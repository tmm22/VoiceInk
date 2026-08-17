import { ConvexHttpClient } from "convex/browser";
import { makeFunctionReference } from "convex/server";
import {
  enforceRateLimit,
  jsonNoStore,
  readBoundedJson,
  rejectCrossOrigin,
} from "../../../lib/server/requestSecurity";
import {
  anonymousContext,
  decryptHistoryField,
  encryptHistoryField,
  historyTextDigest,
  isEncryptedEnvelope,
  loadHistoryKey,
} from "../../../lib/server/historyCrypto";
import { isTranscriptionModelName, isValidLanguageTag } from "../../../shared/transcriptionContract";

export const runtime = "edge";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const retentionChoices = new Set([0, 7, 30, 90, 365]);

function requestFailure() {
  const requestId = crypto.randomUUID();
  return jsonNoStore(
    { error: "History is temporarily unavailable.", requestId },
    { status: 503, headers: { "x-request-id": requestId } },
  );
}

type SecuredClient =
  | { error: Response; client?: never; serviceSecret?: never; historyKey?: never; token?: never }
  | { error?: never; client: ConvexHttpClient; serviceSecret: string; historyKey: CryptoKey; token: string | null };

// The context an envelope is sealed to and opened with. It comes from Convex's
// VERIFIED identity (transcriptions:viewerContext), never a local token decode,
// so the worker's owner-vs-anonymous decision always matches the one Convex
// uses to place and return rows — a present-but-invalid token cannot make the
// seal context diverge from the read context. Anonymous callers bind to their
// clientId. Reconstructed per request, so a ciphertext transplanted into
// another row cannot open.
async function resolveContext(secured: { client: ConvexHttpClient; serviceSecret: string }, clientId: string): Promise<string> {
  const viewerContext = makeFunctionReference<"query">("transcriptions:viewerContext");
  const result = await secured.client.query(viewerContext, { serviceSecret: secured.serviceSecret }) as { ownerContext: string | null };
  return result.ownerContext ?? anonymousContext(clientId);
}

// History is stored encrypted at rest: transcripts and summaries are sealed in
// this Worker with HISTORY_ENCRYPTION_KEY before they reach Convex and opened
// only on the way back out. A missing key fails closed, like a missing service
// secret.
async function securedClient(request: Request): Promise<SecuredClient> {
  const originError = rejectCrossOrigin(request);
  if (originError) return { error: originError };
  const rateError = await enforceRateLimit(request, "HISTORY_RATE_LIMITER");
  if (rateError) return { error: rateError };

  const convexUrl = process.env.NEXT_PUBLIC_CONVEX_URL;
  const serviceSecret = process.env.CONVEX_WEB_API_SECRET;
  const keyPromise = loadHistoryKey(process.env.HISTORY_ENCRYPTION_KEY);
  if (!convexUrl || !serviceSecret || !keyPromise) {
    return { error: jsonNoStore({ error: "History is unavailable." }, { status: 503 }) };
  }
  const client = new ConvexHttpClient(convexUrl);
  const authorization = request.headers.get("authorization");
  const token = authorization?.startsWith("Bearer ") ? authorization.slice(7) : null;
  if (token) client.setAuth(token);
  return { client, serviceSecret, historyKey: await keyPromise, token };
}

export async function POST(request: Request) {
  try {
    const secured = await securedClient(request);
    if (secured.error) return secured.error;
    const parsed = await readBoundedJson<{
      clientId?: unknown; text?: unknown; model?: unknown; durationSeconds?: unknown; operationId?: unknown;
      detectedLanguage?: unknown;
    }>(request, 220_000);
    if (!parsed.ok) return parsed.response;
    const { clientId, text, model, durationSeconds, operationId, detectedLanguage } = parsed.value;
    if (typeof clientId !== "string" || !uuidPattern.test(clientId)
      || typeof operationId !== "string" || !uuidPattern.test(operationId)
      || typeof text !== "string" || !text.trim() || text.length > 200_000
      || !isTranscriptionModelName(model)
      || (detectedLanguage !== undefined && !isValidLanguageTag(detectedLanguage))
      || typeof durationSeconds !== "number" || !Number.isFinite(durationSeconds)
      || durationSeconds < 0 || durationSeconds > 21_600) {
      return jsonNoStore({ error: "The history item is invalid." }, { status: 400 });
    }
    const plaintext = text.trim();
    const context = await resolveContext(secured, clientId);
    const [cipherText, textHash] = await Promise.all([
      encryptHistoryField(secured.historyKey, "text", context, plaintext),
      historyTextDigest(secured.historyKey, operationId, plaintext),
    ]);
    const save = makeFunctionReference<"mutation">("transcriptions:save");
    const id = await secured.client.mutation(save, {
      clientId, text: cipherText, textHash, model, durationSeconds, operationId, serviceSecret: secured.serviceSecret,
      ...(detectedLanguage !== undefined ? { detectedLanguage } : {}),
    });
    return jsonNoStore({ id });
  } catch {
    return requestFailure();
  }
}

export async function GET(request: Request) {
  try {
    const secured = await securedClient(request);
    if (secured.error) return secured.error;
    const clientId = request.headers.get("x-voiceink-client-id") ?? "";
    const cursor = new URL(request.url).searchParams.get("cursor");
    if (!uuidPattern.test(clientId)) return jsonNoStore({ error: "A valid client identifier is required." }, { status: 400 });
    const list = makeFunctionReference<"query">("transcriptions:list");
    const retention = makeFunctionReference<"query">("retention:get");
    const [items, setting, context] = await Promise.all([
      secured.client.query(list, {
        clientId,
        paginationOpts: { cursor, numItems: 25 },
        serviceSecret: secured.serviceSecret,
      }),
      secured.client.query(retention, { serviceSecret: secured.serviceSecret }),
      resolveContext(secured, clientId),
    ]);
    const page = items as { page: Array<{ text: string; summary?: string }>; isDone: boolean; continueCursor: string };
    // Each row is opened independently: rows written before encryption pass
    // through unchanged, and a single envelope that fails to open (corruption,
    // a superseded key) degrades to a flagged field instead of failing the whole
    // page — the row keeps its id so the user can still delete it.
    const opened = await Promise.all(page.page.map(async (item) => {
      const openField = async (field: "text" | "summary", value: string) => {
        if (!isEncryptedEnvelope(value)) return { value };
        try {
          return { value: await decryptHistoryField(secured.historyKey, field, context, value) };
        } catch {
          return { value: "", failed: true };
        }
      };
      // Strip the raw stored summary out of the spread so a failed or absent
      // summary is genuinely dropped — never leaked as ciphertext through ...item.
      const { summary: _storedSummary, ...rest } = item;
      const text = await openField("text", item.text);
      const summary = _storedSummary !== undefined ? await openField("summary", _storedSummary) : undefined;
      return {
        ...rest,
        text: text.value,
        ...(summary !== undefined && !summary.failed ? { summary: summary.value } : {}),
        ...(text.failed ? { decryptError: true } : {}),
        ...(summary?.failed ? { summaryDecryptError: true } : {}),
      };
    }));
    return jsonNoStore({
      items: opened,
      nextCursor: page.isDone ? null : page.continueCursor,
      retentionDays: (setting as { days?: number } | null)?.days ?? null,
    });
  } catch {
    return requestFailure();
  }
}

export async function PATCH(request: Request) {
  try {
    const secured = await securedClient(request);
    if (secured.error) return secured.error;
    const parsed = await readBoundedJson<{
      action?: unknown; clientId?: unknown; id?: unknown; summary?: unknown; days?: unknown;
    }>(request, 25_000);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    if (body.action === "retention") {
      if (typeof body.days !== "number" || !retentionChoices.has(body.days)) {
        return jsonNoStore({ error: "Choose a supported retention period." }, { status: 400 });
      }
      const set = makeFunctionReference<"mutation">("retention:set");
      return jsonNoStore(await secured.client.mutation(set, {
        days: body.days,
        serviceSecret: secured.serviceSecret,
      }));
    }
    if (typeof body.id !== "string" || !body.id || body.id.length > 200
      || typeof body.clientId !== "string" || !uuidPattern.test(body.clientId)
      || typeof body.summary !== "string" || !body.summary.trim() || body.summary.length > 20_000) {
      return jsonNoStore({ error: "The summary update is invalid." }, { status: 400 });
    }
    const context = await resolveContext(secured, body.clientId);
    const saveSummary = makeFunctionReference<"mutation">("transcriptions:saveSummary");
    await secured.client.mutation(saveSummary, {
      id: body.id,
      clientId: body.clientId,
      summary: await encryptHistoryField(secured.historyKey, "summary", context, body.summary.trim()),
      serviceSecret: secured.serviceSecret,
    });
    return jsonNoStore({ ok: true });
  } catch {
    return requestFailure();
  }
}

export async function DELETE(request: Request) {
  try {
    const secured = await securedClient(request);
    if (secured.error) return secured.error;
    const url = new URL(request.url);
    const clientId = request.headers.get("x-voiceink-client-id") ?? "";
    if (!uuidPattern.test(clientId)) {
      return jsonNoStore({ error: "The history item identifier is invalid." }, { status: 400 });
    }
    if (url.searchParams.get("all") === "true") {
      const clearAll = makeFunctionReference<"mutation">("transcriptions:clearAll");
      await secured.client.mutation(clearAll, { clientId, serviceSecret: secured.serviceSecret });
      return jsonNoStore({ ok: true });
    }
    const id = url.searchParams.get("id") ?? "";
    if (!id || id.length > 200) {
      return jsonNoStore({ error: "The history item identifier is invalid." }, { status: 400 });
    }
    const remove = makeFunctionReference<"mutation">("transcriptions:remove");
    await secured.client.mutation(remove, { id, clientId, serviceSecret: secured.serviceSecret });
    return jsonNoStore({ ok: true });
  } catch {
    return requestFailure();
  }
}
