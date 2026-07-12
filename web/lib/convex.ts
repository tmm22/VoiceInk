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

function convexClient(token?: string | null) {
  if (!convexUrl) return null;
  const client = new ConvexHttpClient(convexUrl);
  if (token) client.setAuth(token);
  return client;
}

export async function saveTranscription(value: SavedTranscription, token?: string | null) {
  if (!convexUrl || typeof window === "undefined") return;
  const client = convexClient(token);
  if (!client) return;
  const save = makeFunctionReference<"mutation">("transcriptions:save");
  await client.mutation(save, { ...value, clientId: clientId() });
}

export async function listTranscriptions(token?: string | null): Promise<TranscriptionHistoryItem[]> {
  if (!convexUrl || typeof window === "undefined") return [];
  const client = convexClient(token);
  if (!client) return [];
  const list = makeFunctionReference<"query">("transcriptions:list");
  return client.query(list, { clientId: clientId() }) as Promise<TranscriptionHistoryItem[]>;
}

export async function deleteTranscription(id: string, token?: string | null) {
  if (!convexUrl || typeof window === "undefined") return;
  const client = convexClient(token);
  if (!client) return;
  const remove = makeFunctionReference<"mutation">("transcriptions:remove");
  await client.mutation(remove, { id, clientId: clientId() });
}
