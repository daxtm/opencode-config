#!/usr/bin/env bash
# opencode-config's checks — run by `ock check` (and so by `ock ship`) and the build agent.
#   1. every shell script parses (and passes shellcheck, when it's installed)
#   2. the plugin parses as TypeScript, and the JSONC config parses
#   3. prompts (global AGENTS.md, agents, commands, templates) stay inside budgets.conf
#   4. the workflow scripts do what they promise (scripts/test-workflow.sh, credential-free)
#   5. OpenCode itself, with a fake model: request token budget, guard, agents, commands
#      (scripts/test-opencode.sh; skipped when OpenCode isn't installed)
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.local/share/opencode-kit/npm/node_modules/.bin:$PATH"
fail=0
bad() { echo "FAIL $*"; fail=1; }

mapfile -t scripts < <(printf '%s\n' install.sh setup.sh bin/* scripts/*.sh templates/project/scripts/check.sh | sort -u)
before=$fail
for f in "${scripts[@]}"; do bash -n "$f" || bad "bash syntax: $f"; done
if command -v shellcheck >/dev/null; then
	shellcheck -S warning -e SC2016 "${scripts[@]}" || bad "shellcheck"
else
	echo "skip shellcheck (not installed)"
fi
(( fail == before )) && echo "ok   ${#scripts[@]} shell scripts"

before=$fail
ESBUILD=(npx -y esbuild@0.28.2)
command -v esbuild >/dev/null && ESBUILD=(esbuild)
for f in global/plugins/*.ts; do
	"${ESBUILD[@]}" "$f" --log-level=error >/dev/null || bad "TypeScript syntax: $f"
done
node -e '
const fs = require("fs"); const src = fs.readFileSync(process.argv[1], "utf8");
let out = "", i = 0, str = false;
while (i < src.length) {            // strip // and /* */ comments outside strings
  const c = src[i], n = src[i + 1];
  if (str) { out += c; if (c === "\\") { out += n; i += 2; continue } if (c === "\"") str = false; i++; continue }
  if (c === "\"") { str = true; out += c; i++; continue }
  if (c === "/" && n === "/") { while (i < src.length && src[i] !== "\n") i++; continue }
  if (c === "/" && n === "*") { i = src.indexOf("*/", i + 2) + 2; continue }
  out += c; i++
}
JSON.parse(out.replace(/,(\s*[}\]])/g, "$1"));
' global/opencode.jsonc || bad "global/opencode.jsonc does not parse"
(( fail == before )) && echo "ok   plugin and config parse"

shopt -s nullglob
before=$fail
while read -r glob lines words; do
	[[ -z "$glob" || "$glob" == \#* ]] && continue
	for f in $glob; do
		l="$(wc -l < "$f")"; w="$(wc -w < "$f")"
		if (( l > lines || w > words )); then bad "budget: $f is $l lines / $w words (max $lines / $words) — move rules into a script"; fi
	done
done < budgets.conf
(( fail == before )) && echo "ok   budgets"

before=$fail
if [[ -n "${OCK_IN_BEHAVIOR_TESTS:-}" ]]; then
	echo "skip behavior tests (already inside them: the setup test runs ock new on a copy of this repo)"
else
	bash "$ROOT/scripts/test-workflow.sh" || bad "workflow behavior (see FAIL lines above)"
	bash "$ROOT/scripts/test-opencode.sh" || bad "OpenCode behavior (see FAIL lines above)"
	(( fail == before )) && echo "ok   behavior tests"
fi

exit "$fail"
