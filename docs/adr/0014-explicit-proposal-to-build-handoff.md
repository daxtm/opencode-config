# ADR-0014: Proposal completion does not authorize build

- Status: Accepted
- Date: 2026-11-23
- Related: stop-auto-build, ADR-0002, ADR-0013

## Context

The main agent routes implementation requests to build and follows implementation through checks.
It also routes design decisions to spec and tells the user to review the resulting proposal before
`/apply`. These instructions need a clear precedence when an implementation request first needs
design: a completed proposal is not evidence that the user has reviewed it.

## Options

1. Continue from spec into build using the original request — good: fewer user turns / bad: the
   user loses the opportunity to review the actual plan before implementation.
2. End the proposal handoff and require a new explicit implementation request — good: review stays
   under user control / bad: one extra user turn even if the original request asked for a full build.

## Decision

Option 2. Once work goes through spec, main reports the proposal and stops. Only a later `/apply`
or unambiguous implementation instruction authorizes build; a review acknowledgement does not.
The deciding reason is that consent to implement an idea is not approval of an unseen plan.
Direct implementation requests that do not enter spec remain valid; an authorized `/apply` still
executes its tasks without asking for approval of each task.

## Consequences

- Good: proposal review cannot silently become implementation; existing commands remain sufficient.
- Bad: users must explicitly request implementation after planning. This is an agent-routing
  instruction, not a security boundary; scripted model tests cannot prove real-model obedience.
