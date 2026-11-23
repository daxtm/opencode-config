#!/usr/bin/env python3
"""A fake OpenAI-compatible model for scripts/test-opencode.sh (no network, no credentials).

Usage: fake-model.py <port> <request-log.jsonl> <plan.json>

Every request body is appended to the log. The reply follows the plan: a JSON list of steps, each
{"when": "<text in the system prompt>" (optional), "text": "..."} or {"when": ..., "tool": name,
"args": {...}}, optionally with "delay": seconds before the reply starts. Each request takes the first unused step whose "when" matches its system prompt
(so main, build, spec… can be scripted independently); with none left it answers "done". Used
steps are recorded in <plan.json>.used, so rewriting the plan and deleting that file starts over.
"""
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, LOG, PLAN = int(sys.argv[1]), sys.argv[2], sys.argv[3]
USED = PLAN + ".used"


def system_text(body):
    parts = []
    for m in body.get("messages", []):
        if m.get("role") == "system":
            c = m.get("content")
            parts.append(c if isinstance(c, str) else json.dumps(c))
    return " ".join(parts)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        body = b'{"object":"list","data":[{"id":"m1","object":"model"}]}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        body = json.loads(raw or b"{}")
        with open(LOG, "a") as f:
            f.write(json.dumps({"path": self.path, "body": body}) + "\n")
        plan = json.load(open(PLAN)) if os.path.exists(PLAN) else []
        used = json.load(open(USED)) if os.path.exists(USED) else []
        sysm = system_text(body)
        n, step = len(plan) + len(used), {"text": "done"}
        for i, st in enumerate(plan):
            if i in used or (st.get("when") and st["when"] not in sysm):
                continue
            n, step = i, st
            used.append(i)
            break
        json.dump(used, open(USED, "w"))
        time.sleep(float(step.get("delay", 0)))  # a step can take a while, like a real model
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        base = {"id": "c%d" % n, "object": "chat.completion.chunk", "created": int(time.time()), "model": "m1"}

        def event(delta, finish):
            chunk = dict(base, choices=[{"index": 0, "delta": delta, "finish_reason": finish}])
            if finish:
                chunk["usage"] = {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}
            self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
            self.wfile.flush()

        if "tool" in step:
            call = {"index": 0, "id": "call_%d" % n, "type": "function",
                    "function": {"name": step["tool"], "arguments": json.dumps(step["args"])}}
            event({"role": "assistant", "tool_calls": [call]}, None)
            event({}, "tool_calls")
        else:
            event({"role": "assistant", "content": step["text"]}, None)
            event({}, "stop")
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
