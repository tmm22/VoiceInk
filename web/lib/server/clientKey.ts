// Day-rotating pseudonymous client key for the ASR spend ledger. The ledger
// only needs "same caller, same UTC day" to enforce quotas — never the
// caller's network address — so the IP is HMAC'd with a server-held secret and
// the UTC day before it leaves the web Worker. The secret MUST be one the ASR
// Worker never holds (the callers pass HISTORY_ENCRYPTION_KEY, a web-Worker-only
// value), otherwise the party that stores the pseudonyms would also hold the
// key to reverse them. Stored quota rows are meaningless on their own and
// unlinkable across days. Pure Web-API module so it stays unit-testable in Node.

const encoder = new TextEncoder();

function utcDay(now: number): string {
  return new Date(now).toISOString().slice(0, 10);
}

export async function pseudonymousClientKey(secret: string, ip: string | null, now: number): Promise<string> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const message = `voiceink-client-key-v1:${utcDay(now)}:${ip ?? "unknown"}`;
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(message)));
  let binary = "";
  for (const byte of mac.subarray(0, 16)) binary += String.fromCharCode(byte);
  return "k1:" + btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}
