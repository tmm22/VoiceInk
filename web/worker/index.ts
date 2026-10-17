/**
 * Worker entry point for local development (vite.config.ts) and the
 * production build (dist/server/index.js).
 *
 * Content-hashed assets and public files are served by the Workers assets
 * layer without invoking this Worker. It runs for the document ("/", listed in
 * wrangler.production.jsonc `run_worker_first`), the API routes, and asset
 * misses, and every response it produces carries the security headers.
 */
import * as enhance from "../app/api/enhance/route";
import * as history from "../app/api/history/route";
import * as importContent from "../app/api/import/route";
import * as summarize from "../app/api/summarize/route";
import * as transcribe from "../app/api/transcribe/route";
import { jsonNoStore } from "../lib/server/requestValidation";
import { applySecurityHeaders, createNonce, isApiPath } from "./securityHeaders";

type Env = { ASSETS: Fetcher };
type RouteHandler = (request: Request) => Promise<Response>;
type RouteModule = Partial<Record<"GET" | "POST" | "PATCH" | "DELETE", RouteHandler>>;

const apiRoutes: Record<string, RouteModule> = {
  "/api/enhance": enhance,
  "/api/history": history,
  "/api/import": importContent,
  "/api/summarize": summarize,
  "/api/transcribe": transcribe,
};

const HTTP_METHODS = ["GET", "POST", "PATCH", "DELETE"] as const;

function allowedMethods(route: RouteModule) {
  const methods: string[] = HTTP_METHODS.filter((method) => typeof route[method] === "function");
  if (route.GET) methods.push("HEAD");
  return [...methods, "OPTIONS"].join(", ");
}

async function handleApi(request: Request, pathname: string): Promise<Response> {
  const route = apiRoutes[pathname];
  if (!route) return jsonNoStore({ error: "Not found." }, { status: 404 });
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: { Allow: allowedMethods(route) } });
  }
  const method = request.method === "HEAD" ? "GET" : request.method;
  const handler = route[method as keyof RouteModule];
  if (!handler) {
    return jsonNoStore({ error: "Method not allowed." }, { status: 405, headers: { Allow: allowedMethods(route) } });
  }
  try {
    const response = await handler(request);
    return request.method === "HEAD" ? new Response(null, response) : response;
  } catch (error) {
    // Route handlers return their own bounded errors; this only catches an
    // unexpected throw. Log metadata, never request or provider content.
    console.error("voiceink_route_unhandled_error", {
      route: pathname,
      method: request.method,
      errorName: error instanceof Error ? error.name : "unknown",
    });
    return jsonNoStore({ error: "Something went wrong. Please try again." }, { status: 500 });
  }
}

// The prerendered shell is a static asset, but scripts are admitted only by a
// per-request CSP nonce, so the Worker stamps a fresh nonce onto every script
// and module preload before the document leaves the edge. It is never cached.
async function serveDocument(request: Request, env: Env, nonce: string): Promise<Response> {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed.", { status: 405, headers: { Allow: "GET, HEAD" } });
  }
  const shell = await env.ASSETS.fetch(new Request(new URL("/", request.url)));
  if (!shell.ok) return new Response("Service unavailable.", { status: 503 });
  const headers = new Headers({
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store, must-revalidate",
  });
  if (request.method === "HEAD") return new Response(null, { headers });
  const stampNonce = { element: (element: Element) => { element.setAttribute("nonce", nonce); } };
  const stamped = new HTMLRewriter()
    .on("script", stampNonce)
    .on('link[rel="modulepreload"]', stampNonce)
    .transform(shell);
  return new Response(stamped.body, { headers });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const { pathname } = new URL(request.url);
    const nonce = createNonce();
    let response: Response;
    if (isApiPath(pathname)) response = await handleApi(request, pathname);
    else if (pathname === "/" || pathname === "/index.html") response = await serveDocument(request, env, nonce);
    else response = await env.ASSETS.fetch(request);
    return applySecurityHeaders(response, pathname, nonce);
  },
} satisfies ExportedHandler<Env>;
