# Decision log (ADRs)

One decision per file, `NNNN-kebab-title.md`, from [0000-template.md](0000-template.md). Written by OpenCode
when a decision outlives one change (a dependency, a data format, an architecture choice); routine
choices stay in the OpenSpec change's `design.md`. Merging the PR accepts it. Never edited afterwards,
except to mark it superseded by a newer ADR.

| ADR | Title | Status | Date |
|---|---|---|---|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted | 2026-11-21 |
| [0002](0002-workflow-in-scripts-not-prompts.md) | Workflow in scripts, not prompts | Accepted | 2026-11-21 |
| [0003](0003-public-repos-by-default.md) | Public repos by default | Accepted | 2026-11-21 |
| [0004](0004-script-owned-repository-takeover.md) | Script-owned repository takeover | Superseded by 0006 | 2026-11-21 |
| [0005](0005-explicit-research-scope.md) | Explicit research scope | Accepted | 2026-11-21 |
| [0006](0006-takeover-is-part-of-pinew.md) | Taking over a repo is part of `pinew` | Accepted | 2026-11-21 |
| [0007](0007-test-holds-only-finished-work.md) | `test` holds only finished work | Accepted | 2026-11-21 |
| [0008](0008-opencode-replaces-pi.md) | OpenCode v2 replaces pi; the kit is ported, not rebuilt | Accepted | 2026-11-22 |
| [0009](0009-kit-commands-run-with-bang.md) | No-model kit commands run as `!ock …` | Accepted | 2026-11-22 |
| [0010](0010-ci-check-required-again.md) | PRs to main require the GitHub Actions `check` again | Superseded by 0012 | 2026-11-22 |
| [0011](0011-project-boundary.md) | Agents write only inside the current project | Accepted | 2026-11-22 |
| [0012](0012-no-github-actions.md) | No GitHub Actions — checks run locally in `ock ship` | Accepted | 2026-11-22 |
