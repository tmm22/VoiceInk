import { ConvexHttpClient } from "convex/browser";
import { makeFunctionReference } from "convex/server";

type SavedTranscription = {
  text: string;
  durationSeconds: number;
  model: string;
};

export type TranscriptionHistoryItem = SavedTranscription & {
  _id: string;
  status: "processing" | "complete" | "failed";
  createdAt: number;
};

const convexUrl = process.env.NEXT_PUBLIC_CONVEX_URL;

function clientId() {
  const key = "voiceink-client-id";
  const existing = window.localStorage.getItem(key);
  if (existing) return existing;
  const created = crypto.randomUUID();
  window.localStorage.setItem(key, created);
  return created;
}

export async function saveTranscription(value: SavedTranscription) {
  if (!convexUrl || typeof window === "undefined") return;
  const client = new ConvexHttpClient(convexUrl);
  const save = makeFunctionReference<"mutation">("transcriptions:save");
  await client.mutation(save, { ...value, clientId: clientId() });
}

export async function listTranscriptions(): Promise<TranscriptionHistoryItem[]> {
  if (!convexUrl || typeof window === "undefined") return [];
  const client = new ConvexHttpClient(convexUrl);
  const list = makeFunctionReference<"query">("transcriptions:list");
  return client.query(list, { clientId: clientId() }) as Promise<TranscriptionHistoryItem[]>;
}
