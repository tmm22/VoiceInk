import js from "@eslint/js";
import eslintReact from "@eslint-react/eslint-plugin";
import nextPlugin from "@next/eslint-plugin-next";
import { defineConfig, globalIgnores } from "eslint/config";
import importX from "eslint-plugin-import-x";
import jsxA11y from "eslint-plugin-jsx-a11y-x";
import reactHooks from "eslint-plugin-react-hooks";
import globals from "globals";
import tseslint from "typescript-eslint";

// Explicit flat config instead of eslint-config-next, whose bundled
// eslint-plugin-react, jsx-a11y and import plugins do not support ESLint 10.
// It keeps every rule family that preset enabled, using maintained
// ESLint 10 equivalents for React, accessibility and import rules.
export default defineConfig([
  globalIgnores([".next/**", "out/**", "build/**", "dist/**", "convex/_generated/**", "next-env.d.ts"]),
  {
    files: ["**/*.{js,jsx,mjs,cjs,ts,tsx,mts,cts}"],
    languageOptions: { globals: { ...globals.browser, ...globals.node } },
  },
  js.configs.recommended,
  tseslint.configs.recommended,
  reactHooks.configs.flat["recommended-latest"],
  {
    files: ["**/*.{jsx,tsx}"],
    ...eslintReact.configs["recommended-typescript"],
  },
  {
    // eslint-config-next enforced react/display-name; @eslint-react keeps
    // these equivalents out of its recommended set.
    files: ["**/*.{jsx,tsx}"],
    rules: {
      "@eslint-react/no-missing-component-display-name": "error",
      "@eslint-react/no-missing-context-display-name": "error",
    },
  },
  nextPlugin.configs["core-web-vitals"],
  {
    files: ["**/*.{jsx,tsx}"],
    ...jsxA11y.configs.recommended,
  },
  {
    // CommonJS sources (the vendored fast-glob shim) legitimately use require().
    files: ["**/*.cjs"],
    languageOptions: { sourceType: "commonjs" },
    rules: { "@typescript-eslint/no-require-imports": "off" },
  },
  {
    plugins: { "import-x": importX },
    rules: { "import-x/no-anonymous-default-export": "warn" },
  },
]);
