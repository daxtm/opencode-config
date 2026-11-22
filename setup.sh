#!/usr/bin/env bash
# setup.sh — first-time setup of opencode-config on this machine. Run it from the dev repo
# (~/workspace/projects/opencode-config). Safe to re-run: finished steps are skipped.
#
#   1. OpenCode v2 (curl -fsSL https://opencode.ai/v2/install | bash), unless v2 is installed
#   2. ~/.config/opencode: a dangling symlink there (left by the old setup) is removed — only the
#      link, never what it pointed to. Anything else there is kept (install.sh saves a copy of any
#      file it has to replace).
#   3. OpenSpec CLI (pinned) for the kit
#   4. GitHub: this repo becomes the PUBLIC repo `opencode-config` (ock new: rulesets,
#      `test` branch, hooks)
#   5. the live kit ~/workspace/projects/.opencode-workflow-kit: a clone of GitHub's opencode-config
#      that follows main; `ock kit apply` deploys it into ~/.config/opencode
#   6. web-search keys: ~/.config/pi-kit/secrets.env is copied to ~/.config/opencode-kit/secrets.env
#      if the new one doesn't exist yet (the old file stays)
# Nothing in ~/workspace/projects is moved or deleted, and no other project is touched.
#
# Usage: ./setup.sh [--dry-run]     --dry-run: say what would happen, change nothing
set -euo pipefail

DRY=0
case "${1:-}" in --dry-run) DRY=1 ;; "") ;; *) echo "usage: setup.sh [--dry-run]" >&2; exit 2 ;; esac
DEV="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LIVE="$HOME/workspace/projects/.opencode-workflow-kit"
CONFIG="$HOME/.config/opencode"
STATE="$HOME/.local/share/opencode-kit"
OPENSPEC_VERSION="2.1.1"
REPO_NAME="opencode-config"

say() { echo "setup: $*"; }
do_() { if (( DRY )); then echo "setup: would run: $*"; else "$@"; fi; }
die() { echo "setup: STOP — $*" >&2; exit 1; }

# ---- preflight: everything that could stop us, before changing anything -------------------------
[[ "$DEV" == "$HOME/workspace/projects/$REPO_NAME" ]] || die "run this from ~/workspace/projects/$REPO_NAME (it is in $DEV)"
for c in git gh node npm curl python3 flock; do command -v "$c" >/dev/null || die "$c is not installed"; done
gh auth status >/dev/null 2>&1 || die "gh isn't logged in — run: gh auth login"
node -e 'const [a, b] = process.versions.node.split(".").map(Number); process.exit(a > 22 || (a === 22 && b >= 6) ? 0 : 1)' \
	|| say "WARNING: Node.js $(node --version) is older than 22.6 — the kit's own checks need 22.6+ (projects are unaffected)"
owner="$(gh api user -q .login)"
origin="$(git -C "$DEV" remote get-url origin 2>/dev/null || true)"
if [[ -z "$origin" || "$origin" == *.bundle ]]; then
	# A renamed repo keeps a redirect from its old name: only a repo really named opencode-config counts.
	if [[ "$(gh repo view "$owner/$REPO_NAME" --json name -q .name 2>/dev/null || true)" == "$REPO_NAME" ]]; then
		die "GitHub already has $owner/$REPO_NAME (the old one?). Rename it first, e.g.:
       gh repo rename ${REPO_NAME}-old -R $owner/$REPO_NAME --yes
     then run this again."
	fi
fi
live_origin="$(git -C "$LIVE" remote get-url origin 2>/dev/null || true)"
if [[ -e "$LIVE" ]] && ! [[ -d "$LIVE/.git" && -n "$live_origin" && "$live_origin" == "$(git -C "$DEV" remote get-url origin 2>/dev/null)" ]]; then
	die "$LIVE already exists and isn't a clone of $owner/$REPO_NAME (the old kit?). Move it away first, e.g.:
       mv \"$LIVE\" \"$HOME/workspace/projects/Old/.opencode-workflow-kit-old\""
fi
if [[ -L "$CONFIG" && -e "$CONFIG" ]]; then
	die "$CONFIG is a symlink to $(readlink "$CONFIG") — remove that link yourself (rm \"$CONFIG\"), then run this again"
fi

# ---- 1. OpenCode v2 -------------------------------------------------------------------------------
oc="$(command -v opencode || true)"; [[ -n "$oc" ]] || oc="$HOME/.opencode/bin/opencode"
have="$("$oc" --version 2>/dev/null | head -n1 || true)"
if [[ "$have" =~ (^|[^0-9])2\.[0-9]+ ]]; then
	say "OpenCode $have already installed"
else
	say "installing OpenCode v2 (was: ${have:-none})"
	if (( DRY )); then echo "setup: would run: curl -fsSL https://opencode.ai/v2/install | bash"
	else curl -fsSL https://opencode.ai/v2/install | bash; fi
	oc="$HOME/.opencode/bin/opencode"
fi

# ---- 2. ~/.config/opencode ------------------------------------------------------------------------
if [[ -L "$CONFIG" && ! -e "$CONFIG" ]]; then
	say "removing the dangling symlink $CONFIG → $(readlink "$CONFIG") (only the link)"
	do_ rm -- "$CONFIG"
fi

# ---- 3. OpenSpec ----------------------------------------------------------------------------------
if [[ -z "${OCK_SKIP_NPM:-}" && "$("$STATE/npm/node_modules/.bin/openspec" --version 2>/dev/null || true)" != "$OPENSPEC_VERSION" ]]; then
	say "installing OpenSpec $OPENSPEC_VERSION into $STATE/npm"
	do_ mkdir -p "$STATE/npm"
	do_ npm install --silent --no-fund --no-audit --prefix "$STATE/npm" "@fission-ai/openspec@$OPENSPEC_VERSION"
fi

# ---- 4. GitHub ------------------------------------------------------------------------------------
if [[ "$origin" == *.bundle ]]; then
	say "forgetting the bundle this repo was cloned from"
	do_ git -C "$DEV" remote remove origin
fi
if [[ -z "$origin" || "$origin" == *.bundle ]]; then
	say "publishing $DEV as the public GitHub repo $owner/$REPO_NAME (includes one run of the kit's own checks: a few minutes)"
	do_ env OCK_NEW_NO_NEXT=1 "$DEV/bin/ock" new "$DEV"
else
	say "GitHub remote already set ($origin)"
fi

# ---- 5. live kit + deploy -------------------------------------------------------------------------
if [[ ! -e "$LIVE" ]]; then
	say "creating the live kit $LIVE (follows GitHub's main)"
	url="$(git -C "$DEV" remote get-url origin 2>/dev/null || true)"
	[[ -n "$url" && "$url" != *.bundle ]] || url="https://github.com/$owner/$REPO_NAME.git"
	do_ git clone -q "$url" "$LIVE"
fi

# ---- 6. web-search keys ---------------------------------------------------------------------------
if [[ ! -e "$HOME/.config/opencode-kit/secrets.env" && -r "$HOME/.config/pi-kit/secrets.env" ]]; then
	say "copying web-search keys from ~/.config/pi-kit/secrets.env"
	do_ mkdir -p "$HOME/.config/opencode-kit"
	do_ install -m 600 "$HOME/.config/pi-kit/secrets.env" "$HOME/.config/opencode-kit/secrets.env"
fi

say "deploying the kit into $CONFIG"
do_ "$LIVE/bin/ock" kit apply
svc="$("$oc" service status 2>/dev/null | head -n1 || true)"   # exits 0 even when stopped
if (( ! DRY )) && [[ -n "$svc" && "$svc" != stopped* ]]; then
	say "restarting OpenCode's background service so it picks up the new settings"
	"$oc" service restart >/dev/null 2>&1 || say "couldn't restart it — run: opencode service restart"
fi

# ---- next steps -----------------------------------------------------------------------------------
stray=()
for f in AGENTS.md CLAUDE.md opencode.json opencode.jsonc .opencode; do
	[[ -e "$HOME/workspace/projects/$f" ]] && stray+=("$f")
done
cat <<EOF

Done$( (( DRY )) && echo " (dry run — nothing was changed)").
Next:
  1. exec zsh                      (picks up OpenCode's PATH if it was just installed)
  2. opencode, then /connect twice:  OpenCode Go (API key)  and  OpenAI → "Sign in with ChatGPT"
  3. ock models                    every model should say ok
  Daily use: cd into a project, run opencode. /propose, /apply, /fix, /research, /roadmap, /adr, /commit.
  Git plumbing costs nothing with !:  !ock ship   !ock status   !ock cleanup   !ock help
EOF
if (( ${#stray[@]} )); then
	echo "  Note: ~/workspace/projects contains ${stray[*]} (left over from pinew). The kit keeps them out of"
	echo "        every project's prompt, but move them out when you tidy that folder."
fi
