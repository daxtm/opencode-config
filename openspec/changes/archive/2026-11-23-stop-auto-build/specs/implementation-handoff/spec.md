## Purpose

Keep the transition from proposal review to implementation under the user's explicit control.

## ADDED Requirements

### Requirement: Proposal handoff stops before build

After spec completes a proposal, main MUST relay the result and invite review or `/apply`, then stop without launching build. This rule MUST take precedence over following an earlier implementation request through completion.

#### Scenario: Propose completes

- **WHEN** `/propose add a hello command` finishes and spec reports the pushed proposal
- **THEN** main reports the proposal and invites “Review it, then /apply — or tell me what to change”
- **AND** no build agent starts

#### Scenario: Implementation needs design first

- **WHEN** a user requests implementation, main delegates a material design decision to spec, and spec completes
- **THEN** main stops at the proposal handoff rather than resuming the original implementation request
- **AND** build has not started

### Requirement: Build after planning requires a new implementation request

After a proposal handoff, main MUST start build only on a subsequent explicit user instruction to implement, including `/apply`. Agent notifications, existing tasks, and review acknowledgements MUST NOT count as that instruction. Requests to revise a proposal MUST remain planning work.

#### Scenario: Review acknowledgement

- **WHEN** the user replies “looks good” to a completed proposal
- **THEN** main does not start build and points to `/apply` if it suggests a next step

#### Scenario: Completion notification

- **WHEN** main receives a delayed spec completion notification while unchecked implementation tasks exist
- **THEN** main does not start build solely because of that notification or those tasks

#### Scenario: Proposal revision

- **WHEN** the user asks to change the proposed approach without asking to implement it
- **THEN** main routes the revision to spec and does not start build

#### Scenario: Explicit implementation after review

- **WHEN** the user sends `/apply` for the proposal or says “implement this proposed change now”
- **THEN** main starts implementation using the existing build workflow

### Requirement: Authorized execution remains unchanged

Main MUST continue accepting clear direct implementation requests that do not require spec. An authorized `/apply` MUST retain fresh build sessions for successive unchecked tasks, one at a time, without requiring another user approval between tasks.

#### Scenario: Direct implementation

- **WHEN** the user requests a clear implementation that needs no proposal
- **THEN** main can delegate it directly to build

#### Scenario: Apply has more tasks

- **WHEN** an explicitly requested `/apply` finishes one task and another unchecked task remains
- **THEN** main starts the next task in a fresh build session after the previous one finishes, subject to existing failure handling
