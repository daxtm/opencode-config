# opencode-config

My OpenCode v2 setup, managed like any other project: changes go branch → PR → merge, and a
merged change reaches OpenCode on its own. Stripped down for tokens (a main-session request is ~3k
tokens of overhead instead of ~6.8k stock), with a spec-driven git workflow that runs in scripts,
not prompts.

## Daily use

Start OpenCode in a project folder (`cd ~/workspace/projects/<name> && opencode`).

| You want to… | Type |
|---|---|
| Ask something, small edit | just say it |
| Plan one feature (OpenSpec change on `feat/<id>`) | `/propose <idea>` (or `/propose next` from the roadmap) |
| Build the approved change | `/apply` (say "stop" or a change of plan any time) |
| Fix a bug or a failing check | `/fix <symptom>` |
| Look something up on the web | `/research <question>` |
| Plan a whole project | `/roadmap <idea>` |
| Record a decision | `/adr <decision>` |
| Commit what's lying around | `/commit` |
| Open / update the PR | `!ock ship` |
| What's in `test`, what's waiting | `!ock status` |
| Delete local branches you deleted on GitHub | `!ock cleanup` (`--dry-run` first if you like) |
| Go back to main | `!ock switch` |
| See where your tokens went | `!ock usage` (`!ock usage 30` for 30 days) |

Planning never rolls into building on its own. When `/propose` finishes, the change is written and
pushed and the session stops for your review — the original request does not authorize an unseen
plan, and neither does "looks good", a pending task or a finish notification. Review it, then run
`/apply` (or say "implement it") to build it, one task per build agent; a direct request that needs
no spec still builds right away.

While a subagent works, a line above the prompt shows which one, for how long, and what it's doing
right now; the sidebar lists the session's subagents; a toast (and, when the terminal isn't focused,
a desktop notification) says when one finishes. ↓ on an empty prompt opens OpenCode's subagent list.

`!` runs a shell command right in OpenCode: its output shows up and **no model is called** (zero
tokens). Every `ock` command also works in a normal terminal. `ock help` lists them all.

New project: `ock new <name>` (creates `~/workspace/projects/<name>`, a public GitHub repo with
rulesets, OpenSpec, ADRs, local checks, the `test` branch). Existing folder or pi-era project: `cd` into it,
`ock new`.

## What happens on its own

- Feature branches are pushed for you. `test` = main + every finished branch (a `feat/` branch once
  all its OpenSpec tasks are ticked; `fix/` `chore/` `docs/` right away). A live copy (ComfyUI nodes
  get one automatically) follows `test`.
- `ock ship` archives the finished OpenSpec change, runs the checks, pushes, opens the PR — it
  refuses to push if the checks fail. You merge it on GitHub (merge commits only). Branches are deleted only when you
  choose "Delete branch" on the merged PR, and locally only by `ock cleanup`.
- Merging a PR here (opencode-config) deploys it: OpenCode runs `ock kit apply` at startup.
  Try a branch before merging: `ock kit use feat/x`; back: `ock kit use main`.

## Agents and models

| Agent | Does | Model (agent-models.conf) |
|---|---|---|
| main | answers, tiny edits, routes work | OpenCode Go · DeepSeek V4.1 Flash |
| build | implements a change, test first, commits | OpenCode Go · GLM-5.3 Flash |
| spec | OpenSpec changes, roadmaps, ADRs | ChatGPT Plus · GPT-6.1 Sol |
| debugger | root-causes failures | ChatGPT Plus · GPT-6.1 Sol |
| researcher | web research, cited | OpenCode Go · DeepSeek V4.1 Flash |
| resolver | merge conflicts during `ock ship` | ChatGPT Plus · GPT-6.1 Sol |

Change a model: edit `agent-models.conf` on a branch, ship, merge. `ock models` checks them.

## Guard rails (enforced, not just asked for)

- Agents write only inside the current project (and /tmp). Other projects are read-only references;
  `~/.config/opencode` and the live kit are read-only.
- No merging/approving PRs, deleting branches or repos, pushing to `main`/`test`, committing on
  `main`/`test`, or touching rulesets. (The kit's scripts and your own `!` commands aren't limited.)
- AGENTS.md files in folders above a project (e.g. `~/workspace/projects/AGENTS.md`) are ignored.

## Where things live

| | |
|---|---|
| this repo (dev) | `~/workspace/projects/opencode-config` |
| live kit (follows GitHub's main) | `~/workspace/projects/.opencode-workflow-kit` |
| deployed config | `~/.config/opencode` (written by the live kit's `install.sh`; don't edit) |
| web-search keys | `~/.config/opencode-kit/secrets.env` (`EXA_API_KEY=…` lines) |
| kit state and logs | `~/.local/share/opencode-kit` |

Break-glass (the kit itself broken):
`git -C ~/workspace/projects/.opencode-workflow-kit checkout --detach origin/main && ~/workspace/projects/.opencode-workflow-kit/install.sh`

Decisions behind all this: [docs/adr](docs/adr/README.md).
