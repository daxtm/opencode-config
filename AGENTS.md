# opencode-config

The user's OpenCode v2 setup, managed as a project. Merged changes reach the user's OpenCode
automatically: `ock kit` keeps the live kit (~/workspace/projects/.opencode-workflow-kit, a clone
following GitHub's main) up to date, and its `install.sh` writes ~/.config/opencode.

## Stack
Bash (install.sh, setup.sh, bin/*), one TypeScript OpenCode plugin (global/plugins/kit.ts),
Markdown agents/commands (global/), project templates (templates/project), OpenSpec + ADRs.

## Checks
`scripts/check.sh` — shell syntax + shellcheck, plugin syntax, prompt budgets (budgets.conf), the
workflow behavior tests (scripts/test-workflow.sh) and the OpenCode tests (scripts/test-opencode.sh:
real OpenCode + a fake model — token budget per request, guard, agents, commands).
Run / demo: `bin/ock kit status`, `bin/ock models`.

## Layout
- `bin/` — `ock` and the scripts behind it (ock-new, ock-branch, ock-ship, ock-test, ock-check, ock-gh-setup, ock-kit, ock-resolve)
- `global/` → ~/.config/opencode (opencode.jsonc, AGENTS.md for every agent, agents/, commands/, plugins/)
- `templates/project/` — what `ock new` puts in each project
- `agent-models.conf` — which model each agent uses

## Rules (read ADR-0002 and ADR-0008 before changing the workflow)
- Workflow logic goes in scripts, never in prompts. A prompt says what job to do, not how to police it.
- budgets.conf is a hard limit. Don't raise it to fit a rule — move the rule into a script or the plugin.
- The plugin must never throw from setup or a hook: a broken plugin can stop OpenCode from starting.
- Scripts use absolute paths; anything that deletes files needs --dry-run. Never commit secrets.
