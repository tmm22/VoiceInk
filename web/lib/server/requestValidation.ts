const noStoreHeaders = {
  "cache-control": "no-store",
  pragma: "no-cache",
  "x-content-type-options": "nosniff",
};

export function jsonNoStore(body: unknown, init: ResponseInit = {}) {
  const headers = new Headers(init.headers);
  for (const [name, value] of Object.entries(noStoreHeaders)) headers.set(name, value);
  return Response.json(body, { ...init, headers });
}

export function rejectCrossOrigin(request: Request) {
  const origin = request.headers.get("origin");
  const fetchSite = request.headers.get("sec-fetch-site")?.toLowerCase();
  if (fetchSite === "cross-site") {
    return jsonNoStore({ error: "Cross-origin requests are not allowed." }, { status: 403 });
  }
  if (!origin || origin === new URL(request.url).origin) return null;
  return jsonNoStore({ error: "Cross-origin requests are not allowed." }, { status: 403 });
}

export function rejectOversizedRequest(request: Request, maximumBytes: number) {
  const result = validateDeclaredBodySize(request, maximumBytes);
  return result.ok ? null : result.response;
}

export function validateJsonContentType(request: Request) {
  const contentType = request.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase();
  return contentType === "application/json"
    ? null
    : jsonNoStore({ error: "Content-Type must be application/json." }, { status: 415 });
}

export type DeclaredBodySizeValidation =
  | { ok: true; bytes: number }
  | { ok: false; response: Response };

export function validateDeclaredBodySize(
  request: Request,
  maximumBytes: number,
  headerName = "content-length",
): DeclaredBodySizeValidation {
  const value = request.headers.get(headerName);
  if (value === null) {
    return { ok: false, response: jsonNoStore({ error: "A declared request size is required." }, { status: 411 }) };
  }
  if (!/^[1-9]\d*$/.test(value)) {
    return { ok: false, response: jsonNoStore({ error: "The declared request size is invalid." }, { status: 400 }) };
  }
  const bytes = Number(value);
  if (!Number.isSafeInteger(bytes)) {
    return { ok: false, response: jsonNoStore({ error: "The declared request size is invalid." }, { status: 400 }) };
  }
  if (bytes > maximumBytes) {
    return { ok: false, response: jsonNoStore({ error: "Request body is too large." }, { status: 413 }) };
  }
  return { ok: true, bytes };
}

export type BoundedBodyResult<T> =
  | { ok: true; value: T }
  | { ok: false; response: Response };

export async function readBoundedText(request: Request, maximumBytes: number): Promise<BoundedBodyResult<string>> {
  const declared = validateDeclaredBodySize(request, maximumBytes);
  if (!declared.ok) return declared;
  const reader = request.body?.getReader();
  if (!reader) return { ok: false, response: jsonNoStore({ error: "A request body is required." }, { status: 400 }) };
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let received = 0;
  let text = "";
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      received += value.byteLength;
      if (received > maximumBytes) {
        await reader.cancel();
        return { ok: false, response: jsonNoStore({ error: "Request body is too large." }, { status: 413 }) };
      }
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
  } catch {
    return { ok: false, response: jsonNoStore({ error: "The request body is invalid." }, { status: 400 }) };
  }
  if (received !== declared.bytes) {
    return { ok: false, response: jsonNoStore({ error: "The declared request size does not match the body." }, { status: 400 }) };
  }
  return { ok: true, value: text };
}

export async function readBoundedJson<T>(request: Request, maximumBytes: number): Promise<BoundedBodyResult<T>> {
  const contentTypeError = validateJsonContentType(request);
  if (contentTypeError) return { ok: false, response: contentTypeError };
  const body = await readBoundedText(request, maximumBytes);
  if (!body.ok) return body;
  try {
    return { ok: true, value: JSON.parse(body.value) as T };
  } catch {
    return { ok: false, response: jsonNoStore({ error: "Valid JSON is required." }, { status: 400 }) };
  }
}

export type MultipartContentTypeValidation =
  | { ok: true; contentType: string }
  | { ok: false; response: Response };

export function validateMultipartContentType(request: Request): MultipartContentTypeValidation {
  const contentType = request.headers.get("content-type")?.trim() ?? "";
  const multipartWithBoundary = /^multipart\/form-data\s*;\s*boundary=(?:"[!#$%&'*+.^_`|~0-9A-Za-z-]{1,70}"|[!#$%&'*+.^_`|~0-9A-Za-z-]{1,70})$/i;
  if (!multipartWithBoundary.test(contentType)) {
    return {
      ok: false,
      response: jsonNoStore({ error: "A valid multipart audio upload is required." }, { status: 415 }),
    };
  }
  return { ok: true, contentType };
}
