import { extractReadableArticle } from "../../../lib/imports/readability";
import { enforceRateLimit, jsonNoStore, readBoundedJson, rejectCrossOrigin } from "../../../lib/server/requestSecurity";

export const runtime = "edge";

const maximumBytes = 1_000_000;
const blockedHosts = new Set([
  "localhost",
  "metadata.google.internal",
  "169.254.169.254",
  "100.100.100.200",
]);

function isPrivateIPv4(hostname: string) {
  const parts = hostname.split(".").map(Number);
  if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) return false;
  const [first, second] = parts;
  return first === 10
    || first === 127
    || first === 0
    || (first === 169 && second === 254)
    || (first === 172 && second >= 16 && second <= 31)
    || (first === 192 && second === 168)
    || (first === 100 && second >= 64 && second <= 127)
    || (first === 192 && second === 0)
    || (first === 198 && (second === 18 || second === 19))
    || (first === 192 && second === 0 && parts[2] === 2)
    || (first === 198 && second === 51 && parts[2] === 100)
    || (first === 203 && second === 0 && parts[2] === 113)
    || first >= 224;
}

function isPrivateAddress(address: string) {
  const normalized = address.toLowerCase().replace(/^\[|\]$/g, "");
  if (isPrivateIPv4(normalized)) return true;
  return normalized === "::" || normalized === "::1" || normalized.startsWith("fc") || normalized.startsWith("fd")
    || /^fe[89ab]/.test(normalized) || normalized.startsWith("::ffff:10.") || normalized.startsWith("::ffff:127.")
    || normalized.startsWith("::ffff:192.168.") || /^::ffff:172\.(1[6-9]|2\d|3[01])\./.test(normalized);
}

async function assertPublicDns(hostname: string) {
  if (isPrivateAddress(hostname)) throw new Error("That address cannot be imported.");
  for (const type of ["A", "AAAA"]) {
    const response = await fetch(`https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(hostname)}&type=${type}`, {
      headers: { accept: "application/dns-json" },
      signal: AbortSignal.timeout(5_000),
    });
    if (!response.ok) throw new Error("The page address could not be verified.");
    const result = await response.json() as { Answer?: Array<{ data: string }> };
    if (result.Answer?.some((answer) => isPrivateAddress(answer.data))) throw new Error("That address cannot be imported.");
  }
}

function validateUrl(value: string) {
  const url = new URL(value);
  const hostname = url.hostname.toLowerCase();
  if (!['http:', 'https:'].includes(url.protocol)) throw new Error("Only HTTP and HTTPS URLs can be imported.");
  if (url.username || url.password) throw new Error("Page URLs cannot include credentials.");
  if (url.port && !((url.protocol === "http:" && url.port === "80") || (url.protocol === "https:" && url.port === "443"))) {
    throw new Error("That page uses an unsupported network port.");
  }
  if (hostname.includes(":") || /^\d+$/.test(hostname) || blockedHosts.has(hostname) || hostname.endsWith(".local") || hostname.endsWith(".internal") || isPrivateIPv4(hostname)) {
    throw new Error("That address cannot be imported.");
  }
  return url;
}

async function fetchWithSafeRedirects(initialUrl: URL) {
  let url = initialUrl;
  for (let redirect = 0; redirect <= 3; redirect += 1) {
    await assertPublicDns(url.hostname);
    const response = await fetch(url, {
      redirect: "manual",
      cache: "no-store",
      headers: {
        Accept: "text/html,application/xhtml+xml",
        "User-Agent": "VoiceInk-Web-Importer/1.0",
      },
      signal: AbortSignal.timeout(15_000),
    });
    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get("location");
      if (!location || redirect === 3) throw new Error("The page redirected too many times.");
      url = validateUrl(new URL(location, url).toString());
      continue;
    }
    return response;
  }
  throw new Error("The page could not be imported.");
}

export async function POST(request: Request) {
  try {
    const originError = rejectCrossOrigin(request);
    if (originError) return originError;
    const rateError = await enforceRateLimit(request, "IMPORT_RATE_LIMITER");
    if (rateError) return rateError;
    const parsed = await readBoundedJson<{ url?: unknown }>(request, 2_000);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    if (typeof body.url !== "string" || !body.url.trim()) return jsonNoStore({ error: "Enter a URL to import." }, { status: 400 });

    const response = await fetchWithSafeRedirects(validateUrl(body.url.trim()));
    if (!response.ok) return jsonNoStore({ error: "The page could not be imported." }, { status: 422 });
    const contentType = response.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase();
    if (contentType !== "text/html" && contentType !== "application/xhtml+xml") {
      return jsonNoStore({ error: "Only HTML pages can be imported." }, { status: 415 });
    }
    const declaredHeader = response.headers.get("content-length");
    if (declaredHeader !== null && (!/^\d+$/.test(declaredHeader) || Number(declaredHeader) > maximumBytes)) {
      return jsonNoStore({ error: "The page is too large to import." }, { status: 413 });
    }

    const reader = response.body?.getReader();
    if (!reader) return jsonNoStore({ error: "The page returned no content." }, { status: 422 });
    const chunks: Uint8Array[] = [];
    let received = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      received += value.byteLength;
      if (received > maximumBytes) {
        await reader.cancel();
        return jsonNoStore({ error: "The page is too large to import." }, { status: 413 });
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(received);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    const article = extractReadableArticle(new TextDecoder().decode(bytes));
    if (!article.content) return jsonNoStore({ error: "No readable article content was found." }, { status: 422 });
    return jsonNoStore(article);
  } catch (error) {
    const allowedMessages = new Set([
      "Only HTTP and HTTPS URLs can be imported.",
      "Page URLs cannot include credentials.",
      "That page uses an unsupported network port.",
      "That address cannot be imported.",
      "The page address could not be verified.",
      "The page redirected too many times.",
      "The page could not be imported.",
    ]);
    const message = error instanceof Error && allowedMessages.has(error.message)
      ? error.message
      : "The page could not be imported.";
    return jsonNoStore({ error: message }, { status: 400 });
  }
}
