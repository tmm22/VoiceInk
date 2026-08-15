import { rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const projectRoot = fileURLToPath(new URL("../", import.meta.url));
const buildDirectories = [
  fileURLToPath(new URL("../dist/", import.meta.url)),
  fileURLToPath(new URL("../.vinext/", import.meta.url)),
];

for (const directory of buildDirectories) {
  if (!directory.startsWith(projectRoot)) {
    throw new Error(`Refusing to clean a path outside the web project: ${directory}`);
  }
  await rm(directory, { recursive: true, force: true });
}

console.log("Removed web/dist and web/.vinext build outputs.");
