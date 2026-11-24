---
description: Implement the approved OpenSpec change with one build agent through its checks, push — no PR
---
Implement OpenSpec change $ARGUMENTS (none given: the one matching the current branch `feat/<id>`).

Start ONE build for the whole change with the prompt "Implement OpenSpec change <id>: every unchecked
task in tasks.md, in order." The user can steer it while it runs: pass a change of plan to it as a
follow-up (its sessionID). Failing twice on one task: debugger once, then stop and report.
When it finishes: run `ock check HEAD` and report what works and how to see it.
