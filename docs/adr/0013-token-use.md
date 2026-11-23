# ADR-0013: Bound session size — one build per task, a 128k context cap

- Status: Accepted
- Date: 2026-11-23
- Related: ADR-0008

## Context
Measured on the owner's machine (OpenCode's own records, 7 days, 2,103 model requests): build made
1,709 requests averaging ≈153k tokens of input each — 262M tokens, ≈95% of all usage — and one build
session reached 320k tokens per request. Every step of a session resends the whole session; OpenCode
only compacts near the model's context limit, which for Go's models is above 320k. The fixed
per-request overhead the kit had trimmed (≈3k tokens) was irrelevant next to this. Main also grew to
≈150k per request in long sessions.

## Options
1. Lower the cap a lot (e.g. 64k) — good: simple / bad: frequent summaries; build loses the detail
   it needs mid-task, so quality drops and work gets redone.
2. One build run per OpenSpec task (fresh context: the change's docs, one task, the files it needs),
   one at a time, plus a generous 128k cap as a safety net — good: sessions stay small without losing
   anything the task needs / bad: each task rereads the change's docs and the files it touches.

## Decision
Option 2. `/apply` runs in the main session and hands build one task at a time; the kit plugin
refuses to start a file-changing agent (build, debugger, spec) while another runs in the same project;
`opencode.jsonc` caps GLM-5.3 Flash and DeepSeek V4.1 Flash at 128k context; the compaction summary
uses DeepSeek on `high`. `ock usage` reports where tokens went, so the effect is measured, not assumed.

## Consequences
- Good: build's per-request input is bounded by one task's context instead of a whole change's history.
- Bad: main makes one short extra turn per task; a task that needs a lot of context may hit the cap
  and be summarized.
