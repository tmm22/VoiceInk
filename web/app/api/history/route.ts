import { ConvexHttpClient } from "convex/browser";
import { makeFunctionReference } from "convex/server";
import { enforceRateLimit, rejectCrossOrigin, rejectOversizedRequest } from "../../../lib/server/requestSecurity";

export const runtime = "edge";

async function securedClient(request: Request) {
  const originError = rejectCrossOrigin(request);
  if (originError) return { error: originError };
  const rateError = await enforceRateLimit(request, "HISTORY_RATE_LIMITER");
  if (rateError) return { error: rateError };

  const convexUrl = process.env.NEXT_PUBLIC_CONVEX_URL;
  const serviceSecret = process.env.CONVEX_WEB_API_SECRET;
  if (!convexUrl || !serviceSecret) return { error: Response.json({ error: "History is unavailable." }, { status: 503 }) };
  const client = new ConvexHttpClient(convexUrl);
  const authorization = request.headers.get("authorization");
  if (authorization?.startsWith("Bearer ")) client.setAuth(authorization.slice(7));
  return { client, serviceSecret };
}

export async function POST(request: Request) {
  const oversized = rejectOversizedRequest(request, 220_000);
  if (oversized) return oversized;
  const secured = await securedClient(request);
  if (secured.error) return secured.error;
  const body = await request.json() as { clientId?: string; text?: string; model?: string; durationSeconds?: number };
  const save = makeFunctionReference<"mutation">("transcriptions:save");
  const id = await secured.client.mutation(save, { ...body, serviceSecret: secured.serviceSecret });
  return Response.json({ id });
}

export async function GET(request: Request) {
  const secured = await securedClient(request);
  if (secured.error) return secured.error;
  const clientId = new URL(request.url).searchParams.get("clientId") ?? "";
  const list = makeFunctionReference<"query">("transcriptions:list");
  const retention = makeFunctionReference<"query">("retention:get");
  const [items, setting] = await Promise.all([
    secured.client.query(list, { clientId, serviceSecret: secured.serviceSecret }),
    secured.client.query(retention, { serviceSecret: secured.serviceSecret }),
  ]);
  return Response.json({ items, retentionDays: (setting as { days?: number } | null)?.days ?? null });
}

export async function PATCH(request: Request) {
  const oversized = rejectOversizedRequest(request, 25_000);
  if (oversized) return oversized;
  const secured = await securedClient(request);
  if (secured.error) return secured.error;
  const body = await request.json() as { action?: string; clientId?: string; id?: string; summary?: string; days?: number };
  if (body.action === "retention") {
    const set = makeFunctionReference<"mutation">("retention:set");
    return Response.json(await secured.client.mutation(set, { days: body.days, serviceSecret: secured.serviceSecret }));
  }
  const saveSummary = makeFunctionReference<"mutation">("transcriptions:saveSummary");
  await secured.client.mutation(saveSummary, { id: body.id, clientId: body.clientId, summary: body.summary, serviceSecret: secured.serviceSecret });
  return Response.json({ ok: true });
}

export async function DELETE(request: Request) {
  const secured = await securedClient(request);
  if (secured.error) return secured.error;
  const url = new URL(request.url);
  const remove = makeFunctionReference<"mutation">("transcriptions:remove");
  await secured.client.mutation(remove, { id: url.searchParams.get("id"), clientId: url.searchParams.get("clientId") ?? "", serviceSecret: secured.serviceSecret });
  return Response.json({ ok: true });
}
