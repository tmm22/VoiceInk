const securityHeaders: Record<string, string> = {
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "Permissions-Policy": "camera=(), microphone=(self), geolocation=(), payment=(), usb=()",
  "X-Frame-Options": "DENY",
};

const sensitiveResponseHeaders: Record<string, string> = {
  "Cache-Control": "private, no-store, max-age=0, must-revalidate",
  Pragma: "no-cache",
  Expires: "0",
};

// Early connection warm-up for the third-party origins the page will contact
// (Clerk FAPI ~300ms+ from AU; Turnstile challenge). Preconnect only — script
// preloads must stay out of Link headers because scripts are admitted by the
// per-request CSP nonce, which a Link-initiated fetch would not carry.
const documentLinkHeader = [
  "<https://clerk.paul.im>; rel=preconnect; crossorigin",
  "<https://challenges.cloudflare.com>; rel=preconnect",
].join(", ");

export function createNonce() {
  return btoa(crypto.randomUUID());
}

export function contentSecurityPolicy(nonce: string) {
  return `default-src 'self'; script-src 'nonce-${nonce}' 'strict-dynamic' https://challenges.cloudflare.com https://clerk.paul.im https://accounts.paul.im https://*.clerk.accounts.dev https://*.clerk.com; script-src-attr 'none'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https://img.clerk.com; font-src 'self'; connect-src 'self' https://*.clerk.accounts.dev https://*.clerk.com https://clerk.paul.im; media-src 'self' blob:; frame-src https://challenges.cloudflare.com https://*.clerk.accounts.dev https://*.clerk.com https://clerk.paul.im https://accounts.paul.im; worker-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self' https://*.clerk.accounts.dev https://clerk.paul.im https://accounts.paul.im; frame-ancestors 'none'; upgrade-insecure-requests`;
}

export function isApiPath(pathname: string) {
  return pathname === "/api" || pathname.startsWith("/api/");
}

// Applied to every response the Worker produces (the document, API routes and
// asset misses). Content-hashed static assets are served directly by the
// assets layer with their cache policy from public/_headers.
export function applySecurityHeaders(response: Response, pathname: string, nonce: string) {
  const secured = new Response(response.body, response);
  secured.headers.set("Content-Security-Policy", contentSecurityPolicy(nonce));
  for (const [name, value] of Object.entries(securityHeaders)) secured.headers.set(name, value);
  if (isApiPath(pathname)) {
    for (const [name, value] of Object.entries(sensitiveResponseHeaders)) secured.headers.set(name, value);
  } else {
    secured.headers.append("Link", documentLinkHeader);
  }
  return secured;
}
