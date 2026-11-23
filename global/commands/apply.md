---
description: Implement the approved OpenSpec change task by task (a fresh build agent per task), push — no PR
---
Implement OpenSpec change $ARGUMENTS (none given: the one matching the current branch `feat/<id>`).

Run build for ONE task at a time — the first unchecked `- [ ]` task in its tasks.md — with the prompt
"OpenSpec change <id>, task <n>: <task text>. Do only this task." When it finishes, reread tasks.md and
start the next one. Never start one while a build is running. A task failing twice: debugger once, then stop.
All ticked: run `ock check HEAD` and report what works and how to see it.
