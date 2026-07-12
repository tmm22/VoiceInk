import { env } from "cloudflare:workers";

export const runtime = "edge";

export async function POST(request: Request) {
  const endpoint = process.env.PARAKEET_API_URL;
  const apiKey = process.env.PARAKEET_API_KEY;
  const bindings = env as unknown as { ASR?: Fetcher };

  if (!endpoint) {
    await new Promise((resolve) => setTimeout(resolve, 900));
    return Response.json({
      text: "VoiceInk Web keeps the recording workflow focused: capture your voice, transcribe it with Parakeet, then copy or refine the result.",
      model: "whisper-large-v3-turbo",
      mode: "prototype",
    });
  }

  const formData = await request.formData();
  const target = `${endpoint.replace(/\/$/, "")}/v1/transcriptions`;
  const init: RequestInit = {
    method: "POST",
    headers: apiKey ? { Authorization: `Bearer ${apiKey}` } : undefined,
    body: formData,
  };
  const response = bindings.ASR
    ? await bindings.ASR.fetch(new Request(target, init))
    : await fetch(target, init);

  if (!response.ok) {
    return Response.json(
      { error: "Transcription inference failed", upstreamStatus: response.status },
      { status: 502 },
    );
  }

  return new Response(response.body, {
    status: 200,
    headers: { "content-type": response.headers.get("content-type") ?? "application/json" },
  });
}
