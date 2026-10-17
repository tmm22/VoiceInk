"use strict";
// Drop-in for the subset of fast-glob our toolchain calls, installed through
// package.json `overrides`. fast-glob depends on micromatch -> braces, which
// carries an advisory with no patched release (GHSA-vfj7-8cjw-p6xm); tinyglobby
// matches with picomatch instead. Unsupported options throw so a new caller
// fails loudly instead of silently globbing differently.
const path = require("node:path");
const tinyglobby = require("tinyglobby");

const SUPPORTED_OPTIONS = new Set([
  "absolute",
  "caseSensitiveMatch",
  "cwd",
  "dot",
  "followSymbolicLinks",
  "ignore",
  "onlyDirectories",
  "onlyFiles",
]);

function toTinyglobbyOptions(options = {}) {
  for (const key of Object.keys(options)) {
    if (!SUPPORTED_OPTIONS.has(key)) {
      throw new TypeError(`fast-glob shim: unsupported option "${key}"; extend web/vendor/fast-glob`);
    }
  }
  return {
    ...options,
    // fast-glob never expands a bare directory pattern into its contents.
    expandDirectories: false,
    ...(options.onlyDirectories ? { onlyFiles: false } : {}),
  };
}

// tinyglobby marks directories with a trailing slash; fast-glob does not.
function stripDirectorySlash(entry) {
  return entry.length > 1 && entry.endsWith("/") ? entry.slice(0, -1) : entry;
}

// fast-glob keeps a pattern's written "./dir/" base in each result ("./*.ts"
// yields "a.ts", but "./lang/*.ts" yields "./lang/a.ts"); tinyglobby drops it.
function keepsDotSlashBase(pattern) {
  if (!pattern.startsWith("./")) return false;
  const segments = pattern.slice(2).split("/");
  return segments.length > 1 && !tinyglobby.isDynamicPattern(segments[0]);
}

// Evaluate each pattern alone so per-pattern output conventions hold:
// absolute patterns return absolute paths (tinyglobby would return them
// relative to the process cwd), and "./dir/" bases are preserved.
function planCalls(patterns, options) {
  const base = toTinyglobbyOptions(options);
  return [].concat(patterns).map((pattern) => {
    const absolute = base.absolute === true || path.isAbsolute(pattern);
    return {
      pattern,
      options: absolute ? { ...base, absolute: true } : base,
      prefix: !absolute && keepsDotSlashBase(pattern) ? "./" : "",
    };
  });
}

function collect(results) {
  const seen = new Set();
  for (const { entries, prefix } of results) {
    for (const entry of entries) seen.add(prefix + stripDirectorySlash(entry));
  }
  return [...seen];
}

function globSync(patterns, options) {
  return collect(planCalls(patterns, options).map(({ pattern, options: callOptions, prefix }) => ({
    entries: tinyglobby.globSync(pattern, callOptions),
    prefix,
  })));
}

async function glob(patterns, options) {
  return collect(await Promise.all(planCalls(patterns, options).map(async ({ pattern, options: callOptions, prefix }) => ({
    entries: await tinyglobby.glob(pattern, callOptions),
    prefix,
  }))));
}

function unsupported(name) {
  return () => {
    throw new TypeError(`fast-glob shim: ${name}() is not implemented; extend web/vendor/fast-glob`);
  };
}

const fastGlob = Object.assign(glob, {
  glob,
  async: glob,
  globSync,
  sync: globSync,
  isDynamicPattern: tinyglobby.isDynamicPattern,
  escapePath: tinyglobby.escapePath,
  convertPathToPattern: tinyglobby.convertPathToPattern,
  stream: unsupported("stream"),
  globStream: unsupported("globStream"),
  generateTasks: unsupported("generateTasks"),
});
fastGlob.default = fastGlob;

module.exports = fastGlob;
