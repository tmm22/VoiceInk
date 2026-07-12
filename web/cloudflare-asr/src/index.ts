interface Env {
  AI: {
    run(model: string, input: Record<string, unknown>): Promise<{ text?: string }>;
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
