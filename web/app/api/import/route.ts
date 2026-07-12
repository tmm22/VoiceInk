import { extractReadableArticle } from "../../../lib/imports/readability";
import { enforceRateLimit, rejectCrossOrigin } from "../../../lib/server/requestSecurity";

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
    || (first === 100 && second >= 64 && second <= 127);
}

function validateUrl(value: string) {
  const url = new URL(value);
  const hostname = url.hostname.toLowerCase();
  if (!['http:', 'https:'].includes(url.protocol)) throw new Error("Only HTTP and HTTPS URLs can be imported.");
  if (hostname.includes(":") || /^\d+$/.test(hostname) || blockedHosts.has(hostname) || hostname.endsWith(".local") || hostname.endsWith(".internal") || isPrivateIPv4(hostname)) {
    throw new Error("That address cannot be imported.");
  }
  return url;
}

async function fetchWithSafeRedirects(initialUrl: URL) {
  let url = initialUrl;
  for (let redirect = 0; redirect <= 3; redirect += 1) {
    const response = await fetch(url, {
      redirect: "manual",
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
    const body = await request.json() as { url?: string };
    if (!body.url?.trim()) return Response.json({ error: "Enter a URL to import." }, { status: 400 });

    const response = await fetchWithSafeRedirects(validateUrl(body.url.trim()));
    if (!response.ok) return Response.json({ error: `The page returned ${response.status}.` }, { status: 422 });
    const declaredSize = Number(response.headers.get("content-length") ?? 0);
    if (declaredSize > maximumBytes) return Response.json({ error: "The page is too large to import." }, { status: 413 });

    const bytes = await response.arrayBuffer();
    if (bytes.byteLength > maximumBytes) return Response.json({ error: "The page is too large to import." }, { status: 413 });
    const article = extractReadableArticle(new TextDecoder().decode(bytes));
    if (!article.content) return Response.json({ error: "No readable article content was found." }, { status: 422 });
    return Response.json(article);
  } catch (error) {
    const message = error instanceof Error ? error.message : "The page could not be imported.";
    return Response.json({ error: message }, { status: 400 });
  }
}
