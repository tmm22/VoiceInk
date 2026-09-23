// The shared credential the web Worker presents to the private ASR Worker,
// which checks the same value as its own ASR_API_KEY.
export function asrApiKey(): string | undefined {
  return process.env.ASR_API_KEY || undefined;
}
