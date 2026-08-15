import { ConvexHttpClient } from "convex/browser";
import { makeFunctionReference } from "convex/server";
import {
  enforceRateLimit,
  jsonNoStore,
  readBoundedJson,
  rejectCrossOrigin,
} from "../../../lib/server/requestSecurity";
import { TRANSCRIPTION_MODEL_NAME } from "../../../shared/transcriptionContract";

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
  | { error: Response; client?: never; serviceSecret?: never }
  | { error?: never; client: ConvexHttpClient; serviceSecret: string };

async function securedClient(request: Request): Promise<SecuredClient> {
  const originError = rejectCrossOrigin(request);
  if (originError) return { error: originError };
  const rateError = await enforceRateLimit(request, "HISTORY_RATE_LIMITER");
  if (rateError) return { error: rateError };

  const convexUrl = process.env.NEXT_PUBLIC_CONVEX_URL;
  const serviceSecret = process.env.CONVEX_WEB_API_SECRET;
  if (!convexUrl || !serviceSecret) {
    return { error: jsonNoStore({ error: "History is unavailable." }, { status: 503 }) };
  }
  const client = new ConvexHttpClient(convexUrl);
  const authorization = request.headers.get("authorization");
  if (authorization?.startsWith("Bearer ")) client.setAuth(authorization.slice(7));
  return { client, serviceSecret };
}

export async function POST(request: Request) {
  try {
    const secured = await securedClient(request);
    if (secured.error) return secured.error;
    const parsed = await readBoundedJson<{
      clientId?: unknown; text?: unknown; model?: unknown; durationSeconds?: unknown; operationId?: unknown;
    }>(request, 220_000);
    if (!parsed.ok) return parsed.response;
    const { clientId, text, model, durationSeconds, operationId } = parsed.value;
    if (typeof clientId !== "string" || !uuidPattern.test(clientId)
      || typeof operationId !== "string" || !uuidPattern.test(operationId)
      || typeof text !== "string" || !text.trim() || text.length > 200_000
      || model !== TRANSCRIPTION_MODEL_NAME
      || typeof durationSeconds !== "number" || !Number.isFinite(durationSeconds)
      || durationSeconds < 0 || durationSeconds > 21_600) {
      return jsonNoStore({ error: "The history item is invalid." }, { status: 400 });
    }
    const save = makeFunctionReference<"mutation">("transcriptions:save");
    const id = await secured.client.mutation(save, {
      clientId, text, model, durationSeconds, operationId, serviceSecret: secured.serviceSecret,
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
    const [items, setting] = await Promise.all([
      secured.client.query(list, {
        clientId,
        paginationOpts: { cursor, numItems: 25 },
        serviceSecret: secured.serviceSecret,
      }),
      secured.client.query(retention, { serviceSecret: secured.serviceSecret }),
    ]);
    const page = items as { page: unknown[]; isDone: boolean; continueCursor: string };
    return jsonNoStore({
      items: page.page,
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
    const saveSummary = makeFunctionReference<"mutation">("transcriptions:saveSummary");
    await secured.client.mutation(saveSummary, {
      id: body.id,
      clientId: body.clientId,
      summary: body.summary,
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
    const id = url.searchParams.get("id") ?? "";
    const clientId = request.headers.get("x-voiceink-client-id") ?? "";
    if (!id || id.length > 200 || !uuidPattern.test(clientId)) {
      return jsonNoStore({ error: "The history item identifier is invalid." }, { status: 400 });
    }
    const remove = makeFunctionReference<"mutation">("transcriptions:remove");
    await secured.client.mutation(remove, { id, clientId, serviceSecret: secured.serviceSecret });
    return jsonNoStore({ ok: true });
  } catch {
    return requestFailure();
  }
}
