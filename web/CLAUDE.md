# VoiceInk Web — Claude Code Guide

The canonical agent instructions for everything under `web/` live in `AGENTS.md`.
That file is the single source of truth; this file only imports it and adds a
quick reference so nothing drifts between the two.

@AGENTS.md

## Quick reference for Claude Code

- Run all commands from `web/`, not the repository root.
- Before committing: `npm run check` (types, lint, production build, Node tests,
  secret scan, dependency audit). Never weaken a check to make a change pass.
- After deploying: `npm run test:production -- --base-url https://v.paul.im`.
- Production deploy: `npx wrangler deploy --config wrangler.production.jsonc --keep-vars`
  (`--keep-vars` is mandatory — dashboard-managed vars must survive).
- The only production origin is `https://v.paul.im`; `workers.dev` stays disabled.
- Never print secret values while debugging; confirm existence only.
- Keep `README.md`, `docs/DEPLOYMENT.md`, and `docs/COSTS.md` in sync with any
  architecture, model, retention, domain, secret, rate-limit, or deploy change —
  `npm run check` enforces some of this via the doc-contract tests.
