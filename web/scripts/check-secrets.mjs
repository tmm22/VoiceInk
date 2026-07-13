import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const tracked = execFileSync("git", ["ls-files", "-z"], { cwd: new URL("../../", import.meta.url), encoding: "utf8" }).split("\0").filter(Boolean);
const forbiddenFiles = tracked.filter((file) => /(^|\/)\.env($|\.)|(^|\/)\.dev\.vars$/.test(file));
const patterns = [
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
  /\bsk_live_[A-Za-z0-9_-]+/,
  /\b(?:CLOUDFLARE_API_TOKEN|CLERK_SECRET_KEY|CONVEX_DEPLOY_KEY|CONVEX_WEB_API_SECRET|ASR_API_KEY)\s*=\s*[^<\s]/,
];
const leaks = [];
for (const file of tracked) {
  if (file.endsWith("package-lock.json")) continue;
  let content;
  try { content = readFileSync(new URL(`../../${file}`, import.meta.url), "utf8"); } catch { continue; }
  if (patterns.some((pattern) => pattern.test(content))) leaks.push(file);
}
if (forbiddenFiles.length || leaks.length) {
  console.error("Potential tracked secret material:", [...new Set([...forbiddenFiles, ...leaks])].join(", "));
  process.exit(1);
}
console.log(`Secret regression scan passed across ${tracked.length} tracked files.`);
