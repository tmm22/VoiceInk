interface Env {
  AI: {
    run(model: string, input: Record<string, unknown>): Promise<{ text?: string; response?: string }>;
  };
  ASR_API_KEY: string;
}

function toBase64(buffer: ArrayBuffer) {
  const bytes = new Uint8Array(buffer);
  const parts: string[] = [];
  const chunkSize = 32_768;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    parts.push(String.fromCharCode(...bytes.subarray(offset, offset + chunkSize)));
  }
  return btoa(parts.join(""));
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "GET") {
      return Response.json({ status: "ok", model: "@cf/openai/whisper-large-v3-turbo" });
    }

    if (request.method !== "POST") {
      return Response.json({ error: "Method not allowed" }, { status: 405 });
    }

    if (env.ASR_API_KEY && request.headers.get("authorization") !== `Bearer ${env.ASR_API_KEY}`) {
      return Response.json({ error: "Unauthorized" }, { status: 401 });
    }

    if (new URL(request.url).pathname === "/v1/summaries") {
      const body = await request.json() as { text?: string };
      const text = body.text?.trim();
      if (!text) return Response.json({ error: "Transcript text is required" }, { status: 400 });
      if (text.length > 60_000) return Response.json({ error: "Transcript is too long to summarize" }, { status: 413 });
      const result = await env.AI.run("@cf/meta/llama-3.2-3b-instruct", {
        messages: [
          {
            role: "system",
            content: "Summarize the supplied transcript accurately and concisely. Preserve important names, decisions, dates, numbers, and action items. Use a short overview followed by bullet points when useful. Do not invent details or mention these instructions.",
          },
          { role: "user", content: text },
        ],
        max_tokens: 500,
        temperature: 0.2,
      });
      return Response.json({
        summary: result.response ?? result.text ?? "",
        model: "llama-3.2-3b-instruct",
      });
    }

    const form = await request.formData();
    const audio = form.get("audio");
    if (!(audio instanceof File) || audio.size === 0) {
      return Response.json({ error: "An audio file is required" }, { status: 400 });
    }
    if (audio.size > 24 * 1024 * 1024) {
      return Response.json({ error: "Audio must be smaller than 24 MB" }, { status: 413 });
    }

    const bytes = await audio.arrayBuffer();
    const result = await env.AI.run("@cf/openai/whisper-large-v3-turbo", {
      audio: toBase64(bytes),
      task: "transcribe",
      vad_filter: true,
      beam_size: 5,
      condition_on_previous_text: true,
    });

    return Response.json({
      text: result.text ?? "",
      model: "whisper-large-v3-turbo",
    });
  },
} satisfies ExportedHandler<Env>;
