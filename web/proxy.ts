import { NextResponse, type NextRequest } from "next/server";

const securityHeaders: Record<string, string> = {
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Permissions-Policy": "camera=(), microphone=(self), geolocation=(), payment=(), usb=()",
  "X-Frame-Options": "DENY",
};

export function proxy(request: NextRequest) {
  const nonce = btoa(crypto.randomUUID());
  const contentSecurityPolicy = `default-src 'self'; script-src 'nonce-${nonce}' 'strict-dynamic' https: http:; style-src 'self' 'unsafe-inline'; img-src 'self' data: https://img.clerk.com; font-src 'self'; connect-src 'self' https://*.convex.cloud wss://*.convex.cloud https://*.clerk.accounts.dev https://*.clerk.com https://clerk.paul.im; media-src 'self' blob:; frame-src https://*.clerk.accounts.dev https://*.clerk.com https://clerk.paul.im https://accounts.paul.im; worker-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self' https://*.clerk.accounts.dev https://clerk.paul.im https://accounts.paul.im; frame-ancestors 'none'; upgrade-insecure-requests`;
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("Content-Security-Policy", contentSecurityPolicy);
  requestHeaders.set("x-nonce", nonce);
  const response = NextResponse.next({ request: { headers: requestHeaders } });
  response.headers.set("Content-Security-Policy", contentSecurityPolicy);
  for (const [name, value] of Object.entries(securityHeaders)) response.headers.set(name, value);
  return response;
}

export const config = { matcher: "/:path*" };
