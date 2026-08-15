import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const projectRoot = fileURLToPath(new URL("../", import.meta.url));
const severityRank = { info: 0, low: 1, moderate: 2, high: 3, critical: 4 };

// Vinext currently constrains image-size to a release affected by these two
// parser DoS advisories. The production app never passes user-controlled ICNS,
// JXL, or HEIF files to Vinext's build-time image inspection. Keep this narrow:
// exact package, exact advisory URLs, exact propagated dependency, and expiry.
const imageSizeException = {
  expires: "2026-09-15",
  urls: new Set([
    "https://github.com/advisories/GHSA-w3rx-r6r6-pgpr",
    "https://github.com/advisories/GHSA-5p2g-fcmc-qvqq",
  ]),
};

function isAllowedImageSizeFinding(name, vulnerability, today) {
  if (today > imageSizeException.expires) return false;
  if (name === "image-size") {
    const advisoryUrls = vulnerability.via
      .filter((entry) => typeof entry === "object" && entry !== null)
      .map((entry) => entry.url);
    return vulnerability.isDirect === false
      && advisoryUrls.length === imageSizeException.urls.size
      && advisoryUrls.every((url) => imageSizeException.urls.has(url))
      && vulnerability.via.every((entry) => typeof entry === "object" && entry !== null)
      && vulnerability.effects.length === 1
      && vulnerability.effects[0] === "vinext";
  }
  return name === "vinext"
    && vulnerability.isDirect === true
    && vulnerability.via.length === 1
    && vulnerability.via[0] === "image-size"
    && vulnerability.effects.length === 0;
}

export function evaluateAuditReport(report, { allowImageSize = false, today = new Date().toISOString().slice(0, 10) } = {}) {
  const blocked = [];
  const allowed = [];
  for (const [name, vulnerability] of Object.entries(report.vulnerabilities ?? {})) {
    if ((severityRank[vulnerability.severity] ?? -1) < severityRank.high) continue;
    if (allowImageSize && isAllowedImageSizeFinding(name, vulnerability, today)) allowed.push(name);
    else blocked.push(name);
  }
  return { allowed: allowed.sort(), blocked: blocked.sort() };
}

function runAudit(directory) {
  const npmCommand = process.platform === "win32" ? "npm.cmd" : "npm";
  const result = spawnSync(npmCommand, ["audit", "--json"], {
    cwd: directory,
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  try {
    return JSON.parse(result.stdout);
  } catch {
    throw new Error(`npm audit did not return valid JSON: ${result.stderr || result.stdout}`);
  }
}

function main() {
  const target = process.argv[2] ?? "web";
  const targets = {
    web: { directory: projectRoot, allowImageSize: true },
    "cloudflare-asr": { directory: resolve(projectRoot, "cloudflare-asr"), allowImageSize: false },
  };
  const policy = targets[target];
  if (!policy) throw new Error(`Unknown audit target: ${target}`);

  const findings = evaluateAuditReport(runAudit(policy.directory), policy);
  if (findings.allowed.length) {
    console.warn(`Temporarily accepted exact image-size advisory chain until ${imageSizeException.expires}: ${findings.allowed.join(", ")}`);
  }
  if (findings.blocked.length) {
    console.error(`High or critical npm advisories found in ${target}: ${findings.blocked.join(", ")}`);
    process.exitCode = 1;
    return;
  }
  console.log(`No unapproved high or critical npm advisories found in ${target}.`);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main();
}
