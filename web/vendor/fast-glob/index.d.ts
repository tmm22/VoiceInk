type Pattern = string | readonly string[];
interface Options {
  absolute?: boolean;
  caseSensitiveMatch?: boolean;
  cwd?: string;
  dot?: boolean;
  followSymbolicLinks?: boolean;
  ignore?: string[];
  onlyDirectories?: boolean;
  onlyFiles?: boolean;
}
declare function fastGlob(patterns: Pattern, options?: Options): Promise<string[]>;
declare namespace fastGlob {
  function glob(patterns: Pattern, options?: Options): Promise<string[]>;
  function async(patterns: Pattern, options?: Options): Promise<string[]>;
  function globSync(patterns: Pattern, options?: Options): string[];
  function sync(patterns: Pattern, options?: Options): string[];
  function isDynamicPattern(pattern: string): boolean;
  function escapePath(path: string): string;
  function convertPathToPattern(path: string): string;
}
export = fastGlob;
