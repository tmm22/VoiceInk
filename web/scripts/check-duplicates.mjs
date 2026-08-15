import { readdir } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const projectRoot = fileURLToPath(new URL("../", import.meta.url));
const ignoredDirectoryNames = new Set([
  ".git",
  ".next",
  ".wrangler",
  "coverage",
  "node_modules",
]);
const finderDuplicatePattern = / \d+(?:\.[^/]+)*$/;

export async function findDuplicateArtifacts(root = projectRoot) {
  const matches = [];

  async function visit(directory) {
    const entries = await readdir(directory, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory() && ignoredDirectoryNames.has(entry.name)) continue;
      const path = resolve(directory, entry.name);
      if (entry.isDirectory() && finderDuplicatePattern.test(entry.name)) matches.push(path);
      else if (entry.isDirectory()) await visit(path);
      else if (entry.isFile() && finderDuplicatePattern.test(entry.name)) matches.push(path);
    }
  }

  await visit(root);
  return matches.sort();
}

async function main() {
  const duplicates = await findDuplicateArtifacts();
  if (duplicates.length) {
    console.error("Finder-style duplicate artifacts are not allowed:");
    for (const duplicate of duplicates) console.error(`- ${duplicate}`);
    process.exitCode = 1;
    return;
  }
  console.log("No Finder-style duplicate source or build artifacts found.");
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  await main();
}
