type SavedTranscription = {
  text: string;
  durationSeconds: number;
  model: string;
};

export type RetentionDays = 0 | 7 | 30 | 90 | 365;

export type TranscriptionHistoryItem = SavedTranscription & {
  _id: string;
  summary?: string;
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

export async function saveTranscription(value: SavedTranscription, token?: string | null) {
  if (!convexUrl || typeof window === "undefined") return;
  const response = await fetch("/api/history", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ ...value, clientId: clientId() }),
  });
  if (!response.ok) throw new Error("History could not be saved.");
  const result = await response.json() as { id: string };
  return result.id;
}

export async function listTranscriptions(token?: string | null): Promise<TranscriptionHistoryItem[]> {
  if (!convexUrl || typeof window === "undefined") return [];
  const response = await fetch(`/api/history?clientId=${encodeURIComponent(clientId())}`, { headers: token ? { authorization: `Bearer ${token}` } : {} });
  if (!response.ok) throw new Error("History could not be loaded.");
  return ((await response.json()) as { items: TranscriptionHistoryItem[] }).items;
}

export async function deleteTranscription(id: string, token?: string | null) {
  if (!convexUrl || typeof window === "undefined") return;
  const response = await fetch(`/api/history?id=${encodeURIComponent(id)}&clientId=${encodeURIComponent(clientId())}`, { method: "DELETE", headers: token ? { authorization: `Bearer ${token}` } : {} });
  if (!response.ok) throw new Error("History item could not be deleted.");
}

export async function saveTranscriptionSummary(id: string, summary: string, token?: string | null) {
  if (!convexUrl || typeof window === "undefined") return;
  const response = await fetch("/api/history", { method: "PATCH", headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify({ id, summary, clientId: clientId() }) });
  if (!response.ok) throw new Error("Summary could not be saved.");
}

export async function getRetention(token?: string | null): Promise<RetentionDays | null> {
  if (!convexUrl || typeof window === "undefined" || !token) return null;
  const response = await fetch(`/api/history?clientId=${encodeURIComponent(clientId())}`, { headers: { authorization: `Bearer ${token}` } });
  if (!response.ok) return null;
  return ((await response.json()) as { retentionDays: RetentionDays | null }).retentionDays;
}

export async function setRetention(days: RetentionDays, token?: string | null) {
  if (!convexUrl || typeof window === "undefined" || !token) return;
  const response = await fetch("/api/history", { method: "PATCH", headers: { "content-type": "application/json", authorization: `Bearer ${token}` }, body: JSON.stringify({ action: "retention", days }) });
  if (!response.ok) throw new Error("Retention could not be updated.");
}
