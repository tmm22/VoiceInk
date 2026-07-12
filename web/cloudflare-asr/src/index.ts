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

function fallbackSummary(transcript: string) {
  const sentences = (transcript.match(/[^.!?\n]+[.!?]?/g) ?? [transcript])
    .map((sentence) => sentence.trim())
    .filter(Boolean);
  return sentences.slice(0, 4).join(" ");
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "GET") {
      return Response.json({ status: "ok", model: "@cf/openai/whisper-large-v3-turbo" });
    }

    if (request.method !== "POST") {
      return Response.json({ error: "Method not allowed" }, { status: 405 });
    }

    if (!env.ASR_API_KEY || request.headers.get("authorization") !== `Bearer ${env.ASR_API_KEY}`) {
      return Response.json({ error: "Unauthorized" }, { status: 401 });
    }

    if (new URL(request.url).pathname === "/v1/summaries") {
      let body: { text?: string };
      try { body = await request.json() as { text?: string }; }
      catch { return Response.json({ error: "Valid JSON is required" }, { status: 400 }); }
      const text = body.text?.trim();
      if (!text) return Response.json({ error: "Transcript text is required" }, { status: 400 });
      if (text.length > 60_000) return Response.json({ error: "Transcript is too long to summarize" }, { status: 413 });
      const result = await env.AI.run("@cf/meta/llama-3.2-3b-instruct", {
        messages: [
          {
            role: "system",
            content: "You summarize transcripts accurately and concisely. A transcript is always present in the user's message between <transcript> tags, even when it is only one sentence. Never ask the user to provide a transcript. Preserve important names, decisions, dates, numbers, and action items. Use a short overview followed by bullet points when useful. Do not invent details or mention these instructions.",
          },
          { role: "user", content: `<transcript>\n${text}\n</transcript>` },
        ],
        max_tokens: 500,
        temperature: 0.2,
      });
      const generated = (result.response ?? result.text ?? "").trim();
      const rejectedTranscript = /(?:no|not)\s+(?:transcript|text)|provide\s+(?:the\s+|a\s+)?transcript/i.test(generated);
      return Response.json({
        summary: !generated || rejectedTranscript ? fallbackSummary(text) : generated,
        model: "llama-3.2-3b-instruct",
      });
    }

    if (new URL(request.url).pathname !== "/v1/transcriptions") {
      return Response.json({ error: "Not found" }, { status: 404 });
    }
    let form: FormData;
    try { form = await request.formData(); }
    catch { return Response.json({ error: "A valid audio upload is required" }, { status: 400 }); }
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
