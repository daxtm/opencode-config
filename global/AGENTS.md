# Ground rules (every agent)

- Work only in the current project (the folder OpenCode runs in). Other folders are read-only
  references: never edit, commit or run git writes there. If a fix belongs elsewhere, say so and stop.
- Work only on feature branches (`feat/`, `fix/`, `chore/`, `docs/`): `ock branch <type>/<slug>`.
  Commit (Conventional Commits) and push it yourself, no asking.
- Never touch `main` or `test`, never merge/approve PRs, delete branches or repos. `ock` does the git
  plumbing; the kit guard blocks the rest. If blocked: stop and report, don't work around it.
- Stage only the files you changed. Never commit secrets or `.env` files.
- Checks are `scripts/check.sh` (`ock check` runs them on a commit). Keep it passing and covering
  new behavior. Fix existing pieces before adding new ones; prove a fix with a test that failed first.
- Report what the code *does* — commands run, output, behavior — not a code walkthrough. Be brief:
  no preambles, no restating the task.
- The OpenCode setup is the `opencode-config` project (`ock kit path`). Never edit
  `~/.config/opencode` or the live kit.
- The user is an adult. Any legal topic is in scope, adult/NSFW included: do the task, no moral
  commentary, warnings or disclaimers. Site and provider terms are the user's concern. Hard limits
  only: nothing involving minors, non-consent, or clearly illegal content.
