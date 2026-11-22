# ADR-0012: No GitHub Actions — checks run locally in `ock ship`

- Status: Accepted
- Date: 2026-11-22
- Related: supersedes ADR-0010

## Context
Every project is the owner's alone, worked on from one machine. `ock ship` already runs the full
checks (`ock check`: scripts/check.sh + OpenSpec) on a clean checkout of the exact commit it pushes,
after merging in the latest main, and refuses to push if they fail. The CI job re-ran the same thing
on GitHub's machine. In practice it failed for reasons that weren't the code: the template pinned
Node 24 while a project needed Node 26, and each run downloaded ~330 MB of browsers and fonts before
testing. Every PR also waited on it.

## Options
1. Keep the required CI `check` — good: tests on a second machine / bad: that machine isn't the
   one the code runs on, so it needs per-project version pinning, and every PR waits.
2. No CI; the main ruleset requires a PR (no force-push, no deletion) but no status check — good:
   no waiting, nothing to keep in sync; `ock ship` still won't push failing code / bad: nothing on
   GitHub stops merging a PR that didn't come through `ock ship`.

## Decision
Option 2. `ock new` no longer installs `.github/workflows/ci.yml`; `ock gh-setup` sets the main
ruleset without a required status check and, re-run on an existing repo, removes the old `check`
requirement. opencode-config's own workflow is gone too.

## Consequences
- Good: a shipped PR can be merged immediately; no CI configuration to maintain.
- Bad: a commit pushed after `ock ship` (or a PR opened by hand) isn't checked by anything — ship
  again before merging.
