---
description: Implement the approved OpenSpec change (build agent) through its checks, push — no PR
agent: build
---
Implement OpenSpec change $ARGUMENTS — every task in its tasks.md. No change id given: use the change matching
the current branch (`feat/<id>`). If switching to it would mix in unrelated edits, stop and report their paths.
