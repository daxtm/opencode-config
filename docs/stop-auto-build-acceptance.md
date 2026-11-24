# stop-auto-build — acceptance record

Change: `openspec/changes/stop-auto-build` · ADR: [ADR-0014](adr/0014-explicit-proposal-to-build-handoff.md) · Date: 2026-11-23

Two kinds of evidence are recorded here, and they are **not** equivalent:

- **Deterministic + fake-model coverage (observed)** — automated checks that ran in CI-like
  conditions on this repo. They prove the prompt contract and the request/context plumbing:
  which text reaches the model, which agent is invoked, what is relayed.
- **Manual real-model acceptance (pending, not run)** — the design's 5-step live checklist. It
  requires the user's real model and live kit and has **not been performed** as part of this
  change. A fake model follows a script; it cannot prove that a real model refuses to build from
  an acknowledgement. These steps must be observed once on a live session before calling the
  behavior fully accepted.

## Observed: prompt contract (fake-free, always runs)

`bash scripts/test-workflow.sh` — **116 passed, 0 failed**, including the named regression
"prompt contract: proposal stops before build":

- main prompt: spec completion stops for review; a new explicit implementation request is
  required after the proposal; the earlier request cannot authorize the proposal.
- main prompt: the old unqualified "Follow an implementation request through its checks" is gone.
- `/propose` still stops for review and never implements; `/apply` still runs one task at a time
  and starts the next task itself.

Prompt/request budgets unchanged (verified in the OpenCode tests below; `budgets.conf` untouched).

## Observed: fake-model harness (`scripts/test-opencode.sh`, real OpenCode + scripted model)

`bash scripts/test-opencode.sh` — **39 passed, 0 failed** (main ≈3145 tokens/request, build
≈2433; budgets 3200/2700). New coverage, asserted against the *installed* prompt as captured in
recorded model requests, not merely the source file:

- "proposal handoff stops before build" (scripted spec-completion/relay):
  - the propose request goes through spec;
  - **zero build requests** after spec completes — no build agent started, no build delegation
    even attempted;
  - main relays the review invitation ("Review it, then /apply — or tell me what to change");
  - captured main-session request system prompt contains: "stop for review", "never authorize
    build", `/apply` as the explicit authorization, and no unqualified follow-through wording.
- `/apply` positive case retained: `/apply` runs in the main session, asks for one task per build
  run, **still starts the build itself** (no fresh approval per task), and the build request is
  the single next task.
- Direct-build positive case retained: main delegates a plain implementation request to build and
  relays the result.

This harness proves routing/context plumbing only (see ADR-0014 consequences); it does not show a
real model inferring authorization correctly.

## Pending: manual real-model acceptance (design checklist — NOT RUN)

To be observed on a live session with the user's real model (design lines 57-61):

1. `/propose add a hello command` → proposal pushed, review invitation, no build activity. **Not run.**
2. Reply "looks good" → still no build activity. **Not run.**
3. Ask to revise the proposal → spec only. **Not run.**
4. `/apply` → build starts; subsequent tasks proceed without fresh approval. **Not run.**
5. In a separate session, a clear direct implementation request still reaches build. **Not run.**

Each step should be confirmed against this record (e.g. via `ock` request logs or visible agent
activity) before the change is treated as fully accepted in practice.
