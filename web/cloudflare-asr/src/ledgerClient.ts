import {
  DEFAULT_DAILY_CLIENT_AUDIO_SECONDS,
  DEFAULT_DAILY_SPEND_LIMIT_MICROS,
  parsePositiveIntegerSetting,
} from "./budget.ts";
import type { ReserveResult, SpendLedger } from "./spendLedger.ts";

export type LedgerEnv = {
  SPEND_LEDGER?: DurableObjectNamespace<SpendLedger>;
  DAILY_SPEND_LIMIT_MICROS?: string;
  DAILY_CLIENT_AUDIO_SECONDS?: string;
};

export type Admission =
  | { ok: true; id: string }
  | { ok: false; reason: "budget" | "client" | "unavailable" };

const LEDGER_CALL_TIMEOUT_MS = 3_000;

// The timer is cleared however the race settles, so a fast ledger call does
// not leave a pending timeout behind for every paid request.
export async function withTimeout<T>(operation: Promise<T>, timeoutMs = LEDGER_CALL_TIMEOUT_MS): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      operation,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error("Ledger timeout")), timeoutMs);
      }),
    ]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

function ledgerStub(env: LedgerEnv) {
  if (!env.SPEND_LEDGER) return null;
  return env.SPEND_LEDGER.get(env.SPEND_LEDGER.idFromName("global"));
}

// Any failure to reach the ledger is a denial: paid inference never runs
// without an admitted reservation.
export async function reserveSpend(
  env: LedgerEnv,
  request: { estimateMicros: number; secondsEstimate: number; clientKey: string },
): Promise<Admission> {
  const stub = ledgerStub(env);
  if (!stub) return { ok: false, reason: "unavailable" };
  try {
    const call = stub.reserve({
      ...request,
      spendLimitMicros: parsePositiveIntegerSetting(env.DAILY_SPEND_LIMIT_MICROS, DEFAULT_DAILY_SPEND_LIMIT_MICROS),
      clientSecondsLimit: parsePositiveIntegerSetting(env.DAILY_CLIENT_AUDIO_SECONDS, DEFAULT_DAILY_CLIENT_AUDIO_SECONDS),
    }) as unknown as Promise<ReserveResult>;
    const result = await withTimeout(call);
    if (result.ok) return { ok: true, id: result.id };
    return { ok: false, reason: result.reason };
  } catch {
    return { ok: false, reason: "unavailable" };
  }
}

export async function commitSpend(env: LedgerEnv, id: string, actualMicros: number, actualSeconds: number) {
  const stub = ledgerStub(env);
  if (!stub) return;
  try {
    await withTimeout(stub.commit(id, actualMicros, actualSeconds));
  } catch {
    // The reservation stands until expiry — spend is over-counted, never under.
  }
}

export async function releaseSpend(env: LedgerEnv, id: string) {
  const stub = ledgerStub(env);
  if (!stub) return;
  try {
    await withTimeout(stub.release(id));
  } catch {
    // Expiry reclaims the headroom.
  }
}
