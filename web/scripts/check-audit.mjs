import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const projectRoot = fileURLToPath(new URL("../", import.meta.url));
const severityRank = { info: 0, low: 1, moderate: 2, high: 3, critical: 4 };

// GHSA-vfj7-8cjw-p6xm has no patched braces release as of 2026-10-17.
// These exact paths only expand repository-controlled build/lint globs.
// Never extend this exception to runtime input or additional advisories.
const bracesExceptionExpiry = "2026-11-17";
const buildOnlyChain = {
  braces: { direct: false, via: ["https://github.com/advisories/GHSA-vfj7-8cjw-p6xm"], effects: ["micromatch"] },
  micromatch: { direct: false, via: ["braces"], effects: ["fast-glob"] },
  "fast-glob": { direct: false, via: ["micromatch"], effects: ["@next/eslint-plugin-next", "vite-plugin-dynamic-import"] },
  "@next/eslint-plugin-next": { direct: false, via: ["fast-glob"], effects: ["eslint-config-next"] },
  "eslint-config-next": { direct: true, via: ["@next/eslint-plugin-next"], effects: [] },
  "vite-plugin-dynamic-import": { direct: false, via: ["fast-glob"], effects: ["vite-plugin-commonjs"] },
  "vite-plugin-commonjs": { direct: false, via: ["vite-plugin-dynamic-import"], effects: ["vinext"] },
  vinext: { direct: true, via: ["vite-plugin-commonjs"], effects: [] },
};

function exactValues(actual, expected) {
  return Array.isArray(actual) && actual.length === expected.length
    && [...actual].sort().every((value, index) => value === [...expected].sort()[index]);
}

function isExactBuildChain(vulnerabilities) {
  return Object.entries(buildOnlyChain).every(([name, expected]) => {
    const finding = vulnerabilities[name];
    if (!finding || finding.severity !== "high" || finding.isDirect !== expected.direct) return false;
    const via = finding.via?.map((entry) => name === "braces"
      ? (typeof entry === "object" && entry?.name === "braces" ? entry.url : null)
      : entry);
    return exactValues(via, expected.via) && exactValues(finding.effects, expected.effects);
  });
}

export function evaluateAuditReport(report, { allowBuildBraces = false, today = new Date().toISOString().slice(0, 10) } = {}) {
  const blocked = [];
  const allowed = [];
  const vulnerabilities = report.vulnerabilities ?? {};
  const allowChain = allowBuildBraces && today <= bracesExceptionExpiry && isExactBuildChain(vulnerabilities);
  for (const [name, vulnerability] of Object.entries(vulnerabilities)) {
    if ((severityRank[vulnerability.severity] ?? -1) < severityRank.high) continue;
    if (allowChain && Object.hasOwn(buildOnlyChain, name)) allowed.push(name);
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
    web: { directory: projectRoot, allowBuildBraces: true },
    "cloudflare-asr": { directory: resolve(projectRoot, "cloudflare-asr"), allowBuildBraces: false },
  };
  const policy = targets[target];
  if (!policy) throw new Error(`Unknown audit target: ${target}`);

  const findings = evaluateAuditReport(runAudit(policy.directory), policy);
  if (findings.allowed.length) {
    console.warn(`Temporarily accepted build-only braces advisory chain until ${bracesExceptionExpiry}: ${findings.allowed.join(", ")}`);
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
