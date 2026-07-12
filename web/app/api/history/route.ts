import { ConvexHttpClient } from "convex/browser";
import { makeFunctionReference } from "convex/server";
import { enforceRateLimit, rejectCrossOrigin } from "../../../lib/server/requestSecurity";

export const runtime = "edge";

export async function POST(request: Request) {
  const originError = rejectCrossOrigin(request);
  if (originError) return originError;
  const rateError = await enforceRateLimit(request, "HISTORY_RATE_LIMITER");
  if (rateError) return rateError;

  const convexUrl = process.env.NEXT_PUBLIC_CONVEX_URL;
  const serviceSecret = process.env.CONVEX_WEB_API_SECRET;
  if (!convexUrl || !serviceSecret) return Response.json({ error: "History is unavailable." }, { status: 503 });

  const body = await request.json() as { clientId?: string; text?: string; model?: string; durationSeconds?: number };
  const client = new ConvexHttpClient(convexUrl);
  const authorization = request.headers.get("authorization");
  if (authorization?.startsWith("Bearer ")) client.setAuth(authorization.slice(7));
  const save = makeFunctionReference<"mutation">("transcriptions:save");
  const id = await client.mutation(save, { ...body, serviceSecret });
  return Response.json({ id });
}
