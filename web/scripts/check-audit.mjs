import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const projectRoot = fileURLToPath(new URL("../", import.meta.url));
const severityRank = { info: 0, low: 1, moderate: 2, high: 3, critical: 4 };

// Any high or critical advisory fails the gate; there are no exceptions. When
// an advisory has no patched release, remove or replace the dependency instead
// of allowlisting it (the unpatched braces chain left the tree when its
// dependents, vinext and the Next.js lint plugin, were removed).
export function evaluateAuditReport(report) {
  const blocked = Object.entries(report.vulnerabilities ?? {})
    .filter(([, vulnerability]) => (severityRank[vulnerability.severity] ?? -1) >= severityRank.high)
    .map(([name]) => name);
  return { blocked: blocked.sort() };
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
    web: projectRoot,
    "cloudflare-asr": resolve(projectRoot, "cloudflare-asr"),
  };
  const directory = targets[target];
  if (!directory) throw new Error(`Unknown audit target: ${target}`);

  const findings = evaluateAuditReport(runAudit(directory));
  if (findings.blocked.length) {
    console.error(`High or critical npm advisories found in ${target}: ${findings.blocked.join(", ")}`);
    process.exitCode = 1;
    return;
  }
  console.log(`No high or critical npm advisories found in ${target}.`);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main();
}
