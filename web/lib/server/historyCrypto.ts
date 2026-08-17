// Envelope encryption for history fields stored in Convex. Pure Web-API module
// (no cloudflare:workers import) so the logic stays unit-testable in Node.
//
// Envelope: "$venc1$" + base64(salt[16] || iv[12] || AES-256-GCM ciphertext).
// Each record derives its own AES-256 key from the worker-held
// HISTORY_ENCRYPTION_KEY via HKDF-SHA-256 with a random per-record salt. The
// HKDF info binds BOTH the field name and the record's ownership context
// (`o:<clerk-subject>` or `a:<clientId>`), so an envelope can never be replayed
// into a different field, a different record, or another user's row and still
// open: an attacker with Convex write access who transplants a victim's
// ciphertext into a row they can read decrypts to garbage because the context
// reconstructed from the authenticated request does not match. Convex stores
// only envelopes; the key never leaves the web Worker.

const ENVELOPE_PREFIX = "$venc1$";
const SALT_BYTES = 16;
const IV_BYTES = 12;
const GCM_TAG_BYTES = 16;
const KEY_BYTES = 32;
const MINIMUM_ENVELOPE_BYTES = SALT_BYTES + IV_BYTES + GCM_TAG_BYTES;
const HKDF_INFO_PREFIX = "voiceink-history:";
const BASE64_BODY = /^[A-Za-z0-9+/]+={0,2}$/;

export type HistoryField = "text" | "summary";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let index = 0; index < bytes.length; index += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(index, index + 0x8000));
  }
  return btoa(binary);
}

function fromBase64(value: string): Uint8Array<ArrayBuffer> {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

// A value is only treated as an encrypted envelope when the body is well-formed
// base64 that decodes to at least a salt+iv+tag. This keeps a pre-encryption
// plaintext transcript that merely happens to start with the prefix literal
// from being mistaken for ciphertext (which would throw on decrypt).
export function isEncryptedEnvelope(value: string): boolean {
  if (!value.startsWith(ENVELOPE_PREFIX)) return false;
  const body = value.slice(ENVELOPE_PREFIX.length);
  if (!BASE64_BODY.test(body)) return false;
  const padding = body.endsWith("==") ? 2 : body.endsWith("=") ? 1 : 0;
  return Math.floor((body.length * 3) / 4) - padding >= MINIMUM_ENVELOPE_BYTES;
}

export async function importHistoryKey(base64Key: string): Promise<CryptoKey> {
  const raw = fromBase64(base64Key.trim());
  if (raw.length !== KEY_BYTES) throw new Error("The history encryption key must be exactly 32 bytes.");
  return crypto.subtle.importKey("raw", raw, "HKDF", false, ["deriveKey", "deriveBits"]);
}

// Caches the imported key across requests in the same isolate; re-imports only
// if the configured secret value changes.
let cachedKey: { source: string; key: Promise<CryptoKey> } | null = null;
export function loadHistoryKey(secret: string | undefined): Promise<CryptoKey> | null {
  if (!secret) return null;
  if (!cachedKey || cachedKey.source !== secret) cachedKey = { source: secret, key: importHistoryKey(secret) };
  return cachedKey.key;
}

// The ownership context bound into every derivation. `o:` is the verified Clerk
// subject for account rows; `a:` is the anonymous browser clientId. Both are
// values the read path reconstructs from the authenticated request, never from
// the stored row.
export function ownerContext(clerkSubject: string): string {
  return `o:${clerkSubject}`;
}
export function anonymousContext(clientId: string): string {
  return `a:${clientId}`;
}

function hkdfBitsParams(salt: Uint8Array<ArrayBuffer>, info: string) {
  return { name: "HKDF", hash: "SHA-256", salt, info: encoder.encode(info) } as const;
}

async function deriveFieldKey(key: CryptoKey, salt: Uint8Array<ArrayBuffer>, field: HistoryField, context: string): Promise<CryptoKey> {
  return crypto.subtle.deriveKey(
    hkdfBitsParams(salt, `${HKDF_INFO_PREFIX}${field}|${context}`),
    key,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

export async function encryptHistoryField(key: CryptoKey, field: HistoryField, context: string, plaintext: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(SALT_BYTES));
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));
  const fieldKey = await deriveFieldKey(key, salt, field, context);
  const ciphertext = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, fieldKey, encoder.encode(plaintext)));
  const envelope = new Uint8Array(SALT_BYTES + IV_BYTES + ciphertext.length);
  envelope.set(salt, 0);
  envelope.set(iv, SALT_BYTES);
  envelope.set(ciphertext, SALT_BYTES + IV_BYTES);
  return ENVELOPE_PREFIX + toBase64(envelope);
}

export async function decryptHistoryField(key: CryptoKey, field: HistoryField, context: string, envelope: string): Promise<string> {
  if (!envelope.startsWith(ENVELOPE_PREFIX)) throw new Error("The value is not an encrypted history envelope.");
  const bytes = fromBase64(envelope.slice(ENVELOPE_PREFIX.length));
  if (bytes.length < MINIMUM_ENVELOPE_BYTES) throw new Error("The encrypted history envelope is truncated.");
  const fieldKey = await deriveFieldKey(key, bytes.subarray(0, SALT_BYTES) as Uint8Array<ArrayBuffer>, field, context);
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: bytes.subarray(SALT_BYTES, SALT_BYTES + IV_BYTES) },
    fieldKey,
    bytes.subarray(SALT_BYTES + IV_BYTES),
  );
  return decoder.decode(plaintext);
}

// Keyed digest for idempotency comparison: Convex can detect operation-id reuse
// with different content without ever seeing plaintext. The operationId is
// bound into the derivation so identical transcripts in different records
// produce different digests — Convex cannot use the digest to correlate equal
// content across users or records. Keyed (not a plain hash) so stored digests
// cannot confirm guesses of short transcripts.
export async function historyTextDigest(key: CryptoKey, operationId: string, text: string): Promise<string> {
  const bits = await crypto.subtle.deriveBits(hkdfBitsParams(new Uint8Array(SALT_BYTES), `${HKDF_INFO_PREFIX}dedupe:${operationId}`), key, 256);
  const macKey = await crypto.subtle.importKey("raw", bits, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return toBase64(new Uint8Array(await crypto.subtle.sign("HMAC", macKey, encoder.encode(text))));
}
