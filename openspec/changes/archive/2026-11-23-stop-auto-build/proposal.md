# Proposal

## Why

The build step must not start automatically when a proposal is ready. The user needs a review boundary before implementation, even when the original request sounded ready to build.

## What Changes

- Fix the existing main-agent handoff: after spec completes, report the proposal and stop; do not start build.
- Require a new explicit implementation request (`/apply` or an unambiguous instruction to implement) after that handoff. Proposal completion, unchecked tasks, agent notifications, and review acknowledgements are not authorization.
- Preserve direct implementation requests and `/apply`'s existing one-task-at-a-time execution once authorized.
- Add regression coverage to the existing workflow/OpenCode tests and document the review boundary.

## Capabilities

### New Capabilities

- `implementation-handoff`: User-controlled transition from proposal to implementation. No existing published specs cover it; this records a correction to the existing agents and commands, not a new command or mechanism.

### Modified Capabilities

None.

## Impact

Implementation touches `global/agents/main.md`, the existing `/propose` and `/apply` contracts only as needed, `scripts/test-workflow.sh`, `scripts/test-opencode.sh`, and README workflow guidance. Prompt and request budgets stay unchanged.

Out of scope: stopping an already authorized build, prompting before each `/apply` task, changing build models or concurrency, new approval storage, permission hooks, and shipping behavior.

To see it work, run `/propose add a hello command`: expect a committed proposal and “Review it, then /apply — or tell me what to change,” with no build agent started. Reply “looks good”: still no build. Run `/apply`: the first unchecked task starts in build.
