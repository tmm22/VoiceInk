import { reserveSpend, type Admission, type LedgerEnv } from "./ledgerClient.ts";
import { json, requestColo } from "./http.ts";

export interface AsrEnv extends LedgerEnv {
  AI: Ai;
  ASR_API_KEY: string;
}

export function admissionDenial(admission: Extract<Admission, { ok: false }>) {
  if (admission.reason === "unavailable") {
    return json({ error: "Inference protection is unavailable" }, { status: 503 });
  }
  return json({ error: "Daily capacity has been reached. Please try again later." }, {
    status: 429,
    headers: { "retry-after": "3600" },
  });
}

// Every paid request pays one SpendLedger round trip before inference, so the
// reserve duration is logged (metadata only — never the client key) to make
// the durable object's placement cost readable from observability before any
// locationHint migration decision.
export async function reserveSpendLogged(
  env: AsrEnv,
  request: Request,
  spend: { estimateMicros: number; secondsEstimate: number; clientKey: string },
): Promise<Admission> {
  const startedAt = Date.now();
  const admission = await reserveSpend(env, spend);
  console.log("voiceink_spend_reserve", {
    durationMs: Date.now() - startedAt,
    admitted: admission.ok,
    denialReason: admission.ok ? null : admission.reason,
    colo: requestColo(request),
  });
  return admission;
}
