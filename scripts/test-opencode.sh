#!/usr/bin/env bash
# OpenCode behavior tests — the deployed config running in real OpenCode, against a fake model
# (scripts/fake-model.py), in a throwaway HOME. No network, no credentials, no tokens.
#
# Covers what the user would notice: which agents exist; the size of every request (system prompt +
# tool definitions — what each turn costs before your words); no separate title request; which tools
# each agent gets; main → build delegation; the guard refusing pushes to main and writes outside the
# project; the slash commands reaching the right agent; `ock` on the agents' PATH.
#
# Needs OpenCode 2.3.x (`opencode`, or $OCK_OPENCODE), python3, git, curl. Skipped without OpenCode.
# Usage: scripts/test-opencode.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
MAIN_BUDGET=3200   # tokens (chars/4) per main-session request: system prompt + tools
AGENT_BUDGET=2700  # per subagent request
fails=0; passes=0
pass() { passes=$((passes + 1)); echo "  ok   $*"; }
fail() { fails=$((fails + 1)); echo "  FAIL $*"; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }

OC="${OCK_OPENCODE:-$(command -v opencode || echo "$HOME/.opencode/bin/opencode")}"
if [[ ! -x "$OC" ]]; then
	echo "skip OpenCode tests (opencode not installed)"; exit 0
fi
for c in python3 git curl; do command -v "$c" >/dev/null || { echo "test-opencode: $c is required"; exit 1; }; done
version="$("$OC" --version 2>/dev/null | head -n1)"
[[ "$version" == *2.3.* ]] || echo "  note: tested against OpenCode 2.3.x, found ${version:-unknown}"

# Neither under /tmp nor inside this repo, on purpose: the project boundary lets /tmp through, and
# the kit's own folder is read-only — fixtures in either place would hide boundary bugs.
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}"
T="$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/ock-test-opencode.XXXXXX")"
FAKE_PID=""; SERVE_PID=""
cleanup() { [[ -n "$FAKE_PID" ]] && kill "$FAKE_PID" 2>/dev/null; [[ -n "$SERVE_PID" ]] && kill "$SERVE_PID" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
H="$T/home"; P="$H/workspace/projects/proj"; O="$H/workspace/projects/other"; REQ="$T/requests.jsonl"; PLAN="$T/plan.json"
mkdir -p "$H" "$P" "$O"
free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
FAKE_PORT="$(free_port)"
python3 "$ROOT/scripts/fake-model.py" "$FAKE_PORT" "$REQ" "$PLAN" > "$T/fake.log" 2>&1 & FAKE_PID=$!

printf '[user]\n\tname = Test\n\temail = test@example.com\n' > "$H/.gitconfig"
sed -E 's#=.*#=fake/m1#' "$ROOT/agent-models.conf" | grep -vE '^[[:space:]]*(#|$)' > "$T/models.conf"
HOME="$H" OCK_MODELS="$T/models.conf" OCK_SKIP_NPM=1 OCK_SKIP_SERVICE=1 "$ROOT/install.sh" > "$T/install.log" 2>&1 \
	|| { echo "test-opencode: install.sh failed"; cat "$T/install.log"; exit 1; }
git -C "$P" init -q -b main; HOME="$H" git -C "$P" commit -q --allow-empty -m init; git -C "$P" switch -q -c feat/x
cat > "$P/opencode.json" <<EOF
{"providers":{"fake":{"name":"Fake","env":["FAKE_API_KEY"],"package":"@opencode/ai/providers/openai-compatible",
 "settings":{"baseURL":"http://127.0.0.1:$FAKE_PORT/v1"},"models":{"m1":{"name":"M1","limit":{"context":200000,"output":8000}}}}}}
EOF
export FAKE_API_KEY=x OCK_NO_BACKGROUND=1
for _ in $(seq 50); do curl -s -m 1 "http://127.0.0.1:$FAKE_PORT/v1/models" >/dev/null && break; sleep 0.1; done

plan() { printf '%s' "$1" > "$PLAN"; rm -f "$PLAN.used"; : > "$REQ"; }
# --auto approves everything that isn't explicitly denied, so only the kit's own denies can block
run() { (cd "$P" && HOME="$H" timeout 150 "$OC" run --standalone --archived --auto "$1" > "$T/run.log" 2>&1); }
# One line per request: agent tools≈tokens total≈tokens [tool results…]
requests() {
	python3 - "$REQ" <<'PY'
import json, sys
marks = [("main session", "main"), ("You implement one task", "build"), ("OpenSpec change that build", "spec"),
         ("You are the researcher", "researcher"), ("finishing a merge", "resolver"), ("Reproduces a failure", "debugger")]
for line in open(sys.argv[1]):
    b = json.loads(line)["body"]
    sysm = " ".join(m["content"] if isinstance(m["content"], str) else json.dumps(m["content"]) for m in b["messages"] if m["role"] == "system")
    who = next((n for k, n in marks if k in sysm), "other")
    tools = sorted(t["function"]["name"] for t in b.get("tools", []))
    est = (len(sysm) + len(json.dumps(b.get("tools", [])))) // 4
    results = [m["content"] if isinstance(m["content"], str) else json.dumps(m["content"]) for m in b["messages"] if m["role"] == "tool"]
    users = [m["content"] if isinstance(m["content"], str) else json.dumps(m["content"]) for m in b["messages"] if m["role"] == "user"]
    print(json.dumps({"who": who, "tools": ",".join(tools), "tokens": est, "results": results, "user": users[-1] if users else ""}))
PY
}
field() { python3 -c 'import json,sys; [print(json.loads(l)[sys.argv[1]] if not isinstance(json.loads(l)[sys.argv[1]], list) else "\n".join(json.loads(l)[sys.argv[1]])) for l in sys.stdin]' "$1"; }

echo "agents"
(cd "$P" && HOME="$H" timeout 60 "$OC" debug agents --standalone > "$T/agents.json" 2>"$T/agents.err")
agents="$(python3 -c 'import json,sys; print(" ".join(sorted(a["id"] for a in json.load(open(sys.argv[1])) if not a.get("hidden"))))' "$T/agents.json" 2>/dev/null)"
check "visible agents are exactly the kit's (built-in plan/general/explore gone)" test "$agents" = "build debugger main researcher spec"
check "the resolver exists for ock ship (hidden)" grep -q '"resolver"' "$T/agents.json"

echo "token budget"
echo "STRAY-PARENT-RULES" > "$H/workspace/projects/AGENTS.md"      # the leftover from pinew
echo "# proj" > "$P/AGENTS.md"; echo "PROJECT-OWN-RULES" >> "$P/AGENTS.md"
plan '[{"text":"hello back"}]'; run "hello"
r="$(requests)"
check "the project's own AGENTS.md reaches the model" grep -q PROJECT-OWN-RULES "$REQ"
check "an AGENTS.md in a folder above the project does not" bash -c "! grep -q STRAY-PARENT-RULES '$REQ'"
rm -f "$H/workspace/projects/AGENTS.md" "$P/AGENTS.md"
plan '[{"text":"hello back"}]'; run "hello"
r="$(requests)"
check "one model request per message (titles cost nothing)" test "$(wc -l <<<"$r")" = 1
check "main session tools: edit glob grep read shell subagent write" test "$(field tools <<<"$r")" = "edit,glob,grep,read,shell,subagent,write"
main_tokens="$(field tokens <<<"$r")"
check "main session request ≈${main_tokens} tokens (budget $MAIN_BUDGET; stock OpenCode ≈6800)" test "$main_tokens" -le "$MAIN_BUDGET"

echo "delegation"
plan '[{"when":"main session","tool":"subagent","args":{"agent":"build","description":"add hello","prompt":"Add hello. Acceptance: bin/hello prints hello."}},
 {"when":"You implement one task","text":"built: bin/hello prints hello"},
 {"when":"main session","text":"launched"},{"when":"main session","text":"RELAYED"}]'
run "add a hello command"
r="$(requests)"
b="$(grep '"who": "build"' <<<"$r" | head -n1)"
check "main delegates to build" test -n "$b"
check "build gets no subagent tool" test "$(field tools <<<"$b")" = "edit,glob,grep,read,shell,write"
build_tokens="$(field tokens <<<"$b")"
check "build request ≈${build_tokens:-?} tokens (budget $AGENT_BUDGET)" test "${build_tokens:-99999}" -le "$AGENT_BUDGET"
check "main relays the result" grep -q RELAYED "$T/run.log"

echo "guard"
plan "[{\"when\":\"main session\",\"tool\":\"shell\",\"args\":{\"command\":\"git push origin main\"}},
 {\"when\":\"main session\",\"tool\":\"shell\",\"args\":{\"command\":\"echo x > $O/via-shell.txt\"}},
 {\"when\":\"main session\",\"tool\":\"write\",\"args\":{\"path\":\"$O/via-write.txt\",\"content\":\"x\"}},
 {\"when\":\"main session\",\"tool\":\"write\",\"args\":{\"path\":\"$H/.config/opencode/AGENTS.md\",\"content\":\"x\"}},
 {\"when\":\"main session\",\"tool\":\"write\",\"args\":{\"path\":\"notes/inside.txt\",\"content\":\"x\"}},
 {\"when\":\"main session\",\"tool\":\"shell\",\"args\":{\"command\":\"command -v ock\"}},
 {\"when\":\"main session\",\"text\":\"done\"}]"
run "go"
res="$(requests | tail -n1 | field results)"
check "pushing to main is refused by the kit guard" grep -q 'kit guard: Never push to main' <<<"$res"
check "a shell write into another project is refused" bash -c "grep -q 'kit guard: Writing $O/via-shell.txt' <<<\"\$1\" && test ! -e '$O/via-shell.txt'" _ "$res"
check "an edit in another project is refused" test ! -e "$O/via-write.txt"
check "the deployed config is read-only" bash -c "! grep -qx x '$H/.config/opencode/AGENTS.md'"
check "files inside the project are written" test -f "$P/notes/inside.txt"
check "agents' shells find ock" grep -qF "$ROOT/bin/ock" <<<"$res"

echo "commands"
SERVE_PORT="$(free_port)"
(cd "$P" && HOME="$H" exec "$OC" serve --port "$SERVE_PORT" --hostname 127.0.0.1 > "$T/serve.log" 2>&1) & SERVE_PID=$!
for _ in $(seq 100); do grep -q 'server password' "$T/serve.log" 2>/dev/null && break; sleep 0.2; done
PW="$(grep -oE 'password [A-Za-z0-9_-]+' "$T/serve.log" | cut -d' ' -f2)"
api() { curl -s -u "opencode:$PW" -H "x-opencode-directory: $P" -H 'content-type: application/json' -X POST "http://127.0.0.1:$SERVE_PORT$1" -d "$2"; }
command_run() { # name text — runs a slash command in a new session, waits for its requests
	local sid
	sid="$(api /api/session '{}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["id"])')"
	api "/api/session/$sid/command" "{\"name\":\"$1\",\"text\":\"$2\"}" >/dev/null
	for _ in $(seq 60); do [[ "$(wc -l < "$REQ")" -ge 2 ]] && break; sleep 0.25; done; sleep 1
}
plan '[{"when":"You are the researcher","text":"ANSWER"},{"when":"main session","text":"relay"}]'
command_run research "what is the latest OpenSpec version"
r="$(requests | grep '"who": "researcher"' | head -n1)"
check "/research runs the researcher with web + read-only tools" test "$(field tools <<<"$r")" = "glob,grep,read,webfetch,websearch"
plan '[{"when":"OpenSpec change that build","text":"PROPOSED"},{"when":"main session","text":"relay"}]'
command_run propose "add a hello command"
r="$(requests | grep '"who": "spec"' | head -n1)"
check "/propose runs spec with the request" grep -q 'Propose: add a hello command' <<<"$(field user <<<"$r")"
for c in apply fix roadmap adr commit; do
	check "/$c exists" test -f "$H/.config/opencode/commands/$c.md"
done

echo
echo "opencode tests: $passes passed, $fails failed (main ≈${main_tokens:-?} tokens/request, build ≈${build_tokens:-?})"
(( fails == 0 ))
