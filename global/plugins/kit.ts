/**
 * kit — the opencode-config plugin. No model calls, no tokens.
 *
 *   guard        what the AI may NOT do, in every agent and headless run:
 *                  - merge, approve or review a PR; delete, archive, rename or re-publish a repo;
 *                    change rulesets / branch protection
 *                  - delete branches (local or remote); push to main/master/test; commit, merge or
 *                    push while on one of them
 *                  - write outside the current project (shell redirects, cp/mv/rm/…, git -C / cd):
 *                    other projects are read-only references. Edits through the edit/write tools are
 *                    held to the same boundary by the permissions in opencode.jsonc.
 *                The kit's own scripts (`ock …`) run outside the AI's tools, and commands the user
 *                types with `!` are not checked.
 *   one at a time  a file-changing agent (build, debugger, spec) can't start while another one is
 *                still running in the same project: two agents editing one folder collide and waste
 *                tokens redoing each other's work. Read-only agents (researcher) may run alongside.
 *   titles       session titles come from the first message (no extra model request per session)
 *   trims        drops tools and prompt lines this setup never uses (they cost tokens every request),
 *                and AGENTS.md files from folders above the project (they belong to no project)
 *   PATH         agent shells get `ock` and the kit's pinned `openspec`
 *   upkeep       at startup: deploy opencode-config if main moved (ock kit apply --if-changed);
 *                in kit projects: keep `test` in sync with GitHub every 10 minutes
 */
import { execFileSync, spawn } from "node:child_process"
import * as fs from "node:fs"
import * as os from "node:os"
import * as path from "node:path"

const KIT = "{{KIT_DIR}}"
const HOME = os.homedir()
const STATE = path.join(HOME, ".local/share/opencode-kit")
const BIN = [path.join(KIT, "bin"), path.join(STATE, "npm/node_modules/.bin")]
const WRITABLE_OUTSIDE = ["/tmp", "/dev", "/proc"]
const READ_ONLY = [KIT, path.join(HOME, ".config/opencode")] // the deployed setup, wherever it lives
const PROTECTED = /^(main|master|test)$/

// ---- guard rules on the whole command line ----------------------------------------------------
const G = String.raw`\bgit(?:\s+(?:-[Cc]\s+\S+|--?[\w-]+(?:=\S+)?))*\s+`
const sub = (name: string, rest = "") => new RegExp(G + name + String.raw`\b` + rest)
const WRITE_METHOD = String.raw`(-X|--method)\s*(POST|PUT|PATCH|DELETE)\b`
const RULES: { re: RegExp; reason: string }[] = [
  { re: /\bgh\s+pr\s+(merge|review)\b/, reason: "Merging and reviewing PRs is the user's job. Open the PR (ock ship) and stop." },
  { re: /\bgh\s+api\b[^\n]*\/pulls\/\d+\/(merge|reviews)\b/, reason: "Merging/approving PRs is the user's job." },
  { re: /\bgh\s+api\b[^\n]*\b(mergePullRequest|enablePullRequestAutoMerge|addPullRequestReview|submitPullRequestReview)\b/i, reason: "Merging/approving PRs is the user's job." },
  { re: /\bgh\s+repo\s+(delete|archive|rename)\b|\bgh\s+repo\s+edit\b[^\n]*--visibility\b/, reason: "Deleting, archiving, renaming or re-publishing repos is the user's job." },
  { re: new RegExp(String.raw`\bgh\s+api\b[^\n]*(${WRITE_METHOD}[^\n]*\/(rulesets|protection)\b|\/(rulesets|protection)\b[^\n]*${WRITE_METHOD})`, "i"), reason: "GitHub rulesets/protection are set by ock gh-setup, not the AI." },
  { re: sub("branch", String.raw`[^\n;&|]*\s(-d|-D|--delete)(\s|$)`), reason: "Deleting branches is the user's job (they choose it when closing the PR)." },
  { re: sub("push", String.raw`[^\n;&|]*(\s--delete\b|\s-d\b|\s:\S+)`), reason: "Deleting remote branches is the user's job (they choose it when closing the PR)." },
  { re: /\bgh\s+api\b[^\n]*(-X|--method)\s*DELETE\b[^\n]*\/git\/refs\//i, reason: "Don't delete branches via the API." },
  { re: sub("push", String.raw`[^\n;&|]*[\s:+](refs/heads/)?(main|master|test)(\s|$|[;&|])`), reason: "Never push to main/master/test. Push the feature branch; ock ship opens the PR." },
]
const GIT_BRANCH_WRITE = /^(commit|merge|push)$/
const GIT_WRITE = /^(add|am|apply|branch|checkout|cherry-pick|clean|commit|merge|mv|pull|push|rebase|reset|restore|revert|rm|stash|switch|tag|update-ref|worktree)$/
const PATH_WRITERS = new Set(["touch", "mkdir", "rm", "rmdir", "chmod", "chown", "truncate", "tee", "unlink", "shred"])
const DEST_WRITERS = new Set(["cp", "mv", "ln", "install", "rsync"])

function words(segment: string): string[] {
  const out: string[] = []
  const re = /"((?:\\.|[^"\\])*)"|'([^']*)'|(\S+)/g
  let m: RegExpExecArray | null
  while ((m = re.exec(segment))) out.push(m[1] ?? m[2] ?? m[3])
  return out
}
const expand = (p: string, cwd: string) =>
  path.resolve(cwd, p === "~" ? HOME : p.startsWith("~/") ? path.join(HOME, p.slice(2)) : p.replace(/^\$HOME(?=\/|$)/, HOME))
const inside = (abs: string, dir: string) => abs === dir || abs.startsWith(dir + path.sep)

function gitOut(dir: string, args: string[]): string | null {
  try {
    return execFileSync("git", ["-C", dir, ...args], { encoding: "utf8", timeout: 3000, stdio: ["ignore", "pipe", "ignore"] }).trim()
  } catch {
    return null
  }
}

/** Why `command`, run in project `root`, is not allowed — or null. */
function blocked(command: string, root: string): string | null {
  for (const rule of RULES) if (rule.re.test(command)) return rule.reason
  const outside = (abs: string) =>
    READ_ONLY.some((d) => inside(abs, d)) || (!inside(abs, root) && !WRITABLE_OUTSIDE.some((d) => inside(abs, d)))
  let cwd = root
  for (const raw of command.split(/&&|\|\||;|\||\n/)) {
    const seg = raw.trim()
    if (!seg) continue
    // redirect targets: > file, >> file, 2> file (not >&2 / 2>&1)
    for (const m of seg.matchAll(/(?:^|[^<>&\d])\d?>>?\s*(?!&)("[^"]*"|'[^']*'|[^\s;&|]+)/g)) {
      const target = expand(m[1].replace(/^["']|["']$/g, ""), cwd)
      if (outside(target)) return `Writing ${target} is outside this project (${root}). Other folders are read-only references.`
    }
    const w = words(seg.replace(/\d?>>?\s*\S+/g, ""))
    while (w.length && /^[A-Z_][A-Z0-9_]*=/.test(w[0])) w.shift() // VAR=value prefixes
    const cmd = w[0]
    if (!cmd) continue
    if (cmd === "cd") {
      cwd = expand(w[1] ?? HOME, cwd)
      continue
    }
    if (cmd === "git") {
      let dir = cwd
      let i = 1
      for (; i < w.length && w[i].startsWith("-"); i++) {
        if (w[i] === "-C" && w[i + 1]) dir = expand(w[++i], dir)
        else if (w[i] === "-c" && w[i + 1]) i++
      }
      const verb = w[i] ?? ""
      if (GIT_WRITE.test(verb) && outside(dir)) return `git ${verb} in ${dir} is outside this project (${root}). Other projects are read-only references.`
      if (GIT_BRANCH_WRITE.test(verb)) {
        const branch = gitOut(dir, ["branch", "--show-current"]) ?? ""
        if (PROTECTED.test(branch) && gitOut(dir, ["rev-parse", "--verify", "HEAD"]) !== null)
          return `You're on ${branch}. Start a branch first: ock branch <feat|fix|chore|docs>/<slug>`
      }
      continue
    }
    const args = w.slice(1).filter((a) => !a.startsWith("-"))
    let targets: string[] = []
    if (PATH_WRITERS.has(cmd)) targets = cmd === "chmod" || cmd === "chown" ? args.slice(1) : args
    else if (DEST_WRITERS.has(cmd)) targets = args.slice(-1)
    else if ((cmd === "sed" || cmd === "perl") && w.some((a) => /^-[a-zA-Z]*i/.test(a))) targets = args.slice(-1)
    for (const t of targets) {
      const abs = expand(t, cwd)
      if (outside(abs)) return `${cmd} ${abs} is outside this project (${root}). Other folders are read-only references.`
    }
  }
  return null
}

// The behavior tests call the guard directly (a plugin file has only its default export).
;(globalThis as any).__ockKitGuard = blocked

// ---- instructions: the global rules and the project's own AGENTS.md, nothing from folders above --
const GLOBAL_AGENTS = path.join(HOME, ".config/opencode/AGENTS.md")
function keepProjectInstructions(system: any[], root: string) {
  for (const p of system) {
    const entries = p?.metadata?.experimental?.instructions
    if (!Array.isArray(entries) || typeof p.text !== "string") continue
    for (const entry of entries) {
      if (entry?.key !== "core/instructions" || typeof entry.text !== "string") continue
      const kept = entry.text
        .split(/(?=^Instructions from: )/m)
        .filter((seg: string) => {
          const m = /^Instructions from: (.+)$/m.exec(seg)
          if (!m || !seg.startsWith("Instructions from: ")) return true
          const file = m[1].trim()
          return file === GLOBAL_AGENTS || inside(file, root)
        })
        .join("")
      if (kept !== entry.text && p.text.includes(entry.text)) p.text = p.text.replace(entry.text, kept)
    }
  }
}

// ---- background upkeep ------------------------------------------------------------------------
function background(args: string[], cwd: string) {
  if (process.env.OCK_NO_BACKGROUND) return
  try {
    fs.mkdirSync(STATE, { recursive: true })
    const log = fs.openSync(path.join(STATE, "background.log"), "a")
    const child = spawn(path.join(KIT, "bin/ock"), args, { cwd, detached: true, stdio: ["ignore", log, log] })
    child.unref()
  } catch {
    // upkeep must never disturb a session
  }
}

const textOf = (content: unknown): string => {
  if (typeof content === "string") return content
  if (Array.isArray(content)) return content.map((p: any) => (typeof p?.text === "string" ? p.text : "")).join(" ")
  return ""
}

// ---- one file-changing agent at a time --------------------------------------------------------
const WRITERS = new Set(["build", "debugger", "spec"])
type Child = { agent: string; dir: string; since: number }
const running = new Map<string, Child>() // child session id → what runs there
async function watchSubagents(ctx: any) {
  try {
    const types = ["session.created", "session.execution.succeeded", "session.execution.failed", "session.execution.interrupted"]
    for await (const e of ctx.event.subscribe({ types })) {
      const d = e?.data ?? {}
      if (e.type === "session.created") {
        if (d.parentID) running.set(d.sessionID, { agent: d.agent ?? "", dir: e.location?.directory ?? d.location?.directory ?? "", since: Date.now() })
      } else running.delete(d.sessionID)
    }
  } catch {
    // the guard is a safety net; if the event stream ends, OpenCode keeps working without it
  }
}
const busyWriter = (dir: string): Child | undefined => {
  for (const c of running.values()) if (WRITERS.has(c.agent) && (!c.dir || c.dir === dir)) return c
}

export default {
  id: "opencode-kit",
  async setup(ctx: any) {
    const root: string = ctx.location?.directory ?? process.cwd()
    void watchSubagents(ctx)

    await ctx.tool.transform((tools: any) => {
      for (const t of tools.list()) if (t.id === "skill" || t.id.startsWith("opencode_")) tools.remove(t.id)
    })

    await ctx.permission.hook("evaluate", (e: any) => {
      if (e.action === "subagent" && e.effect !== "deny") {
        const wanted = String(e.resources?.[0] ?? "")
        const busy = WRITERS.has(wanted) ? busyWriter(root) : undefined
        if (busy) {
          const mins = Math.max(1, Math.round((Date.now() - busy.since) / 60000))
          e.effect = "deny"
          e.message = `kit guard: ${busy.agent} is still working in this project (${mins} min so far). Only one agent changes files at a time — you'll be woken when it finishes; continue then.`
        }
        return
      }
      if (e.action !== "shell" || e.effect === "deny") return
      for (const command of e.resources ?? []) {
        const why = blocked(String(command), root)
        if (why) {
          e.effect = "deny"
          e.message = `kit guard: ${why}`
          return
        }
      }
    })

    await ctx.session.hook("title", (e: any) => {
      const users = (e.messages ?? []).filter((m: any) => m.role === "user")
      // OpenCode wraps the first message: "Here is the first message of the conversation: <message>…</message>"
      const raw = textOf(users[0]?.content)
      const inner = /<message>\s*([\s\S]*?)\s*(?:<\/message>|$)/.exec(raw)?.[1] ?? raw
      const text = inner.replace(/\s+/g, " ").trim()
      e.result = text ? (text.length > 60 ? text.slice(0, 57) + "…" : text) : "New session"
    })

    await ctx.session.hook("context", (e: any) => {
      // the worktree hint points at the `execute` tool, which this setup removes
      e.system = e.system.filter((p: any) => !(typeof p?.text === "string" && p.text.trimStart().startsWith("When you create a worktree")))
      // OpenCode also loads AGENTS.md files from folders above the project (e.g. ~/workspace/projects);
      // they belong to no project and would ride along on every request
      keepProjectInstructions(e.system, root)
      // each agent's model is fixed by agent-models.conf; the per-call model override only invites guessing
      const props = e.tools?.subagent?.input?.properties
      if (props?.model) delete props.model
    })

    await ctx.shell.hook("create.before", (e: any) => {
      const base = e.env?.PATH ?? process.env.PATH ?? ""
      e.env = { ...(e.env ?? {}), PATH: [...BIN, base].join(":"), OPENSPEC_TELEMETRY: "0" }
    })

    const g = globalThis as any
    if (!g.__ockDeployed) {
      g.__ockDeployed = true
      background(["kit", "apply", "--if-changed", "--quiet"], HOME)
    }
    if (gitOut(root, ["config", "--local", "--get", "kit.project"]) === "true") {
      background(["test", "--fetch", "--quiet", "--repo", root], root)
      const timer = setInterval(() => background(["test", "--fetch", "--quiet", "--repo", root], root), 10 * 60_000)
      timer.unref?.()
    }
  },
}
