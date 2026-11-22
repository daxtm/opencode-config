# ADR-0010: PRs to main require the GitHub Actions `check` again

- Status: Accepted
- Date: 2026-11-22
- Related: restores the CI requirement of ADR-0003 that pi-config v3 removed

## Context
The owner's requirement is final verification by GitHub Actions before a PR can merge. pi-config v3
deleted `.github/workflows/ci.yml` from the templates and the required `check` from the ruleset,
relying on local checks only. Local checks run on the owner's machine and can be skipped by opening
a PR any other way.

## Options
1. Local checks only (v3) — good: no CI minutes / bad: nothing enforces them at merge time.
2. Local checks before push (`ock check`) and the required CI job `check` on every PR — good:
   enforced by the ruleset, same script both places / bad: CI minutes (free on public repos).

## Decision
Option 2. `ock new` installs `.github/workflows/ci.yml` (job `check`: OpenSpec validation, no
unarchived change left in the PR, `scripts/check.sh`); `ock gh-setup` requires `check` on main and
puts it back on repos where v3 removed it.

## Consequences
- Good: a red PR can't be merged, whoever opened it.
- Bad: a PR waits for CI (usually a minute) before the merge button turns green.
