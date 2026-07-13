export function rejectCrossOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin === new URL(request.url).origin) return null;
  return Response.json({ error: "Cross-origin requests are not allowed." }, { status: 403 });
}

export function rejectOversizedRequest(request: Request, maximumBytes: number) {
  const declared = Number(request.headers.get("content-length") ?? 0);
  return declared > maximumBytes
    ? Response.json({ error: "Request body is too large." }, { status: 413 })
    : null;
}
