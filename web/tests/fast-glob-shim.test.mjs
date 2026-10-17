import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";

// The tree resolves fast-glob to vendor/fast-glob (a tinyglobby-backed shim)
// so no package depends on braces (GHSA-vfj7-8cjw-p6xm, never patched). The
// expected values below were recorded from real fast-glob 3.3.3 against this
// fixture, covering the call shapes of vite-plugin-dynamic-import (relative
// globs with a cwd) and @next/eslint-plugin-next (absolute onlyDirectories).
const require = createRequire(import.meta.url);
const fastGlob = require("fast-glob");

const FILES = [
  "src/a.ts", "src/b.js", "src/index.ts", "src/lang/en.json", "src/lang/de.js", "src/lang/index.js",
  "src/.hidden.ts", "pages/x.tsx", "apps/one/pages/p.tsx", "apps/two/x.txt", "dir.ts/inner.ts",
];

const ROOT = "<root>";
const CASES = [
  [["./lang/*.{js,ts,json}", "./lang/*/index.{js,ts,json}"], { cwd: `${ROOT}/src` }, ["./lang/de.js", "./lang/en.json", "./lang/index.js"]],
  [["./*.{ts,js}", "./*/index.{ts,js}"], { cwd: `${ROOT}/src` }, ["a.ts", "b.js", "index.ts", "lang/index.js"]],
  [["../pages/*.tsx"], { cwd: `${ROOT}/src` }, ["../pages/x.tsx"]],
  [["src/**/*.ts"], { cwd: ROOT }, ["src/a.ts", "src/index.ts"]],
  [["src"], { cwd: ROOT }, []],
  [`${ROOT}/apps/*/`, { onlyDirectories: true }, [`${ROOT}/apps/one`, `${ROOT}/apps/two`]],
  [ROOT, { onlyDirectories: true }, [ROOT]],
  [["apps/*"], { cwd: ROOT, onlyDirectories: true }, ["apps/one", "apps/two"]],
  [["**/*.ts"], { cwd: ROOT }, ["dir.ts/inner.ts", "src/a.ts", "src/index.ts"]],
  [["**/*.ts"], { cwd: ROOT, dot: true }, ["dir.ts/inner.ts", "src/.hidden.ts", "src/a.ts", "src/index.ts"]],
  [["**/index.*"], { cwd: ROOT, ignore: ["**/lang/**"] }, ["src/index.ts"]],
  [["src/*", "src/**/*.js"], { cwd: ROOT }, ["src/a.ts", "src/b.js", "src/index.ts", "src/lang/de.js", "src/lang/index.js"]],
  [["./src/lang/*.js"], { cwd: ROOT, absolute: true }, [`${ROOT}/src/lang/de.js`, `${ROOT}/src/lang/index.js`]],
];

async function withFixture(run) {
  // realpath: macOS tmpdir is a symlink, and absolute results use the real path.
  const root = await realpath(await mkdtemp(join(tmpdir(), "voiceink-fast-glob-")));
  try {
    for (const file of FILES) {
      await mkdir(dirname(join(root, file)), { recursive: true });
      await writeFile(join(root, file), "");
    }
    await run((value) => JSON.parse(JSON.stringify(value).replaceAll(ROOT, root)));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

test("fast-glob resolves to the vendored tinyglobby shim, not the braces-dependent package", async () => {
  const manifest = JSON.parse(await readFile(require.resolve("fast-glob/package.json"), "utf8"));
  assert.match(manifest.version, /-tinyglobby\./);
  const lock = JSON.parse(await readFile(new URL("../package-lock.json", import.meta.url), "utf8"));
  for (const name of ["braces", "micromatch"]) {
    const installed = Object.keys(lock.packages).filter((path) => path.endsWith(`node_modules/${name}`));
    assert.deepEqual(installed, [], `${name} must not return to the dependency tree`);
  }
});

test("the shim matches real fast-glob output for every supported call shape", async () => {
  await withFixture(async (resolve) => {
    for (const [patterns, options, expected] of CASES) {
      const label = `${JSON.stringify(patterns)} ${JSON.stringify(options)}`;
      const want = resolve(expected).sort();
      assert.deepEqual(fastGlob.sync(resolve(patterns), resolve(options)).sort(), want, `sync ${label}`);
      assert.deepEqual(fastGlob.globSync(resolve(patterns), resolve(options)).sort(), want, `globSync ${label}`);
      assert.deepEqual((await fastGlob.glob(resolve(patterns), resolve(options))).sort(), want, `glob ${label}`);
      assert.deepEqual((await fastGlob(resolve(patterns), resolve(options))).sort(), want, `default ${label}`);
    }
  });
});

test("the shim fails loudly on options and APIs it does not emulate", () => {
  assert.throws(() => fastGlob.sync("*", { deep: 1 }), /unsupported option "deep"/);
  assert.throws(() => fastGlob.sync("*", { markDirectories: true }), /unsupported option "markDirectories"/);
  assert.throws(() => fastGlob.stream("*"), /stream\(\) is not implemented/);
  assert.equal(fastGlob.isDynamicPattern("src/*.ts"), true);
  assert.equal(fastGlob.isDynamicPattern("src/a.ts"), false);
});
