# ADR-0014: `/apply` runs one steerable build; "stop" stops

- Status: Accepted
- Date: 2026-11-23
- Related: partly supersedes ADR-0013 (the 128k context cap stays)

## Context
ADR-0013 split `/apply` into one fresh build session per task. In use it was too slow: every task paid
a main turn plus a cold start, and a change took over an hour. Worse, the guard against a second build
also refused follow-ups to the running build, so the owner could not change its course or stop it —
OpenCode's subagent tool joins a follow-up (`sessionID`) to the running child's current run, and the
guard blocked exactly that. Its tracker also forgot a build once a follow-up restarted its run.

## Options
1. Keep per-task sessions, fix steering — good: smallest sessions / bad: still slow.
2. One build for the whole change, bounded by the 128k cap, with lean-context habits in build's
   prompt; a guard that refuses only a NEW concurrent writer; a `stop_subagents` tool for main — good:
   fast, steerable, and the cap still stops runaway sessions / bad: a long change can reach the cap and
   be summarized once or twice.

## Decision
Option 2. The guard moves to the subagent tool's `execute.before` hook, where it sees `sessionID`:
follow-ups always pass; a new build/debugger/spec while another runs in the project is refused with
how to steer or stop it. Run state follows `session.execution.started`/ended events. Main's prompt:
"stop" → `stop_subagents` first, then answer; a change of plan → a follow-up to the running agent.

## Consequences
- Good: `/apply` is one continuous build again; the owner can redirect or stop it mid-run.
- Bad: main's request grows ~75 tokens (the stop tool); measure the cap's effect with `ock usage`.
