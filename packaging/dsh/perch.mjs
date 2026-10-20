// Perch × dsh: watches dsh sessions (the terminal UI, and `dsh web` since #80)
// and pipes each state change into `perch hook dsh` (one JSON object on stdin;
// the payload is specified in #74, web's `surface` / `url` in #80).
// It only moves events: every decision about a session's state lives in Swift
// (HookAdapter). It never changes dsh's behaviour: it never appends session
// events, its waterfall listener only observes and always delegates, nothing it
// does can throw into dsh, and it never waits on perch.
//
// Setup (#76) embeds this file in perch (scripts/dsh/embed-plugin.sh), writes it
// next to the perch binary and mounts it through dsh's home patch layer,
// $DSH_HOME/cordis.patch.yml, which every profile reads:
//   - insert:
//       - id: perch
//         name: '/Users/you/.perch/bin/perch-dsh.mjs'
//         config:
//           perch: '/Users/you/.perch/bin/perch'   # optional; this is the default
//
// One dependency-free file: no imports from @deepseek-ai/* (dsh is a release
// candidate and its event names move), fields are read structurally, unknown
// events are ignored.
import { spawn } from 'node:child_process'
import { accessSync, constants } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

export const name = 'perch'

// Services only a terminal UI provides: dsh's own TUI (`tuiPrompt`) and the
// third-party dsh-tui (`tuiStatus`, `tuiDialogs`, …).
const TUI_SERVICES = ['tuiPrompt', 'tuiStatus', 'tuiDialogs', 'tuiScenes', 'tuiWorkspaces']
// `dsh web` (#80): one server, many sessions, answered in the browser. Its
// `webApp` service says the address it advertises (without the sign-in token).
const WEB_SERVICE = 'webStartup'
// `dsh headless` is one-shot, nobody waits on it: never a row. Web and headless
// can both be started from a terminal, so a TTY alone proves nothing.
const UNSUPPORTED_SERVICES = ['headlessStartup']
// A perch that hasn't exited by then doesn't hold up the session's next event.
const SPAWN_GRACE_MS = 2000

/**
 * @param {any} ctx - the cordis context
 * @param {{ perch?: string } | undefined} config
 */
export function apply(ctx, config) {
  const perch = expandHome(config?.perch) ?? join(homedir(), '.perch', 'bin', 'perch')
  /** @type {Map<string, Session>} */
  const sessions = new Map()
  /** @type {'tui' | 'web' | null | undefined} */
  let surface

  // Which surface this dsh is: 'tui', 'web', or null to stay out (headless, or
  // nothing recognisable). Decided lazily: the services don't exist yet while
  // plugins load. Only a definite answer is kept; "not yet" is asked again.
  function currentSurface() {
    if (surface !== undefined) return surface
    if (UNSUPPORTED_SERVICES.some((name) => has(ctx, name))) return (surface = null)
    if (has(ctx, WEB_SERVICE)) return (surface = 'web')
    if (!process.stdin.isTTY || !process.stdout.isTTY) return null
    if (TUI_SERVICES.some((name) => has(ctx, name))) return (surface = 'tui')
    return null
  }

  /** `dsh web`'s advertised address (`http://127.0.0.1:3080/`), or undefined. */
  function webUrl() {
    return str(read(() => ctx.get('webApp', false)?.getAdvertisedUrl()))
  }

  /** The state for a session Perch follows, or undefined to stay out of it. */
  function track(session) {
    const id = session?.id
    if (typeof id !== 'string' || id === '') return undefined
    const known = sessions.get(id)
    if (known) return known.ignored ? undefined : known
    if (!currentSurface()) return undefined
    const header = read(() => session.header) ?? {}
    // A subagent's child session is part of its parent's turn, not a row.
    const ignored = header.origin === 'subagent' || Number(header.delegationDepth) > 0
    const state = new Session(id, str(header.cwd) ?? str(read(() => session.cwd)))
    state.ignored = ignored
    sessions.set(id, state)
    return ignored ? undefined : state
  }

  function send(state, hookEventName, at, extra) {
    state.reported = true
    state.enqueue({
      hook_event_name: hookEventName,
      session_id: state.id,
      cwd: state.cwd,
      at: typeof at === 'number' && Number.isFinite(at) ? at : Date.now(),
      pid: process.pid,
      turn: state.turn,
      ...(surface === 'web' ? { surface: 'web', url: webUrl() } : {}),
      ...extra,
    }, perch)
  }

  // A turn the human didn't start (goal driver, schedule, background job) has
  // no `user/message` from the user; say so once something else happens in it.
  function ensurePrompt(state) {
    if (state.turn === undefined || state.prompted) return
    state.prompted = true
    send(state, 'Prompt', state.turnStartedAt, { keep_prompt: true })
  }

  function end(state, at) {
    sessions.delete(state.id)
    if (state.ignored || !state.reported) return
    send(state, 'SessionEnd', at)
    state.flush(perch)
  }

  ctx.on('session/event', (session, event) => guard(() => {
    const type = event?.type
    if (!HANDLED.has(type)) return
    const state = track(session)
    if (!state) return
    const data = event.data ?? {}
    const at = event.time
    switch (type) {
      case 'turn/start':
        state.turn = data.turn === undefined ? undefined : String(data.turn)
        state.turnStartedAt = at
        state.prompted = false
        state.lastText = undefined
        break
      case 'user/message': {
        if (data.source?.kind !== 'user' || state.prompted) break
        state.prompted = true
        send(state, 'Prompt', at, { prompt: text(data.content) ?? '' })
        break
      }
      case 'tool/call':
        if (typeof data.callId === 'string') state.args.set(data.callId, data.arguments)
        ensurePrompt(state)
        break
      case 'approval/asked': {
        ensurePrompt(state)
        const input = parseArguments(state.args.get(data.callId))
        send(state, 'ApprovalAsked', at, {
          tool_name: str(data.toolName),
          ...(input === undefined ? {} : { tool_input: input }),
          reason: str(data.reason),
        })
        break
      }
      case 'approval/decided':
        send(state, 'Answered', at)
        break
      case 'assistant/message': {
        const reply = text(data.message?.content)
        if (reply !== undefined) state.lastText = reply
        ensurePrompt(state)
        break
      }
      case 'turn/end': {
        ensurePrompt(state)
        const reason = data.reason ?? {}
        if (data.turn !== undefined) state.turn = String(data.turn)
        send(state, 'TurnEnd', at, {
          reason: str(reason.kind) ?? 'unknown',
          last_assistant_message: state.lastText,
          error: str(reason.error?.message),
        })
        state.args.clear()
        state.lastText = undefined
        break
      }
    }
  }))

  // ask_user_question has no session event of its own. Prepended, so it sees
  // the request before the TUI answers it; it only observes and delegates.
  ctx.on('user-questions/request', async function (request, next) {
    const state = guard(() => {
      const session = request?.agent?.session
      const tracked = track(session)
      if (!tracked) return undefined
      ensurePrompt(tracked)
      const questions = Array.isArray(request.questions) ? request.questions : []
      send(tracked, 'QuestionAsked', Date.now(), {
        questions: questions.map((q) => ({ question: str(q?.question), header: str(q?.header) })),
      })
      return tracked
    })
    try {
      return await next()
    } finally {
      // An answer and a cancel (next() throws) both resume the turn.
      if (state) guard(() => send(state, 'Answered', Date.now()))
    }
  }, true)

  ctx.on('session/disposed', (session) => guard(() => {
    const state = sessions.get(session?.id)
    if (state) end(state, Date.now())
  }))

  // `/exit` disposes plugins before sessions, so no `session/disposed` comes.
  ctx.effect(() => () => guard(() => {
    for (const state of [...sessions.values()]) end(state, Date.now())
  }), 'perch: end sessions')
}

class Session {
  constructor(id, cwd) {
    this.id = id
    this.cwd = cwd
    this.ignored = false
    /** Whether perch has heard of it, so it is owed a SessionEnd. */
    this.reported = false
    /** @type {string | undefined} */
    this.turn = undefined
    this.turnStartedAt = undefined
    this.prompted = false
    /** @type {string | undefined} */
    this.lastText = undefined
    /** `tool/call` arguments (a JSON string) by callId, until the turn ends. */
    this.args = new Map()
    this.queue = []
    this.busy = false
  }

  // One perch at a time per session, so a session's reports reach perchd in
  // order (a TurnEnd that overtook its Prompt would leave the row Running).
  // dsh never waits for any of it.
  enqueue(payload, perch) {
    this.queue.push(payload)
    if (!this.busy) this.next(perch)
  }

  next(perch) {
    const payload = this.queue.shift()
    if (!payload) return
    this.busy = true
    let done = false
    const finish = () => {
      if (done) return
      done = true
      clearTimeout(timer)
      this.busy = false
      guard(() => this.next(perch))
    }
    const timer = setTimeout(finish, SPAWN_GRACE_MS)
    timer.unref?.()
    if (!run(perch, payload, finish)) finish()
  }

  /** Send whatever is queued now: the process may be about to exit. */
  flush(perch) {
    for (const payload of this.queue.splice(0)) run(perch, payload)
  }
}

/** Spawns `perch hook dsh` with the payload on stdin; false when it can't. */
function run(perch, payload, onExit) {
  try {
    accessSync(perch, constants.X_OK)
  } catch {
    return false  // Perch isn't installed (or was uninstalled): stay out of the way.
  }
  try {
    const child = spawn(perch, ['hook', 'dsh'], { detached: true, stdio: ['pipe', 'ignore', 'ignore'] })
    child.on('error', () => onExit?.())
    child.on('exit', () => onExit?.())
    child.stdin.on('error', () => {})
    child.stdin.end(JSON.stringify(payload) + '\n')
    child.unref()
    return true
  } catch {
    return false
  }
}

const HANDLED = new Set([
  'turn/start', 'user/message', 'tool/call', 'approval/asked', 'approval/decided', 'assistant/message', 'turn/end',
])

function guard(fn) {
  try {
    return fn()
  } catch {
    return undefined
  }
}

function read(fn) {
  try {
    return fn()
  } catch {
    return undefined
  }
}

function has(ctx, service) {
  return read(() => ctx.get(service, false)) !== undefined
}

function str(value) {
  return typeof value === 'string' && value !== '' ? value : undefined
}

/** The text blocks of a message's content, joined; undefined when there are none. */
function text(content) {
  if (typeof content === 'string') return str(content)
  if (!Array.isArray(content)) return undefined
  const parts = content.filter((b) => b?.type === 'text' && typeof b.text === 'string').map((b) => b.text)
  return str(parts.join('\n').trim())
}

function parseArguments(args) {
  if (args !== null && typeof args === 'object') return args
  if (typeof args !== 'string') return undefined
  const parsed = read(() => JSON.parse(args))
  return parsed !== null && typeof parsed === 'object' ? parsed : undefined
}

function expandHome(path) {
  if (typeof path !== 'string' || path === '') return undefined
  return path === '~' || path.startsWith('~/') ? join(homedir(), path.slice(1)) : path
}
