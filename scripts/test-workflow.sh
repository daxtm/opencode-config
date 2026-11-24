#!/usr/bin/env bash
# Behavior tests for the workflow scripts — what the user would observe, not just that code parses.
# Runs everything in a throwaway HOME with a fake GitHub (bare git repos behind a stub `gh`) and a
# stub `opencode` (the headless conflict resolver). No network, no credentials. Needs git, node
# (22.6+, for the guard tests) and openspec.
#
# Covers: ock new (new public repo, --private, taking over a repo with no main, a repo that already
# has main, a pi-era project), the `test` rules (only finished work, auto-push, never recreating
# deleted branches), ock ship (refuses unchecked tasks, archives, opens the PR), ock cleanup,
# ock kit, and the kit guard (shell rules + project boundary).
#
# Usage: scripts/test-workflow.sh        (prints one line per check; exit 1 if any fails)
set -uo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
fails=0; passes=0
pass() { passes=$((passes + 1)); echo "  ok   $*"; }
fail() { fails=$((fails + 1)); echo "  FAIL $*"; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }

for c in git node; do command -v "$c" >/dev/null || { echo "test-workflow: $c is required"; exit 1; }; done
if ! command -v openspec >/dev/null; then
	echo "test-workflow: openspec is required (run ock kit apply or install @fission-ai/openspec@2.1.1)" >&2; exit 1
fi

# ---- prompt contract regression: proposal stops before build --------------------------------------
# Named regression for the review boundary (openspec/changes/stop-auto-build, task 1.1).
# Red-first: against the pre-fix main prompt the contract checks below FAIL — the prompt had no
# stop-after-spec rule, only the unqualified "Follow an implementation request through its checks",
# so spec completion could be read as authorizing the build. The /propose and /apply checks are
# preservation checks and must keep passing through the fix.
echo "prompt contract: proposal stops before build"
MAIN="$ROOT/global/agents/main.md"
check "main prompt: spec completion stops for review" \
	grep -qiE 'stops? for review|stop(s|ping)? (after|before) (the )?spec|spec[^.]{0,40}\bstops?\b' "$MAIN"
check "main prompt: a new explicit implementation request is required after the proposal" \
	grep -qiE '(new|fresh|later|separate) (explicit |unambiguous )?(implementation|build) request' "$MAIN"
check "main prompt: the earlier request cannot authorize the proposal" \
	grep -qiE '(cannot|can not|does not|never) authoriz|not authoriz' "$MAIN"
check "main prompt: no unqualified implementation follow-through" \
	bash -c "! grep -q 'Follow an implementation request through its checks' '$MAIN'"
check "/propose still stops for review" grep -qi 'stop for review' "$ROOT/global/commands/propose.md"
check "/propose still never implements" grep -qiE "don.t implement" "$ROOT/global/commands/propose.md"
check "/apply runs the whole change in one build" grep -q "ONE build for the whole change" "$ROOT/global/commands/apply.md"
check "/apply passes the user's steering to the running build" grep -q "follow-up (its sessionID)" "$ROOT/global/commands/apply.md"
check "main prompt: stop means stop (stop_subagents first)" grep -q "call stop_subagents first" "$MAIN"

OCK_REAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"; mkdir -p "$OCK_REAL_CACHE"   # before HOME changes
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
H="$T/home"; GH="$T/github"; STUBS="$T/stubs"; LOG="$T/log"
mkdir -p "$H/.local/bin" "$H/workspace/projects" "$GH/repos" "$GH/prs" "$STUBS" "$LOG"
printf '[user]\n\tname = Test\n\temail = test@example.com\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$H/.gitconfig"

# ---- fake GitHub: `gh` backed by bare repos in $GH/repos ----------------------------------------
cat > "$STUBS/gh" <<'EOF'
#!/usr/bin/env bash
S="${FAKEGH:?}"; echo "gh $*" >> "$S/calls.log"
name_of() { basename "$(git remote get-url origin 2>/dev/null)" .git; }
arg_after() { local want="$1" prev="" a; shift; for a in "$@"; do [[ "$prev" == "$want" ]] && { echo "$a"; return; }; prev="$a"; done; }
case "$1 $2" in
"auth status") exit 0 ;;
"repo view")
	n=""; [[ -n "${3:-}" && "$3" != --* ]] && n="${3##*/}"; n="${n:-$(name_of)}"
	[[ ! -d "$S/repos/$n.git" && -f "$S/redirects/$n" ]] && n="$(cat "$S/redirects/$n")"   # GitHub follows a renamed repo's old name until the name is reused
	b="$S/repos/$n.git"
	[[ -n "$n" && -d "$b" ]] || { echo "Could not resolve to a Repository" >&2; exit 1; }
	case "$(arg_after -q "$@")" in
	.name) echo "$n" ;; *nameWithOwner*) echo "tester/$n" ;; *visibility*) cat "$b.vis" ;; *sshUrl*) echo "$b" ;;
	*defaultBranchRef*) git -C "$b" symbolic-ref --short HEAD 2>/dev/null ;; *) echo "{}" ;;
	esac ;;
"repo create")
	n="$3"; vis=PRIVATE; [[ " $* " == *" --public "* ]] && vis=PUBLIC
	git init -q --bare -b main "$S/repos/$n.git"; echo "$vis" > "$S/repos/$n.git.vis"
	git remote add origin "$S/repos/$n.git" ;;
"api "*|"api -X")
	[[ "$2" == user ]] && { echo tester; exit 0; }
	b="$S/repos/$(name_of).git"; vis="$(cat "$b.vis" 2>/dev/null)"
	if [[ "$*" == *rulesets* ]]; then   # stored as $S/ruleset-<repo>-<name>.json
		if [[ "$*" == *-X* ]]; then
			[[ "$vis" == PUBLIC ]] || { echo '{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature."}' >&2; exit 1; }
			body="$(cat)"; rs="$(grep -o '"name": "[^"]*"' <<<"$body" | head -n1 | cut -d'"' -f4)"
			printf '%s\n' "$body" > "$S/ruleset-$(name_of)-$rs.json"; echo "ruleset applied: $rs ($3)" >> "$S/calls.log"
		else
			rs="$(arg_after -q "$@" | sed -n 's/.*select(.name == "\([^"]*\)").*/\1/p')"
			[[ -n "$rs" && -f "$S/ruleset-$(name_of)-$rs.json" ]] && echo 1
		fi
		exit 0
	fi
	db="$(arg_after -f "$@")"; [[ "$db" == default_branch=* ]] && git -C "$b" symbolic-ref HEAD "refs/heads/${db#default_branch=}"
	[[ " $* " == *" --input - "* ]] && cat >/dev/null
	exit 0 ;;
"pr list") f="$S/prs/$(arg_after --head "$@" | tr / _)"; [[ -f "$f" ]] && head -n1 "$f"; exit 0 ;;
"pr create")
	head="$(arg_after --head "$@")"; n=$(( $(find "$S/prs" -type f | wc -l) + 1 ))
	{ echo "https://github.com/tester/$(name_of)/pull/$n"; cat "$(arg_after --body-file "$@")"; } > "$S/prs/${head//\//_}"
	head -n1 "$S/prs/${head//\//_}" ;;
*) echo "fake gh: unhandled: $*" >&2; exit 1 ;;
esac
EOF
# ---- stub opencode: the headless conflict resolver keeps both sides -----------------------------
cat > "$STUBS/opencode" <<'EOF'
#!/usr/bin/env bash
echo "opencode $*" >> "${FAKEGH:?}/opencode.log"
[[ "$1" == --version ]] && { echo 2.3.2; exit 0; }
[[ "$1 ${2:-}" == "service status" ]] && exit 1
[[ "$1" == service ]] && exit 0
if [[ "$1" == run ]]; then
	for f in $(git diff --name-only --diff-filter=U); do sed -i -E '/^(<{7}|={7}|>{7})( |$)/d' "$f"; git add "$f"; done
	git -c core.hooksPath=/dev/null commit -q --no-edit
fi
EOF
chmod +x "$STUBS/gh" "$STUBS/opencode"
ln -s "$ROOT/bin/ock" "$H/.local/bin/ock"

export HOME="$H" FAKEGH="$GH" OPENSPEC_TELEMETRY=0
export PATH="$STUBS:$H/.local/bin:$PATH" GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GITHUB_ACTIONS
export OCK_INTERNAL=1   # each scenario syncs explicitly; hooks must not race its assertions
export OCK_IN_BEHAVIOR_TESTS=1   # the kit's own check.sh, run by the setup test, must not recurse
P="$H/workspace/projects"
remote_has() { git -C "$GH/repos/$1.git" rev-parse -q --verify "refs/heads/$2" >/dev/null; }
default_of() { git -C "$GH/repos/$1.git" symbolic-ref --short HEAD; }
sync() { ock test "$@" >/dev/null 2>&1; }   # explicit sync; waits for any hook-started one

# ---- ock new -------------------------------------------------------------------------------------
echo "ock new"
(cd "$P" && ock new demo > "$LOG/new-demo.txt" 2>&1); D="$P/demo"
check "new project gets a public GitHub repo" grep -qx PUBLIC "$GH/repos/demo.git.vis"
check "main ruleset applied (PR required)" grep -q "rulesets on: main" "$LOG/new-demo.txt"
check "main ruleset requires no status check (no GitHub Actions)" bash -c "test -f '$GH/ruleset-demo-main.json' && ! grep -q required_status_checks '$GH/ruleset-demo-main.json'"
check "secret push protection turned on" grep -q "push protection on" "$LOG/new-demo.txt"
check "GitHub never auto-deletes branches" grep -q "delete_branch_on_merge=false" "$GH/calls.log"
check "project gets no CI workflow, and an executable local check" bash -c "test ! -e '$D/.github/workflows' && test -x '$D/scripts/check.sh'"
check "setup committed on main passes its own checks" bash -c "cd '$D' && ./scripts/check.sh"
check "test branch exists on GitHub" remote_has demo test

(cd "$P" && ock new secret --private > "$LOG/new-private.txt" 2>&1)
check "--private repo warns that main is unprotected" grep -q UNPROTECTED "$LOG/new-private.txt"

# a repo set up while the kit still required the CI `check`: re-running gh-setup drops the requirement
printf '{"name": "main", "rules": [{"type": "pull_request"}, {"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": "check"}]}}]}\n' > "$GH/ruleset-demo-main.json"
(cd "$D" && ock gh-setup > "$LOG/gh-setup-again.txt" 2>&1)
check "gh-setup replaces the existing main ruleset" grep -q 'ruleset applied: main (PUT)' "$GH/calls.log"
check "gh-setup removes an old required CI check" bash -c "! grep -q required_status_checks '$GH/ruleset-demo-main.json'"

# takeover: a repo on GitHub whose only branch is chore/repo-baseline (no main, no test)
git init -q --bare -b chore/repo-baseline "$GH/repos/legacy.git"; echo PUBLIC > "$GH/repos/legacy.git.vis"
git clone -q "$GH/repos/legacy.git" "$T/seed" 2>/dev/null
(cd "$T/seed" && echo "old work" > notes.txt && git add -A && git commit -q -m "old work" && git push -q origin chore/repo-baseline 2>/dev/null)
git clone -q "$GH/repos/legacy.git" "$P/legacy" 2>/dev/null
base_sha="$(git -C "$P/legacy" rev-parse HEAD)"
git -C "$P/legacy" switch -q -c main
git -C "$P/legacy" commit -q --allow-empty -m 'local-only work'
git -C "$P/legacy" switch -q chore/repo-baseline
(cd "$P/legacy" && ock new > "$LOG/new-takeover.txt" 2>&1)
check "takeover: main created on GitHub from the old default branch" test "$(git -C "$GH/repos/legacy.git" rev-parse main 2>/dev/null)" = "$base_sha"
check "takeover: old branch untouched" test "$(git -C "$GH/repos/legacy.git" rev-parse chore/repo-baseline)" = "$base_sha"
check "takeover: main is now the default branch" test "$(default_of legacy)" = main
check "takeover: test branch exists" remote_has legacy test
check "takeover: setup arrives as a PR (nothing pushed to main)" bash -c "ls '$GH/prs' | grep -q chore_kit-setup && test \"\$(git -C '$GH/repos/legacy.git' rev-parse main)\" = '$base_sha'"
check "takeover: rulesets applied" grep -q "rulesets on: main" "$LOG/new-takeover.txt"

# a repo that already has main: just the setup PR
(cd "$P/demo" && ock new > "$LOG/new-again.txt" 2>&1)
check "re-running ock new on a set-up repo changes nothing" grep -q "nothing to ship" "$LOG/new-again.txt"

# ---- test branch + ship ----------------------------------------------------------------------------
echo "test branch, ship"
cd "$D" || exit 1
ock branch feat/add-hello >/dev/null 2>&1
mkdir -p openspec/changes/add-hello/specs/hello bin
printf '## Why\nThe demo needs a visible first feature so the owner can see the workflow end to end.\n\n## What Changes\n- Add bin/hello.\n' > openspec/changes/add-hello/proposal.md
printf '## Purpose\nPrint a friendly greeting so the owner can see the project running.\n\n## ADDED Requirements\n\n### Requirement: Greeting\nThe system SHALL print hello.\n\n#### Scenario: Run it\n- **WHEN** the user runs bin/hello\n- **THEN** it prints hello\n' > openspec/changes/add-hello/specs/hello/spec.md
printf -- '- [ ] 1.1 Add bin/hello ([x] is the done marker)\n' > openspec/changes/add-hello/tasks.md
git add -A && git commit -q -m "docs(openspec): propose add-hello"; sync
check "feature branch pushed to GitHub without anyone pushing" test "$(git rev-parse feat/add-hello)" = "$(git -C "$GH/repos/demo.git" rev-parse feat/add-hello 2>/dev/null)"
check "unfinished feature kept out of test" bash -c "! git merge-base --is-ancestor feat/add-hello test"
st="$(ock status 2>&1)"
check "status lists it as waiting (0/1 tasks)" grep -q 'waiting.*feat/add-hello (add-hello: 0/1 tasks)' <<<"$st"
check "ship refuses unchecked tasks" bash -c "! ock ship"
printf '#!/bin/bash\nset -eu\ntest "$(bin/hello)" = hello\n' > scripts/check.sh
printf '#!/bin/sh\necho hello\n' > bin/hello; chmod +x bin/hello; sed -i 's/- \[ \]/- [x]/' openspec/changes/add-hello/tasks.md
git add -A && git commit -q -m "feat: hello"; sync
check "finished feature joins test" git merge-base --is-ancestor feat/add-hello test
ock ship > "$LOG/ship.txt" 2>&1
check "ship opens the PR" grep -q "PR opened" "$LOG/ship.txt"
check "ship archived the change" test -d "$(ls -d openspec/changes/archive/*-add-hello 2>/dev/null | head -n1)"
check "PR body carries the proposal" grep -q '^### Why' "$GH/prs/feat_add-hello"
ock branch fix/greeting >/dev/null 2>&1; echo "greeting fix" > GREETING.md; git add GREETING.md; git commit -q -m "fix: greeting"; sync
check "fix/ branch joins test right away" bash -c "test \"\$(git rev-parse fix/greeting)\" != \"\$(git rev-parse origin/main)\" && git merge-base --is-ancestor fix/greeting test"

# ---- merge on GitHub, cleanup -------------------------------------------------------------------
echo "cleanup"
gh_merge() { # repo branch [keep] — "Create a merge commit"; deletes the branch unless keep
	local c="$T/merge-$RANDOM"; git clone -q "$GH/repos/$1.git" "$c" 2>/dev/null
	git -C "$c" -c core.hooksPath=/dev/null merge -q --no-ff "origin/$2" -m "Merge pull request from $2" && git -C "$c" push -q origin main 2>/dev/null
	[[ "${3:-}" == keep ]] || git -C "$GH/repos/$1.git" branch -q -D "$2"; rm -rf "$c"
}
gh_merge demo feat/add-hello; gh_merge demo fix/greeting keep
git switch -q main; sync --fetch
check "sync never deletes branches" git rev-parse -q --verify refs/heads/feat/add-hello
check "cleanup --dry-run lists the deleted one, deletes nothing" bash -c "ock cleanup --dry-run | grep -q 'would delete feat/add-hello' && git rev-parse -q --verify refs/heads/feat/add-hello"
git branch -q local-wip
ock cleanup >/dev/null 2>&1
check "cleanup deletes a branch gone from GitHub" bash -c "! git rev-parse -q --verify refs/heads/feat/add-hello"
check "cleanup keeps a merged branch you kept on GitHub" git rev-parse -q --verify refs/heads/fix/greeting
check "cleanup never touches a never-pushed branch" git rev-parse -q --verify refs/heads/local-wip
git branch -q feat/gone origin/main; git push -q -u origin feat/gone 2>/dev/null; git switch -q feat/gone; echo pending > pending; git add pending; git commit -q -m pending; git switch -q main
git -C "$GH/repos/demo.git" branch -q -D feat/gone
sync
check "a branch you deleted on GitHub is never pushed back" bash -c "! git -C '$GH/repos/demo.git' rev-parse -q --verify refs/heads/feat/gone"
ock cleanup >/dev/null
check "cleanup preserves unpublished commits on a gone branch" git show feat/gone:pending
check "test contains everything merged to main" git merge-base --is-ancestor origin/main test

# ---- ock kit -----------------------------------------------------------------------------------
echo "ock kit"
git init -q --bare -b main "$GH/repos/opencode-config.git"
K="$P/opencode-config"; git clone -q "$GH/repos/opencode-config.git" "$K" 2>/dev/null
printf '#!/usr/bin/env bash\necho installed > "$HOME/installed-from"; git -C "$(dirname "$0")" rev-parse HEAD >> "$HOME/installed-from"\n' > "$K/install.sh"; chmod +x "$K/install.sh"
git -C "$K" add -A; git -C "$K" commit -q -m init; git -C "$K" push -q -u origin main 2>/dev/null
LIVEK="$P/.opencode-workflow-kit"; git clone -q "$GH/repos/opencode-config.git" "$LIVEK" 2>/dev/null
export OCK_LIVE="$LIVEK" OCK_DEV="$K"
"$ROOT/bin/ock" kit apply > "$LOG/kit-apply.txt" 2>&1
check "ock kit apply runs the live kit's install.sh" grep -qx installed "$H/installed-from"
git -C "$K" switch -q -c chore/try; echo x > "$K/x"; git -C "$K" add x; git -C "$K" commit -q -m try; git -C "$K" push -q -u origin chore/try 2>/dev/null
"$ROOT/bin/ock" kit use chore/try >/dev/null 2>&1
check "ock kit use deploys a branch to try" test -f "$LIVEK/x"
gh_merge opencode-config chore/try
"$ROOT/bin/ock" kit apply --if-changed --quiet >/dev/null 2>&1
check "after merging, the kit goes back to following main" bash -c "'$ROOT/bin/ock' kit status | grep -q 'follows main'"
check "main's merge is deployed" test "$(git -C "$LIVEK" rev-parse HEAD)" = "$(git -C "$GH/repos/opencode-config.git" rev-parse main)"
check "an edited live kit refuses to deploy" bash -c "echo edit >> '$LIVEK/install.sh' && ! '$ROOT/bin/ock' kit apply"
git -C "$LIVEK" checkout -q -- install.sh
# A failed installation leaves the checkout at the requested SHA: checkout equality isn't success.
git -C "$K" switch -q -c chore/retry origin/main
cat > "$K/install.sh" <<'EOF'
#!/usr/bin/env bash
echo attempt >> "$HOME/install-attempts"
[[ -f "$HOME/allow-install" ]]
EOF
git -C "$K" add install.sh; git -C "$K" commit -q -m 'installer retry fixture'; git -C "$K" push -q -u origin chore/retry 2>/dev/null
check "ock kit reports an installation failure" bash -c "! '$ROOT/bin/ock' kit use chore/retry"
check "status reports a failed install at the current checkout" grep -q 'installation pending' <<<"$("$ROOT/bin/ock" kit status)"
touch "$H/allow-install"
"$ROOT/bin/ock" kit apply --if-changed --quiet > "$LOG/kit-retry.txt" 2>&1
check "ock kit retries a failed installation at the same SHA" test "$(wc -l < "$H/install-attempts")" = 2
"$ROOT/bin/ock" kit apply --if-changed --quiet >/dev/null 2>&1
check "ock kit skips a successfully installed unchanged SHA" test "$(wc -l < "$H/install-attempts")" = 2
unset OCK_LIVE OCK_DEV

# ---- a pi-era project is taken over ----------------------------------------------------------------
echo "pi-era takeover"
Q="$P/old-pi"; git init -q -b main "$Q"; git -C "$Q" commit -q --allow-empty -m base
mkdir -p "$Q/.git/hooks"; printf '#!/bin/sh\n( pi-test-branch --quiet & ) # pi-workflow-kit\n' > "$Q/.git/hooks/post-commit"; chmod +x "$Q/.git/hooks/post-commit"
git -C "$Q" config pi.kit true; git -C "$Q" config pi.live.restart "echo restarted"
(cd "$Q" && ock new > "$LOG/new-pi-era.txt" 2>&1)
check "pi-era: the pi hook line is replaced by the kit's" bash -c "! grep -q pi-workflow-kit '$Q/.git/hooks/post-commit' && grep -q '# opencode-kit' '$Q/.git/hooks/post-commit'"
check "pi-era: pi settings carry over" test "$(git -C "$Q" config kit.live.restart)" = "echo restarted"
check "pi-era: no CI workflow added" test ! -e "$Q/.github/workflows/ci.yml"

# ---- recovery regressions ----------------------------------------------------------------------
echo "recovery"
cd "$D" || exit 1
ock branch fix/missing-tasks >/dev/null 2>&1
mkdir -p openspec/changes/missing-tasks
echo '## Why' > openspec/changes/missing-tasks/proposal.md
git add openspec; git commit -q -m 'propose without tasks'; sync
check "active change without tasks stays out of test" bash -c '! git merge-base --is-ancestor fix/missing-tasks test'

# Rebuild's zero-merge path must discard an old test tip, including in its live worktree.
R="$P/rebuild"; git init -q --bare -b main "$GH/repos/rebuild.git"
git clone -q "$GH/repos/rebuild.git" "$R" 2>/dev/null
cd "$R" || exit 1
echo base > base; mkdir -p scripts; printf '#!/bin/bash\ngrep -qx base base\n' > scripts/check.sh; chmod +x scripts/check.sh
git add scripts base; git commit -q -m base; git push -q -u origin main 2>/dev/null
git switch -q -c fix/abandoned; echo abandoned > abandoned; git add abandoned; git commit -q -m abandoned
sync; ock live set "$T/rebuild-live" >/dev/null 2>&1
git worktree add -q "$T/rebuild-test-checkout" test
git switch -q main; git branch -q -D fix/abandoned
# Remove the branch remotely, as an owner would; rebuild fetches/prunes before syncing.
git -C "$GH/repos/rebuild.git" branch -q -D fix/abandoned
old_test="$(git rev-parse test)"; echo 'user edit' > "$T/rebuild-test-checkout/base"
check "rebuild refuses a test checkout with tracked edits" bash -c '! ock test rebuild'
check "refusal preserves the test branch tip" test "$(git rev-parse test)" = "$old_test"
check "refusal preserves user edits" grep -qx 'user edit' "$T/rebuild-test-checkout/base"
git -C "$T/rebuild-test-checkout" restore base
ock test rebuild > "$LOG/rebuild.txt" 2>&1
check "rebuild with nothing eligible resets local test to main" test "$(git rev-parse test)" = "$(git rev-parse main)"
check "rebuild with nothing eligible resets remote test to main" test "$(git -C "$GH/repos/rebuild.git" rev-parse test)" = "$(git rev-parse main)"
check "rebuild updates the live worktree" test ! -e "$T/rebuild-live/abandoned"
check "rebuild updates a clean checkout of test" test ! -e "$T/rebuild-test-checkout/abandoned"

# --no-github must not create remote main, call gh or push any branch.
git init -q --bare -b legacy "$GH/repos/offline.git"; echo PUBLIC > "$GH/repos/offline.git.vis"
git clone -q "$GH/repos/offline.git" "$P/offline" 2>/dev/null
cd "$P/offline" || exit 1
echo base > base; mkdir -p scripts; printf '#!/bin/bash\ngrep -qx base base\n' > scripts/check.sh; chmod +x scripts/check.sh
git add scripts base; git commit -q -m base; git push -q -u origin legacy 2>/dev/null
before_refs="$(git -C "$GH/repos/offline.git" show-ref)"; before_calls="$(wc -l < "$GH/calls.log")"
echo 'user work' > unrelated.txt
ock new --no-github > "$LOG/new-offline.txt" 2>&1
check "ock new --no-github succeeds on an existing remote project" grep -q 'Next:' "$LOG/new-offline.txt"
check "ock new --no-github leaves all remote refs unchanged" test "$(git -C "$GH/repos/offline.git" show-ref)" = "$before_refs"
check "ock new --no-github makes no GitHub API calls" test "$(wc -l < "$GH/calls.log")" = "$before_calls"
check "ock new keeps unrelated user files untracked" test "$(git ls-files -- unrelated.txt)" = ''
check "ock new leaves unrelated user file contents intact" grep -qx 'user work' unrelated.txt

# Local projects on master, without any GitHub repo yet, must publish the setup.
L="$P/local-first"; git init -q -b master "$L"
git -C "$L" commit --allow-empty -qm base
(cd "$L" && ock new > "$LOG/local-first" 2>&1)
check "first publication includes setup on remote main" git -C "$GH/repos/local-first.git" cat-file -e main:scripts/check.sh
check "first publication retains local master" git -C "$L" rev-parse --verify master
check "local-only legacy setup creates usable main and test" git -C "$P/offline" rev-parse --verify test
(cd "$P/offline" && ock branch feat/offline > "$LOG/branch-offline" 2>&1)
check "offline proposal can start a feature branch" test "$(git -C "$P/offline" branch --show-current)" = feat/offline
check "offline feature inherits the locally installed project checks" git -C "$P/offline" cat-file -e HEAD:scripts/check.sh
check "offline proposal leaves remote refs unchanged" test "$(git -C "$GH/repos/offline.git" show-ref)" = "$before_refs"

# Only workflow branches enter test. Git must refuse to overwrite a user's untracked file.
cd "$R" || exit 1
git switch -q -c scratch/experiment main
echo experiment > experiment; git add experiment; git commit -qm experiment; sync
check "scratch branches stay out of test" bash -c '! git merge-base --is-ancestor scratch/experiment test'
git switch -q -c fix/collision main
echo feature > collision; git add collision; git commit -qm collision
echo personal > "$T/rebuild-test-checkout/collision"
old_test="$(git rev-parse test)"
check "sync refuses to overwrite an untracked test checkout file" bash -c '! ock test'
check "untracked checkout file survives sync" grep -qx personal "$T/rebuild-test-checkout/collision"
check "collision leaves test at its old tip" test "$(git rev-parse test)" = "$old_test"
rm -f "$T/rebuild-test-checkout/collision"
sync
check "sync recovers after the collision is cleared" git merge-base --is-ancestor fix/collision test

# A rejected remote rebuild must return failure; retrying should publish the rebuilt tip.
printf '#!/bin/sh\nexit 1\n' > "$GH/repos/rebuild.git/hooks/pre-receive"
chmod +x "$GH/repos/rebuild.git/hooks/pre-receive"
git switch -q main; git branch -q -D fix/collision; git -C "$GH/repos/rebuild.git" branch -q -D fix/collision
check "rebuild reports a remote push rejection" bash -c '! ock test rebuild'
rm "$GH/repos/rebuild.git/hooks/pre-receive"
ock test rebuild >/dev/null 2>&1
check "retry publishes the intended rebuild" test "$(git -C "$GH/repos/rebuild.git" rev-parse test)" = "$(git rev-parse test)"
# A clean clone rebuilding test keeps finished remote work even without a local checkout.
git clone -q "$GH/repos/rebuild.git" "$T/second-machine"
git -C "$T/second-machine" switch -qc fix/remote-only
git -C "$T/second-machine" commit --allow-empty -qm remote-work
git -C "$T/second-machine" push -qu origin fix/remote-only
remote_only="$(git -C "$T/second-machine" rev-parse HEAD)"
ock test rebuild >/dev/null 2>&1
check "rebuild keeps eligible branches published by another clone" git merge-base --is-ancestor "$remote_only" test
before_preview="$(git -C "$GH/repos/rebuild.git" show-ref)"
old_test="$(git rev-parse test)"
ock test rebuild --dry-run > "$LOG/preview" 2>&1
check "rebuild preview reports the target branch" grep -q 'would rebuild test' "$LOG/preview"
check "rebuild preview preserves local test" test "$(git rev-parse test)" = "$old_test"
check "rebuild preview preserves remote refs" test "$(git -C "$GH/repos/rebuild.git" show-ref)" = "$before_preview"

# An existing user's file and a failed adoption must stay where they were.
mkdir -p "$T/custom dir"
echo sentinel > "$T/custom dir/sentinel"
check "missing live branch is reported" bash -c " ! ock live set --adopt '$T/custom dir' no-such-branch"
check "failed adoption preserves the existing folder" grep -qx sentinel "$T/custom dir/sentinel"
(cd "$R" && ock branch fix/remote-only >"$LOG/remote-checkout" 2>&1)
check "ock branch resumes an existing remote branch" test "$(git rev-parse HEAD)" = "$remote_only"
cd "$R" || exit 1
git switch -qc fix/incompatible origin/main
printf '#!/bin/bash\ntest ! -e other\n' > scripts/check.sh
git add scripts/check.sh; git commit -qm constraint
sync
good="$(git rev-parse test)"
git switch -qc fix/other origin/main; touch other; git add other; git commit -qm other
check "individual branch passes local checks" "$ROOT/bin/ock-check" HEAD
check "combined failure blocks preview" bash -c '! ock test sync'
check "combined failure keeps last passing preview" test "$(git rev-parse test)" = "$good"
printf '#!/bin/bash\nexit 1\n' > scripts/check.sh
git add scripts/check.sh; git commit -qm broken
check "ship refuses failing candidate" bash -c '! ock ship'
check "failed ship creates no PR" test ! -e "$GH/prs/fix_other"
C="$T/preview-conflict"
git init -qb main "$C"; cd "$C" || exit 1
mkdir scripts
printf '#!/bin/sh\ntest -s common.txt\n' > scripts/check.sh; chmod +x scripts/check.sh
echo base > common.txt; git add .; git commit -qm base
git switch -qc fix/first
echo first > common.txt; git commit -qam first
sync
good="$(git rev-parse test)"
git switch -qc fix/second main
echo second > common.txt; git commit -qam second
check "new preview conflict stops sync" bash -c '! ock test sync'
check "new preview conflict preserves last passing commit" test "$(git rev-parse test)" = "$good"
check "new preview conflict never invokes the model" test ! -e .git/ock-test-resolve.log
# ---- setup.sh: first-time setup on a machine with the old setup's leftovers ------------------------
echo "setup"
SH="$T/setup-home"; SGH="$T/github-setup"; mkdir -p "$SH/workspace/projects" "$SH/.config/pi-kit" "$SGH/repos" "$SGH/prs"
cp "$H/.gitconfig" "$SH/.gitconfig"
printf 'EXA_API_KEY=abc\n' > "$SH/.config/pi-kit/secrets.env"
ln -s "$SH/workspace/projects/opencode-config-moved-away/config" "$SH/.config/opencode"   # dangling, as on the real machine
echo "stray pinew file" > "$SH/workspace/projects/AGENTS.md"
SD="$SH/workspace/projects/opencode-config"; mkdir -p "$SD"
(cd "$ROOT" && git ls-files -z --cached --others --exclude-standard | xargs -0 cp --parents -t "$SD")
git -C "$SD" init -q -b main; git -C "$SD" add -A; HOME="$SH" git -C "$SD" commit -q -m "opencode-config"
git -C "$SD" remote add origin "$T/opencode-config.bundle"
git init -q --bare -b main "$SGH/repos/opencode-config.git"; echo PUBLIC > "$SGH/repos/opencode-config.git.vis"
(cd "$SD" && HOME="$SH" FAKEGH="$SGH" OCK_SKIP_NPM=1 ./setup.sh --dry-run > "$LOG/setup-taken.txt" 2>&1)
check "setup stops while GitHub has another opencode-config" grep -q 'already has tester/opencode-config' "$LOG/setup-taken.txt"
mv "$SGH/repos/opencode-config.git" "$SGH/repos/opencode-config-old.git"; mv "$SGH/repos/opencode-config.git.vis" "$SGH/repos/opencode-config-old.git.vis"
mkdir -p "$SGH/redirects"; echo opencode-config-old > "$SGH/redirects/opencode-config"   # renamed, as the user did
(cd "$SD" && HOME="$SH" FAKEGH="$SGH" OCK_SKIP_NPM=1 ./setup.sh --dry-run > "$LOG/setup-dry.txt" 2>&1)
check "setup --dry-run succeeds" grep -q 'dry run — nothing was changed' "$LOG/setup-dry.txt"
check "setup --dry-run changes nothing" bash -c "test -L '$SH/.config/opencode' && test ! -e '$SGH/repos/opencode-config.git' && test ! -e '$SH/workspace/projects/.opencode-workflow-kit'"
(cd "$SD" && HOME="$SH" FAKEGH="$SGH" OCK_SKIP_NPM=1 ./setup.sh > "$LOG/setup.txt" 2>&1)
check "setup succeeds" grep -q '^Done\.' "$LOG/setup.txt"
check "setup: the dangling ~/.config/opencode link is replaced by the deployed config" bash -c "test ! -L '$SH/.config/opencode' && test -f '$SH/.config/opencode/opencode.jsonc' && test -f '$SH/.config/opencode/plugins/kit.ts'"
check "setup: the renamed old repo is left alone" test -z "$(git -C "$SGH/repos/opencode-config-old.git" for-each-ref)"
check "setup: opencode-config is a public GitHub repo with rulesets" bash -c "grep -qx PUBLIC '$SGH/repos/opencode-config.git.vis' && ls '$SGH'/ruleset-opencode-config-*.json"
check "setup: the live kit follows GitHub's main" test "$(git -C "$SH/workspace/projects/.opencode-workflow-kit" rev-parse HEAD)" = "$(git -C "$SGH/repos/opencode-config.git" rev-parse main)"
check "setup: ock is on PATH, from the live kit" test "$(readlink "$SH/.local/bin/ock")" = "$SH/workspace/projects/.opencode-workflow-kit/bin/ock"
check "setup: the deployed config points at the live kit" grep -q "$SH/workspace/projects/.opencode-workflow-kit" "$SH/.config/opencode/plugins/kit.ts"
check "setup: web-search keys copied (private), old file kept" bash -c "test \"\$(stat -c %a '$SH/.config/opencode-kit/secrets.env')\" = 600 && test -f '$SH/.config/pi-kit/secrets.env'"
check "setup: the keys reach OpenCode's service" grep -q 'service set env EXA_API_KEY abc' "$SGH/opencode.log"
check "setup: nothing in ~/workspace/projects is removed" test -f "$SH/workspace/projects/AGENTS.md"
check "setup: points out the stray AGENTS.md" grep -q 'contains AGENTS.md' "$LOG/setup.txt"
(cd "$SD" && HOME="$SH" FAKEGH="$SGH" OCK_SKIP_NPM=1 ./setup.sh > "$LOG/setup-again.txt" 2>&1)
check "setup can be re-run" grep -q '^Done\.' "$LOG/setup-again.txt"
check "the kit reports itself up to date" bash -c "HOME='$SH' '$SH/.local/bin/ock' kit status | grep -q 'up to date'"

# ---- ock usage: reads OpenCode's records ---------------------------------------------------------
echo "ock usage"
UH="$T/usage-home"; mkdir -p "$UH/.local/share/opencode"
python3 - "$UH/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
c = sqlite3.connect(sys.argv[1]); now = int(time.time() * 1000)
c.execute("create table session_v2 (id text, title text, parent_id text)")
c.execute("create table session_message (id text, session_id text, type text, time_created integer, data text)")
c.executemany("insert into session_v2 values (?,?,?)", [("ses_root1", "Implement GUI setup", None), ("ses_child1", "build: task 1", "ses_root1")])
msg = lambda sid, agent, model, variant, fresh, cached: (sid + agent, sid, "assistant", now, json.dumps({"agent": agent,
    "model": {"providerID": "opencode-go", "id": model, "variant": variant}, "tokens": {"input": fresh, "output": 500, "reasoning": 100, "cache": {"read": cached, "write": 0}}}))
c.executemany("insert into session_message values (?,?,?,?,?)", [msg("ses_child1", "build", "glm-5.3-flash", "high", 1000, 300000),
    msg("ses_root1", "main", "deepseek-v4.1-flash", "max", 2000, 50000), ("u1", "ses_root1", "user", now, "{}")])
c.commit()
PY
HOME="$UH" "$ROOT/bin/ock" usage 7 > "$LOG/usage.txt" 2>&1
check "ock usage: totals per agent and model, variant included" grep -q 'build  opencode-go/glm-5.3-flash#high .* 1 .*301.0k' "$LOG/usage.txt"
check "ock usage: subagents count toward the session that started them" grep -q 'Implement GUI setup (_root1) .* 2 ' "$LOG/usage.txt"
check "ock usage: largest request listed first" bash -c "grep -A1 'Largest single requests' '$LOG/usage.txt' | grep -q '301.0k in .*build'"

# ---- kit guard ---------------------------------------------------------------------------------
echo "guards"
# The guard lets writes into /tmp through, so its fixtures must live outside /tmp (and `ock check`
# runs this from a checkout under /tmp, so not next to the repo either).
GT="$(mktemp -d "${OCK_REAL_CACHE:?}/ock-test-guard.XXXXXX")"; trap 'rm -rf "$T" "$GT"' EXIT
G_SRC="$GT/kit-guard.mts"; sed "s|{{KIT_DIR}}|$GT/kit|g" "$ROOT/global/plugins/kit.ts" > "$G_SRC"
mkdir -p "$GT/kit" "$GT/proj" "$GT/other" "$GT/home/.config/opencode"
git -C "$GT/proj" init -q -b main; git -C "$GT/proj" commit -q --allow-empty -m base; git -C "$GT/proj" switch -q -c feat/x
git -C "$GT/other" init -q -b main; git -C "$GT/other" commit -q --allow-empty -m base
git init -q -b main "$GT/onmain"; git -C "$GT/onmain" commit -q --allow-empty -m base
cat > "$T/guard.mjs" <<'EOF'
const [src, proj, other, onmain, home, kit] = process.argv.slice(2)
await import(src)
const blocked = globalThis.__ockKitGuard
const cases = [ // [command, project root, should block]
  ["gh pr merge 3 --merge", proj, true], ["gh repo delete o/r --yes", proj, true],
  ["git push origin main", proj, true], ["git push origin --delete feat/x", proj, true],
  ["git branch -D feat/x", proj, true], ["gh api -X DELETE repos/o/r/rulesets/5", proj, true],
  ["git push -u origin feat/x", proj, false], ["gh pr create --base main --head feat/x", proj, false],
  ["ock ship", proj, false], ["git commit -m wip", proj, false], ["git commit -m wip", onmain, true],
  [`echo hi > ${other}/f.txt`, proj, true], [`echo hi >> ${other}/f.txt`, proj, true],
  [`cat ${other}/README.md > notes.txt`, proj, false], [`cp notes.txt ${other}/`, proj, true],
  [`cp ${other}/README.md docs/`, proj, false], [`git -C ${other} commit -am x`, proj, true],
  [`git -C ${other} log --oneline`, proj, false], [`cd ${other} && git add -A`, proj, true],
  [`cd ${other} && ls`, proj, false], [`sed -i s/a/b/ ${other}/x`, proj, true],
  [`rm -rf ${other}/build`, proj, true], ["rm -rf build", proj, false],
  ["echo x > /tmp/scratch.txt", proj, false], ["make test 2>&1 | tee /tmp/log", proj, false],
  ["npm test > /dev/null 2>&1", proj, false], [`echo x > ${home}/.config/opencode/AGENTS.md`, proj, true],
  [`touch ${kit}/install.sh`, proj, true], [`echo x | tee ~/notes.txt`, proj, true],
]
let bad = 0
for (const [cmd, root, want] of cases) {
  const got = !!blocked(cmd, root)
  if (got !== want) { bad++; console.log(`guard wrong (${want ? "should block" : "should allow"}): ${cmd}`) }
}
process.exit(bad ? 1 : 0)
EOF
if HOME="$GT/home" node --experimental-strip-types --no-warnings "$T/guard.mjs" "$G_SRC" "$GT/proj" "$GT/other" "$GT/onmain" "$GT/home" "$GT/kit" > "$LOG/guard.txt" 2>&1; then
	pass "kit guard blocks prohibited git/GitHub operations and writes outside the project"
else
	fail "kit guard:"; sed 's/^/         /' "$LOG/guard.txt"
fi

echo
echo "workflow tests: $passes passed, $fails failed"
(( fails == 0 ))
