// Constant-time service-secret check shared by every Convex function the web
// Worker calls. A plain !== comparison can leak the matching prefix length
// through timing; this comparison always inspects every character.

export function timingSafeEqualStrings(a: string, b: string): boolean {
  let mismatch = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let index = 0; index < length; index += 1) {
    mismatch |= (a.charCodeAt(index) || 0) ^ (b.charCodeAt(index) || 0);
  }
  return mismatch === 0;
}

export function requireServiceSecret(value?: string) {
  const expected = process.env.CONVEX_WEB_API_SECRET;
  if (!expected || typeof value !== "string" || !timingSafeEqualStrings(value, expected)) {
    throw new Error("This operation must use the protected web service.");
  }
}
