import js from "@eslint/js";
import eslintReact from "@eslint-react/eslint-plugin";
import { defineConfig, globalIgnores } from "eslint/config";
import importX from "eslint-plugin-import-x";
import jsxA11y from "eslint-plugin-jsx-a11y-x";
import reactHooks from "eslint-plugin-react-hooks";
import globals from "globals";
import tseslint from "typescript-eslint";

// Explicit flat config for a Preact app. It keeps the rule families the old
// eslint-config-next preset enforced (core, TypeScript, hooks, React
// correctness, accessibility, imports) using maintained ESLint 10 plugins.
export default defineConfig([
  globalIgnores(["dist/**", "convex/_generated/**"]),
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
    files: ["**/*.{jsx,tsx}"],
    settings: { "react-x": { importSource: "preact" } },
    rules: {
      // eslint-config-next enforced react/display-name; @eslint-react keeps
      // these equivalents out of its recommended set.
      "@eslint-react/no-missing-component-display-name": "error",
      "@eslint-react/no-missing-context-display-name": "error",
      // These suggest React 19-only APIs (use(), <Context> as a provider) that
      // Preact's core does not provide.
      "@eslint-react/no-use-context": "off",
      "@eslint-react/no-context-provider": "off",
    },
  },
  {
    files: ["**/*.{jsx,tsx}"],
    ...jsxA11y.configs.recommended,
  },
  {
    plugins: { "import-x": importX },
    rules: { "import-x/no-anonymous-default-export": "warn" },
  },
]);
