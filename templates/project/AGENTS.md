# {{PROJECT_NAME}}

<!-- Project facts for OpenCode. Sent with every request: keep it short (under ~30 lines).
     Ask OpenCode: "fill in the placeholders in AGENTS.md". -->

## What this is
<one or two sentences: what it does and who uses it>

## Stack
<language/runtime + version, framework, package manager, database>

## Checks
`scripts/check.sh` runs everything (install deps, tests, lint, build). `ock check` runs it on a
commit in a clean checkout; `ock ship` won't push a commit that fails it.
Run / demo: `<command that shows it working>`

## Layout
<the 3-6 directories that matter and what lives in each>

## Rules
- Specs: `openspec/`. Decisions: `docs/adr/`. Plan: `docs/ROADMAP.md`.
- <project-specific rules: files not to touch, naming, error handling>
