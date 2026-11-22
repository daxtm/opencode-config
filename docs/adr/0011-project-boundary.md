# ADR-0011: Agents write only inside the current project

- Status: Accepted
- Date: 2026-11-22
- Related: ADR-0008

## Context
Shown a file from another project, pi edited that other project and did nothing in the one being
worked on. Other projects are useful references, so reading them must stay possible.

## Options
1. A prompt rule only — good: no code / bad: models ignore rules under pressure; that's how it broke.
2. Enforce it: OpenCode permissions deny edit/write to any absolute path (outside the project) except
   /tmp, and the kit plugin denies shell writes outside the project (redirects, cp/mv/rm/…,
   `git -C`/`cd` into another repo) — good: the model gets a clear refusal it can't talk around /
   bad: a heuristic shell parser can miss exotic commands.

## Decision
Option 2, plus the rule in AGENTS.md so the model knows why. The deployed config
(`~/.config/opencode`) and the live kit are read-only even when they'd otherwise be writable.

## Consequences
- Good: a fix for another project is reported, not silently made in the wrong place.
- Bad: legitimate writes elsewhere (other than /tmp) need the user to run them with `!`.
