# ADR-0008: OpenCode v2 replaces pi; the kit is ported, not rebuilt

- Status: Accepted
- Date: 2026-11-22
- Related: supersedes the pi harness parts of ADR-0002 (the scripts-not-prompts principle stands)

## Context
pi was too bare: it had no notion of a project boundary (asked to fix a file shown from another
project, it edited that other project and left the current one untouched), and most of pi-config
existed only to add things OpenCode already has (subagents, project scoping, web search, slash
commands). OpenCode's cost problem was its defaults: a stock request sends ~6.3k tokens of system
prompt and tool definitions before the user's first word, plus a separate title request.

## Options
1. Keep patching pi — good: no migration / bad: every missing feature is more kit code to maintain.
2. OpenCode v2, stripped down, with only the workflow parts of pi-config ported — good: native
   agents, permissions, plugins and web search; the scripts carry over unchanged in behavior / bad:
   one-time port; OpenCode's plugin API is new and may move.

## Decision
Option 2. Kept: the git/GitHub scripts (`pinew`→`ock new`, `pi-branch`→`ock branch`,
`pi-ship`→`ock ship`, `pi-test-branch`→`ock test`/`ock status`/`ock cleanup`/`ock live`,
`pi-check`→`ock check`, `pi-gh-setup`→`ock gh-setup`, `pikit`→`ock kit`), the templates, OpenSpec +
ADRs, the model split, the no-moralizing rule and direct `/research`. Dropped: every pi shim
(subagent extension, kit-path, zsh-bang, web-scope, main-only) and `pikit repair`/retries.
The `pr-only` guard became the kit plugin plus permissions, extended with the project boundary.
Token levers, all measured against OpenCode 2.3.2: each agent has its own short system prompt (it
replaces the provider base prompt), unused tools are denied, the title request is answered by the
plugin, and the main session's request is ~3k tokens.

## Consequences
- Good: the project boundary is enforced, not hoped for; less kit code; same workflow commands.
- Bad: projects set up by pinew need `ock new` once to switch their hooks and settings over.
