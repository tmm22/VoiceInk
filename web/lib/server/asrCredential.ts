// The shared credential the web Worker presents to the private ASR Worker,
// which checks the same value as its own ASR_API_KEY. PARAKEET_API_KEY is the
// secret's pre-rename name, read for one release so production keeps working
// until ASR_API_KEY is installed on the web Worker; remove the fallback (and
// the old secret) in the release after that.
export function asrApiKey(): string | undefined {
  return process.env.ASR_API_KEY || process.env.PARAKEET_API_KEY || undefined;
}
