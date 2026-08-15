import { readFile, readdir } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const productionRoots = ["app", "lib", "shared", "convex", "cloudflare-asr/src", "tooling"];
const maximumLines = 500;

async function sourceFiles(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.name === "_generated") continue;
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) files.push(...await sourceFiles(path));
    else if (/\.(?:ts|tsx|mts)$/.test(entry.name)) files.push(path);
  }
  return files;
}

const violations = [];
for (const directory of productionRoots) {
  for (const file of await sourceFiles(resolve(root, directory))) {
    const lines = (await readFile(file, "utf8")).split(/\r?\n/).length - 1;
    if (lines > maximumLines) violations.push(`${file}: ${lines} lines`);
  }
}
if (violations.length) {
  console.error(`Production TypeScript files must stay at or below ${maximumLines} lines:`);
  for (const violation of violations) console.error(`- ${violation}`);
  process.exitCode = 1;
} else {
  console.log(`Production TypeScript files are at or below ${maximumLines} lines.`);
}
