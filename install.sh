#!/usr/bin/env bash
# install.sh — deploys this checkout (the live kit) into OpenCode. Run by `ock kit apply`; you don't
# run it by hand except as break-glass (see bin/ock-kit).
#
#   global/** → ~/.config/opencode/**   {{KIT_DIR}} {{HOME}} and {{MODEL:<role>}} filled in from
#                                       agent-models.conf. Only files listed in the previous
#                                       .kit-manifest are ever replaced or removed; anything else
#                                       in ~/.config/opencode is left alone (ock kit status lists it).
#   ~/.local/bin/ock                    → this checkout's bin/ock (only a missing file or a symlink
#                                       is replaced)
#   OpenSpec CLI (pinned)               → ~/.local/share/opencode-kit/npm
#   OpenCode service environment        → OPENCODE_DISABLE_CLAUDE_CODE=1 plus web-search keys from
#                                       ~/.config/opencode-kit/secrets.env (KEY=value lines)
set -euo pipefail

KIT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CONFIG="${OCK_CONFIG:-$HOME/.config/opencode}"
STATE="$HOME/.local/share/opencode-kit"
SECRETS="$HOME/.config/opencode-kit/secrets.env"
OPENSPEC_VERSION="2.1.1"
SEARCH_KEYS=(EXA_API_KEY TAVILY_API_KEY FIRECRAWL_API_KEY PARALLEL_API_KEY TINYFISH_API_KEY)

die() { echo "install: $*" >&2; exit 1; }
if [[ -L "$CONFIG" && ! -e "$CONFIG" ]]; then
	die "$CONFIG is a dangling symlink → $(readlink "$CONFIG"). Remove the link (rm \"$CONFIG\") and run ock kit apply again"
fi
mkdir -p "$CONFIG" "$STATE"

# ---- models -----------------------------------------------------------------------------------
declare -A MODEL=()
while IFS='=' read -r role value; do
	role="${role//[[:space:]]/}"
	value="$(sed -E 's/[[:space:]]#[[:space:]].*$//; s/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$value")"
	[[ -n "$role" ]] && MODEL["$role"]="$value"
done < <(grep -vE '^[[:space:]]*(#|$)' "${OCK_MODELS:-$KIT_DIR/agent-models.conf}")

render_text() { # src — prints the rendered file
	local src="$1" out role
	out="$(<"$src")"
	out="${out//\{\{KIT_DIR\}\}/$KIT_DIR}"
	out="${out//\{\{HOME\}\}/$HOME}"
	while [[ "$out" =~ \{\{MODEL:([a-z]+)\}\} ]]; do
		role="${BASH_REMATCH[1]}"
		[[ -n "${MODEL[$role]:-}" ]] || die "agent-models.conf has no model for role '$role' (needed by ${src#"$KIT_DIR"/})"
		out="${out//"{{MODEL:$role}}"/${MODEL[$role]}}"
	done
	printf '%s\n' "$out"
}
render() { # src dst
	local text
	text="$(render_text "$1")" || exit 1
	mkdir -p "$(dirname "$2")"
	printf '%s\n' "$text" > "$2.kit-tmp" && mv "$2.kit-tmp" "$2"
}

# ---- global/ → ~/.config/opencode ---------------------------------------------------------------
manifest="$CONFIG/.kit-manifest"
mapfile -t new < <(cd "$KIT_DIR/global" && find . -type f -printf '%P\n' | sort)
for rel in "${new[@]}"; do
	dst="$CONFIG/$rel"
	if [[ -e "$dst" && ! -f "$manifest" ]] || { [[ -e "$dst" && -f "$manifest" ]] && ! grep -qxF "$rel" "$manifest"; }; then
		if ! cmp -s <(render_text "$KIT_DIR/global/$rel" 2>/dev/null || true) "$dst"; then
			mkdir -p "$STATE/replaced"
			cp -p "$dst" "$STATE/replaced/$(tr / _ <<<"$rel").$(date +%Y%m%d-%H%M%S)"
			echo "install: $rel existed and wasn't from the kit — saved a copy in $STATE/replaced/"
		fi
	fi
	render "$KIT_DIR/global/$rel" "$dst"
done
if [[ -f "$manifest" ]]; then
	while IFS= read -r rel; do
		[[ -n "$rel" ]] || continue
		printf '%s\n' "${new[@]}" | grep -qxF "$rel" && continue
		rm -f "$CONFIG/$rel" && echo "install: removed $rel (no longer in the kit)"
	done < "$manifest"
fi
printf '%s\n' "${new[@]}" > "$manifest"
for other in opencode.json config.json; do
	[[ -e "$CONFIG/$other" ]] && echo "install: WARNING $CONFIG/$other exists too — OpenCode merges it with the kit's opencode.jsonc; move its settings into opencode-config"
done
echo "install: ${#new[@]} files → $CONFIG"

# ---- ock on PATH --------------------------------------------------------------------------------
mkdir -p "$HOME/.local/bin"
if [[ -L "$HOME/.local/bin/ock" || ! -e "$HOME/.local/bin/ock" ]]; then
	ln -sfn "$KIT_DIR/bin/ock" "$HOME/.local/bin/ock"
else
	echo "install: WARNING ~/.local/bin/ock is a real file, not ours — left alone"
fi

# ---- OpenSpec (pinned) --------------------------------------------------------------------------
npm_bin="$STATE/npm/node_modules/.bin"
have="$("$npm_bin/openspec" --version 2>/dev/null || true)"
if [[ "$have" != "$OPENSPEC_VERSION" && -z "${OCK_SKIP_NPM:-}" ]]; then
	if command -v npm >/dev/null; then
		npm install --silent --no-fund --no-audit --prefix "$STATE/npm" "@fission-ai/openspec@$OPENSPEC_VERSION" >/dev/null \
			&& echo "install: openspec $OPENSPEC_VERSION" || echo "install: WARNING openspec install failed (npm) — /propose and ock ship need it"
	else
		echo "install: WARNING npm not found — install Node.js, then: ock kit apply"
	fi
fi

# ---- OpenCode service environment ---------------------------------------------------------------
oc="$(command -v opencode || true)"; [[ -n "$oc" ]] || oc="$HOME/.opencode/bin/opencode"
if [[ -x "$oc" && -z "${OCK_SKIP_SERVICE:-}" ]]; then
	declare -A ENV=([OPENCODE_DISABLE_CLAUDE_CODE]=1)
	if [[ -r "$SECRETS" ]]; then
		for k in "${SEARCH_KEYS[@]}"; do
			v="$(grep -E "^[[:space:]]*(export[[:space:]]+)?$k=" "$SECRETS" | tail -n1 | sed -E "s/^[[:space:]]*(export[[:space:]]+)?$k=//; s/^[\"']//; s/[\"'][[:space:]]*$//" || true)"
			[[ -n "$v" ]] && ENV[$k]="$v"
		done
	fi
	digest="$(for k in $(printf '%s\n' "${!ENV[@]}" | sort); do printf '%s=%s\n' "$k" "${ENV[$k]}"; done | sha256sum | cut -d' ' -f1)"
	if [[ "$(cat "$STATE/service-env.sha" 2>/dev/null || true)" != "$digest" ]]; then
		ok=1
		for k in "${!ENV[@]}"; do "$oc" service set env "$k" "${ENV[$k]}" >/dev/null 2>&1 || ok=0; done
		if (( ok )); then
			echo "$digest" > "$STATE/service-env.sha"
			echo "install: OpenCode service environment updated (${#ENV[@]} values) — takes effect after: opencode service restart"
		else
			echo "install: WARNING couldn't set the OpenCode service environment (opencode service set env)"
		fi
	fi
fi
echo "install: done ($(git -C "$KIT_DIR" log -1 --format='%h %s' 2>/dev/null || echo 'not a git checkout'))"
