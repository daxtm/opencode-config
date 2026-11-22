# ADR-0009: No-model kit commands run as `!ock …`

- Status: Accepted
- Date: 2026-11-22
- Related: ADR-0002, ADR-0008

## Context
pi showed script output from `/ship`, `/cleanup` etc. without a model call. In OpenCode 2.3.2 a
plugin command runs code with zero model calls, but it cannot show its output: queued text only
reaches the next model turn, and a thrown error appears as an error notice. A markdown command
always costs a model turn. The TUI's `!` shell mode runs a command and shows its output with zero
model requests (verified in a pty against the real TUI).

## Options
1. `/ship` as a markdown command — good: familiar name / bad: a model turn (and tokens) for a script.
2. `/ship` as a plugin command reporting through errors — good: no tokens / bad: success looks like
   an error, and output is truncated.
3. One CLI, `ock`, typed as `!ock ship` inside OpenCode (or plain `ock ship` in a terminal) — good:
   no tokens, full output, same command everywhere / bad: one character to learn.

## Decision
Option 3. Model workflows stay slash commands (/propose, /apply, /fix, /research, /roadmap, /adr,
/commit); git and GitHub plumbing is `ock`.

## Consequences
- Good: zero-token shipping, cleanup and status; the model can also run `ock` when asked.
- Bad: `/ship` doesn't exist — the main agent's prompt points to `!ock ship`.
