# Design

## Context

See proposal.md for motivation. `global/commands/propose.md` already says “stop for review” and
“Don't implement anything.” `global/agents/main.md` already suggests review after spec, but its
unqualified “Follow an implementation request through its checks” instruction leaves the
spec-to-build transition ambiguous. `/apply` explicitly authorizes sequential task execution.
There are no published capability specs yet.

## Goals / Non-Goals

- Resolve the conflicting routing instructions in the existing main prompt, within its current
  50-line/350-word budget and the existing request-token budget.
- Keep existing commands, task sequencing, branch handling, and writer concurrency unchanged.
- Do not introduce an authorization database, a command, or a plugin intent classifier.

## Decisions

### Fix the handoff, not the command inventory

[ADR-0014](../../../docs/adr/0014-explicit-proposal-to-build-handoff.md) records the durable
approval boundary. Rewrite the main prompt's completion guidance to distinguish:

1. Explicit direct implementation with no spec step: execute and check as today.
2. Any request that enters spec: report its result, offer review or `/apply`, and end the
   implementation chain. An earlier request cannot authorize the unseen proposal.
3. A later explicit implementation request: resume through the existing build or `/apply` path.

The stop rule must explicitly cover completion notifications, unchecked tasks, and acknowledgements
such as “looks good.” Proposal revisions stay with spec. This is agent intent routing, where
ADR-0002 permits concise judgment instructions, not deterministic git/workflow logic in prompts.
Leave `/propose` and `/apply` unchanged unless their wording needs alignment; neither is missing
the core behavior. Do not weaken `/apply`'s authorized task loop.

Alternative: deny every build delegation or add approval state in the plugin. That would change
direct implementation and require a new intent/authorization mechanism to solve a routing ambiguity.
It is not needed for this change.

### Reuse the existing test harnesses

Add an always-run prompt-contract regression to `scripts/test-workflow.sh` that fails on today's
main prompt: require explicit stop-after-spec precedence and a fresh implementation request,
reject the old unqualified follow-through wording, and preserve the existing `/propose` stop
and `/apply` sequential-task contracts. Report a named “proposal stops before build” assertion.

Extend `scripts/test-opencode.sh` to check the installed main prompt in captured model requests
contains that policy, not merely the source file. Add a scripted spec-completion/relay case that
records the review invitation and zero build requests; retain direct-build and `/apply` coverage.
Use the existing fake-model harness and asynchronous notification handling. Do not add fixed sleeps
or an external model dependency.

The scripted response proves routing/context plumbing, not that a real model infers authorization
correctly. The deterministic contract test is the red-first regression; the following manual
acceptance run is necessary to observe real-model behavior:

- `/propose add a hello command`: proposal pushed, review invitation, no build activity.
- “looks good”: no build activity.
- Ask to revise the proposal: spec only.
- `/apply`: build starts; subsequent tasks proceed without fresh approval.
- In a separate session, a clear direct implementation request still reaches build.

Document this boundary in README's existing workflow section, with the `/apply` example.

## Risks / Trade-offs

- [Prompt adherence is not a security guarantee] → Explicit precedence, installed-prompt coverage,
  and the manual acceptance transcript; do not claim a fake model proves autonomous compliance.
- [A stop rule could halt authorized `/apply` between tasks] → Scope it to the proposal handoff,
  preserve the command's task loop, and retain positive execution coverage.
- [Added wording exceeds budget] → Replace ambiguous text rather than append rules; budgets do not rise.

## Migration Plan

No data migration. After implementation is reviewed and merged, normal kit deployment installs the
updated prompt for new sessions. Roll back by reverting that implementation and redeploying through
the normal kit path. This does not cancel sessions or builds already in progress.
