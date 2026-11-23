/** @jsxImportSource @opentui/solid */
/**
 * subagents — shows what your subagents are doing. A TUI plugin: it only draws, no model calls.
 *
 *   above the prompt   one line per running subagent of this session: agent, how long it has been
 *                      running, its task, and what it is doing right now (its latest tool call)
 *   sidebar            this session's subagents, running and finished, with their run times
 *   when one finishes  a toast; if the terminal isn't focused, also a desktop notification + sound
 *
 * ↓ on an empty prompt opens OpenCode's own subagent list (Esc closes it, ctrl+d interrupts one).
 */
import { Plugin } from "@opencode/plugin/tui"

type Outcome = "running" | "done" | "failed" | "stopped"
type Sub = {
  id: string
  parent: string
  agent: string
  task: string
  started: number
  ended?: number
  outcome: Outcome
  doing?: string
}
type State = { now: number; subs: Record<string, Sub> }

const MAX_LINE = 70
const clip = (s: string, n = MAX_LINE) => {
  const one = s.replace(/\s+/g, " ").trim()
  return one.length > n ? one.slice(0, n - 1) + "…" : one
}
const elapsed = (ms: number) => {
  const s = Math.max(0, Math.round(ms / 1000))
  return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, "0")}s`
}
// what a tool call is doing, in a few words
const describe = (name: string | undefined, input: Record<string, any> | undefined) => {
  const i = input ?? {}
  const what = i.command ?? i.path ?? i.filePath ?? i.pattern ?? i.query ?? i.url ?? i.agent ?? i.description ?? ""
  return clip(`${name ?? "tool"} ${typeof what === "string" ? what : JSON.stringify(what)}`, 60)
}
const ICON: Record<Outcome, string> = { running: "●", done: "✓", failed: "✗", stopped: "■" }

export default Plugin.define({
  id: "opencode-kit.subagents",
  setup(ctx) {
    const [state, set] = ctx.storage.memory<State>("subagents", { initial: { now: Date.now(), subs: {} } })
    const toolNames = new Map<string, string>()

    // The session a subagent ultimately belongs to: follow parents up through known subagents.
    const top = (id: string) => {
      let cur = id
      for (let i = 0; i < 10 && state.subs[cur]; i++) cur = state.subs[cur].parent
      return cur
    }
    const family = (sessionID: string) => {
      const root = top(sessionID)
      return Object.values(state.subs)
        .filter((s) => top(s.id) === root)
        .sort((a, b) => a.started - b.started)
    }

    const add = (id: string, parent: string | undefined, agent: string | undefined, task: string | undefined, at: number) => {
      if (!parent || state.subs[id]) return
      set((d) => {
        d.subs[id] = { id, parent, agent: agent ?? "subagent", task: clip(task ?? ""), started: at, outcome: "running" }
      })
    }
    const finish = (id: string, outcome: Outcome, at: number) => {
      const sub = state.subs[id]
      if (!sub || sub.outcome !== "running") return
      set((d) => {
        d.subs[id].outcome = outcome
        d.subs[id].ended = at
        d.subs[id].doing = undefined
      })
      const took = elapsed(at - sub.started)
      const word = outcome === "done" ? "finished" : outcome === "failed" ? "failed" : "stopped"
      ctx.ui.toast.show({
        title: `${sub.agent} ${word} · ${took}`,
        message: sub.task || sub.agent,
        variant: outcome === "done" ? "success" : outcome === "failed" ? "error" : "warning",
        sessionID: sub.parent,
      })
      void ctx.attention
        .notify({
          title: `OpenCode: ${sub.agent} ${word}`,
          message: sub.task || `${sub.agent} ${word} after ${took}`,
          notification: { when: "blurred" },
          sound: { name: outcome === "done" ? "subagent_done" : "error", when: "blurred" },
        })
        .catch(() => {})
    }

    // Subagents that were already running when the TUI started
    try {
      for (const s of ctx.data.session.list()) {
        if (s.parentID && ctx.data.session.status(s.id) === "running")
          add(s.id, s.parentID, s.agent, s.title, s.time.busy ?? s.time.created)
      }
    } catch {
      // the session cache may not be ready yet; new subagents are picked up from events
    }

    const stops = [
      ctx.data.on("session.created", (e) => add(e.data.sessionID, e.data.parentID, e.data.agent, e.data.title, e.created)),
      ctx.data.on("session.renamed", (e: any) => {
        const id = e.data?.sessionID
        if (id && state.subs[id] && typeof e.data?.title === "string") set((d) => void (d.subs[id].task = clip(e.data.title)))
      }),
      ctx.data.on("session.tool.input.started", (e) => {
        toolNames.set(e.data.id, e.data.name)
        if (state.subs[e.data.sessionID]) set((d) => void (d.subs[e.data.sessionID].doing = e.data.name))
      }),
      ctx.data.on("session.tool.called", (e) => {
        if (state.subs[e.data.sessionID])
          set((d) => void (d.subs[e.data.sessionID].doing = describe(toolNames.get(e.data.id), e.data.input)))
        toolNames.delete(e.data.id)
      }),
      ctx.data.on("session.execution.succeeded", (e) => finish(e.data.sessionID, "done", e.created)),
      ctx.data.on("session.execution.failed", (e) => finish(e.data.sessionID, "failed", e.created)),
      ctx.data.on("session.execution.interrupted", (e) => finish(e.data.sessionID, "stopped", e.created)),
    ]

    // tick once a second while anything runs, so the run times count up
    const timer = setInterval(() => {
      if (Object.values(state.subs).some((s) => s.outcome === "running")) set((d) => void (d.now = Date.now()))
    }, 1000)

    ctx.ui.slot({
      prepend: "session.composer.top",
      render: (input) => {
        const running = () => family(input.sessionID).filter((s) => s.outcome === "running")
        return (
          <box flexDirection="column">
            {running().map((s) => (
              <text>
                {`● ${s.agent} · ${elapsed(state.now - s.started)}${s.task ? ` · ${s.task}` : ""}${s.doing ? `  → ${s.doing}` : ""}`}
              </text>
            ))}
            {running().length > 0 ? <text>{"  ↓ subagent list · esc closes it"}</text> : null}
          </box>
        )
      },
    })

    ctx.ui.slot({
      append: "sidebar.content",
      render: (input) => {
        const subs = () => family(input.sessionID).slice(-8)
        return subs().length === 0 ? null : (
          <box flexDirection="column" paddingTop={1}>
            <text>Subagents</text>
            {subs().map((s) => (
              <text>{`${ICON[s.outcome]} ${s.agent} ${elapsed((s.ended ?? state.now) - s.started)}${s.task ? ` ${clip(s.task, 22)}` : ""}`}</text>
            ))}
          </box>
        )
      },
    })

    return () => {
      clearInterval(timer)
      for (const stop of stops) stop()
    }
  },
})
