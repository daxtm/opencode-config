#!/usr/bin/env python3
"""ock usage [days] — where your tokens went, from OpenCode's own records (read-only).

Reads ~/.local/share/opencode/opencode.db: every model request OpenCode made, with its agent, model
(and variant), and token counts. Shows totals per agent and model, the sessions that used the most
(subagents counted in the session that started them), and the largest single requests — a request's
input is everything resent to the model that turn, so large ones mean a session that grew too long.
"""
import json
import os
import sqlite3
import sys
import time
from types import SimpleNamespace as NS

days = 7
args = sys.argv[1:]
if args and args[0] in ("-h", "--help"):
    print(__doc__.strip())
    sys.exit(0)
if args:
    try:
        days = int(args[0])
    except ValueError:
        sys.exit("usage: ock usage [days]")

db = os.path.expanduser("~/.local/share/opencode/opencode.db")
if not os.path.exists(db):
    sys.exit("ock usage: no OpenCode database at " + db)
con = sqlite3.connect("file:" + db + "?mode=ro", uri=True)
since = (time.time() - days * 86400) * 1000

sessions = {sid: NS(title=title or sid, parent=parent) for sid, title, parent in con.execute("select id, title, parent_id from session_v2")}
rows = []
for sid, data in con.execute("select session_id, data from session_message where type = ? and time_created >= ?", ("assistant", since)):
    d = json.loads(data)
    t = d.get("tokens") or {}
    cache = t.get("cache") or {}
    m = d.get("model") or {}
    model = "{}/{}{}".format(m.get("providerID", "?"), m.get("id", "?"), "#" + m["variant"] if m.get("variant") else "")
    rows.append(NS(sid=sid, agent=d.get("agent", "?"), model=model, fresh=t.get("input", 0), cached=cache.get("read", 0),
                   written=cache.get("write", 0), out=t.get("output", 0), think=t.get("reasoning", 0)))


def k(n):
    return "{:,.1f}k".format(n / 1e3) if n < 1e6 else "{:,.2f}M".format(n / 1e6)


def root(sid):
    for _ in range(10):
        parent = sessions[sid].parent if sid in sessions else None
        if not parent:
            return sid
        sid = parent
    return sid


def table(title, keyfn, label, limit=None):
    groups = {}
    for r in rows:
        g = groups.setdefault(keyfn(r), NS(n=0, fresh=0, cached=0, written=0, out=0, think=0))
        g.n += 1
        g.fresh += r.fresh
        g.cached += r.cached
        g.written += r.written
        g.out += r.out
        g.think += r.think
    print("\n" + title)
    fmt = "  {:<50}{:>6}{:>9}{:>10}{:>11}{:>9}{:>10}"
    print(fmt.format(label, "reqs", "avg in", "fresh in", "cached in", "output", "thinking"))
    ranked = sorted(groups.items(), key=lambda kv: -(kv[1].fresh + kv[1].cached + kv[1].out + kv[1].think))
    for name, g in ranked[:limit]:
        avg = (g.fresh + g.cached + g.written) / g.n
        print(fmt.format(name[:49], g.n, k(avg), k(g.fresh), k(g.cached), k(g.out), k(g.think)))


def session_name(r):
    top = root(r.sid)
    title = sessions[top].title if top in sessions else top
    return "{} ({})".format(title[:38], top[-6:])


print("OpenCode usage, last {} days: {} model requests".format(days, len(rows)))
if rows:
    table("By agent and model", lambda r: r.agent + "  " + r.model, "agent  model")
    table("Top sessions (subagents counted in the session that started them)", session_name, "session", 10)
    print("\nLargest single requests (input = everything resent to the model that turn)")
    for r in sorted(rows, key=lambda r: -(r.fresh + r.cached + r.written))[:8]:
        title = sessions[r.sid].title if r.sid in sessions else ""
        print("  {:>8} in {:>8} out  {:<11}{:<39}{}".format(k(r.fresh + r.cached + r.written), k(r.out + r.think), r.agent, r.model[:38], title[:40]))
