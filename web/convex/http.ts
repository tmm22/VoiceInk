import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { timingSafeEqualStrings } from "./serviceAuth";

// Clerk account-deletion webhook: when a Clerk user is deleted, purge every
// Convex row keyed to that identity so no orphaned transcript ciphertext
// outlives the account. Signature verification follows the Svix scheme
// (HMAC-SHA-256 over "id.timestamp.payload" with the whsec_ base64 secret)
// implemented directly so no webhook dependency is added.

const TIMESTAMP_TOLERANCE_SECONDS = 300;
const MAXIMUM_PAYLOAD_BYTES = 100_000;

const http = httpRouter();

http.route({
  path: "/clerk-users-webhook",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const secret = process.env.CLERK_WEBHOOK_SECRET;
    const issuer = process.env.CLERK_JWT_ISSUER_DOMAIN;
    if (!secret || !issuer) return new Response("Webhook is not configured.", { status: 503 });
    const payload = await request.text();
    if (payload.length > MAXIMUM_PAYLOAD_BYTES) return new Response("Payload too large.", { status: 413 });
    if (!(await hasValidSvixSignature(request.headers, payload, secret))) {
      return new Response("Invalid signature.", { status: 401 });
    }
    let event: { type?: unknown; data?: { id?: unknown } };
    try {
      event = JSON.parse(payload) as typeof event;
    } catch {
      return new Response("Invalid payload.", { status: 400 });
    }
    if (event.type === "user.deleted" && typeof event.data?.id === "string" && event.data.id) {
      // Convex token identifiers are "<issuer>|<subject>".
      await ctx.scheduler.runAfter(0, internal.cleanup.purgeHistoryPage, {
        ownerId: `${issuer}|${event.data.id}`,
        removeSettings: true,
      });
    }
    return new Response(null, { status: 200 });
  }),
});

async function hasValidSvixSignature(headers: Headers, payload: string, secret: string): Promise<boolean> {
  const id = headers.get("svix-id");
  const timestamp = headers.get("svix-timestamp");
  const signatures = headers.get("svix-signature");
  if (!id || !timestamp || !signatures || signatures.length > 4_096) return false;
  const timestampSeconds = Number(timestamp);
  if (!Number.isFinite(timestampSeconds) || Math.abs(Date.now() / 1000 - timestampSeconds) > TIMESTAMP_TOLERANCE_SECONDS) {
    return false;
  }
  let secretBytes: Uint8Array<ArrayBuffer>;
  try {
    const binary = atob(secret.replace(/^whsec_/, ""));
    secretBytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) secretBytes[index] = binary.charCodeAt(index);
  } catch {
    return false;
  }
  const key = await crypto.subtle.importKey("raw", secretBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${id}.${timestamp}.${payload}`)));
  let binary = "";
  for (const byte of mac) binary += String.fromCharCode(byte);
  const expected = btoa(binary);
  return signatures.split(" ").some((entry) => {
    const [version, value] = entry.split(",");
    return version === "v1" && value !== undefined && timingSafeEqualStrings(value, expected);
  });
}

export default http;
