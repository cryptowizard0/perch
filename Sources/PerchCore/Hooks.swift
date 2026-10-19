import Foundation

/// What Claude Code (and Codex, same shape) sends a command hook on stdin. Only the fields Perch uses;
/// Codex's extra fields (`turn_id`, `model`, …) and nulls are ignored. Hermes shell hooks send the same
/// top-level fields and put the event's details in `extra`. Grok sends camelCase (`sessionId`,
/// `lastAssistantMessage`, …) with snake_case copies of only some keys (`session_id`, `hook_event_name`,
/// `tool_name`, `tool_input`, `transcript_path`), so each field is read under either name. Perch's own dsh plugin
/// sends Claude-style names plus `at`, `pid`, `turn`, `keep_prompt` and `questions` (see `HookAdapter.dsh`).
public struct HookInput: Decodable, Equatable, Sendable {
    public var sessionID: String
    public var event: String
    public var cwd: String?
    /// Claude Code's session log (JSONL); see `ClaudeTranscript`.
    public var transcriptPath: String?
    public var notificationType: String?
    public var message: String?
    public var lastAssistantMessage: String?
    /// UserPromptSubmit: what the human typed.
    public var prompt: String?
    /// StopFailure: the error type (`rate_limit`, …). Any JSON, so an unexpected shape never breaks decoding.
    public var error: JSONValue?
    /// PermissionRequest / PostToolUse.
    public var toolName: String?
    public var toolInput: [String: JSONValue]?
    /// Hermes: the event's keyword arguments.
    public var extra: Extra?
    /// Grok: the turn an event belongs to (absent for session-level events).
    public var promptID: String?
    /// Grok: why a Stop / StopCancelled / SessionEnd fired (`end_turn`, `shutdown`, `user_interrupt`, …).
    public var reason: String?
    /// Grok StopCancelled: `user`, `runtime` or `unknown`.
    public var cancelledBy: String?
    /// Grok: set on the events of a subagent's own session.
    public var subagentType: String?
    /// dsh: when the event happened (sent as epoch ms).
    public var at: Date?
    /// dsh: the dsh process, as its plugin says (`process.pid`); see `AgentProcess.dsh(claimed:parent:)`.
    public var pid: Int32?
    /// dsh: the turn an event belongs to (a string or a number on the wire).
    public var turn: String?
    /// dsh Prompt: nobody typed it (the goal driver, a schedule, a background job woke dsh).
    public var keepPrompt: Bool?
    /// dsh QuestionAsked: what `ask_user_question` asks.
    public var questions: [Question]?

    /// One of dsh's `ask_user_question` questions (its options are left out).
    public struct Question: Decodable, Equatable, Sendable {
        public var question: String?
        public var header: String?

        public init(question: String? = nil, header: String? = nil) {
            self.question = question
            self.header = header
        }
    }

    /// The Hermes `extra` fields Perch reads (the rest, like the whole conversation history, is skipped).
    public struct Extra: Decodable, Equatable, Sendable {
        public var userMessage: String?
        public var assistantResponse: String?
        public var platform: String?
        /// pre_approval_request / post_approval_response.
        public var command: String?
        public var description: String?
        public var sessionKey: String?
        public var surface: String?
        public var toolCallID: String?

        enum CodingKeys: String, CodingKey {
            case platform, command, description, surface
            case userMessage = "user_message"
            case assistantResponse = "assistant_response"
            case sessionKey = "session_key"
            case toolCallID = "tool_call_id"
        }

        public init(userMessage: String? = nil, assistantResponse: String? = nil, platform: String? = nil,
                    command: String? = nil, description: String? = nil, sessionKey: String? = nil,
                    surface: String? = nil, toolCallID: String? = nil) {
            self.userMessage = userMessage
            self.assistantResponse = assistantResponse
            self.platform = platform
            self.command = command
            self.description = description
            self.sessionKey = sessionKey
            self.surface = surface
            self.toolCallID = toolCallID
        }
    }

    enum CodingKeys: String, CodingKey {
        case cwd, message, extra, prompt, error, reason
        case sessionID = "session_id", sessionIDCamel = "sessionId"
        case event = "hook_event_name"
        case transcriptPath = "transcript_path", transcriptPathCamel = "transcriptPath"
        case notificationType = "notification_type", notificationTypeCamel = "notificationType"
        case lastAssistantMessage = "last_assistant_message", lastAssistantMessageCamel = "lastAssistantMessage"
        case toolName = "tool_name", toolNameCamel = "toolName"
        case toolInput = "tool_input", toolInputCamel = "toolInput"
        case promptID = "promptId", cancelledBy, subagentType
        case at, pid, turn, questions
        case keepPrompt = "keep_prompt"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys, _ camel: CodingKeys) throws -> String? {
            try c.decodeIfPresent(String.self, forKey: key) ?? c.decodeIfPresent(String.self, forKey: camel)
        }
        if let id = try string(.sessionID, .sessionIDCamel) {
            sessionID = id
        } else {
            throw DecodingError.keyNotFound(CodingKeys.sessionID, .init(codingPath: c.codingPath, debugDescription: "no session_id"))
        }
        event = try c.decode(String.self, forKey: .event)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        transcriptPath = try string(.transcriptPath, .transcriptPathCamel)
        notificationType = try string(.notificationType, .notificationTypeCamel)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        lastAssistantMessage = try string(.lastAssistantMessage, .lastAssistantMessageCamel)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        error = try c.decodeIfPresent(JSONValue.self, forKey: .error)
        toolName = try string(.toolName, .toolNameCamel)
        toolInput = Self.object(c, .toolInput) ?? Self.object(c, .toolInputCamel)
        extra = try c.decodeIfPresent(Extra.self, forKey: .extra)
        // Grok's own fields: an unexpected shape from another agent must never break decoding.
        promptID = try? c.decodeIfPresent(String.self, forKey: .promptID)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        cancelledBy = try? c.decodeIfPresent(String.self, forKey: .cancelledBy)
        subagentType = try? c.decodeIfPresent(String.self, forKey: .subagentType)
        // dsh's fields, just as tolerant.
        at = (try? c.decodeIfPresent(Double.self, forKey: .at)).flatMap { $0 }.map { Date(timeIntervalSince1970: $0 / 1000) }
        pid = (try? c.decodeIfPresent(Int32.self, forKey: .pid)).flatMap { $0 }
        turn = (try? c.decodeIfPresent(String.self, forKey: .turn)).flatMap { $0 }
            ?? (try? c.decodeIfPresent(Int.self, forKey: .turn)).flatMap { $0 }.map(String.init)
        keepPrompt = (try? c.decodeIfPresent(Bool.self, forKey: .keepPrompt)).flatMap { $0 }
        questions = (try? c.decodeIfPresent([Question].self, forKey: .questions)).flatMap { $0 }
    }

    /// An object, or the JSON text of one (dsh keeps a tool call's arguments as a string); nil for anything else.
    private static func object(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String: JSONValue]? {
        if let object = try? c.decodeIfPresent([String: JSONValue].self, forKey: key) { return object }
        guard let text = try? c.decodeIfPresent(String.self, forKey: key) else { return nil }
        return try? JSONDecoder().decode([String: JSONValue].self, from: Data(text.utf8))
    }

    public init(sessionID: String, event: String, cwd: String? = nil, notificationType: String? = nil,
                message: String? = nil, lastAssistantMessage: String? = nil, toolName: String? = nil,
                toolInput: [String: JSONValue]? = nil, extra: Extra? = nil, prompt: String? = nil, error: JSONValue? = nil,
                transcriptPath: String? = nil, promptID: String? = nil, reason: String? = nil, cancelledBy: String? = nil,
                subagentType: String? = nil, at: Date? = nil, pid: Int32? = nil, turn: String? = nil, keepPrompt: Bool? = nil,
                questions: [Question]? = nil) {
        self.at = at
        self.pid = pid
        self.turn = turn
        self.keepPrompt = keepPrompt
        self.questions = questions
        self.promptID = promptID
        self.reason = reason
        self.cancelledBy = cancelledBy
        self.subagentType = subagentType
        self.prompt = prompt
        self.transcriptPath = transcriptPath
        self.error = error
        self.sessionID = sessionID
        self.event = event
        self.cwd = cwd
        self.notificationType = notificationType
        self.message = message
        self.lastAssistantMessage = lastAssistantMessage
        self.toolName = toolName
        self.toolInput = toolInput
        self.extra = extra
    }

    /// The string fields of `tool_input` (command, file_path, url, …); what the allowlist and the notch look at.
    public var toolStrings: [String: String] {
        (toolInput ?? [:]).compactMapValues { if case .string(let s) = $0 { return s } else { return nil } }
    }
}

/// Turns one hook invocation into perchd requests. Pure; `perch hook <agent>` does the I/O.
///
/// Claude Code and Codex drive the session state machine with a `session_report` per event (see `SessionReport`).
/// The session is the only state: the one item they still post is an allowlisted PermissionRequest's request.
///
/// | event | session report |
/// | --- | --- |
/// | UserPromptSubmit | prompt (first line) → running |
/// | Notification (needs you) | waiting with the message (a recorded command stays) |
/// | PermissionRequest | waiting with the full command; see `permission(for:…)`, handled by `perch hook` itself (request if allowlisted) |
/// | PostToolUse / PostToolUseFailure | resume → running; resolves the session's request |
/// | Stop | stop → done with the last reply's first line |
/// | StopFailure | failure → failed with the error type |
/// | Interrupt (Codex) | interrupt → idle |
/// | SessionEnd | end → removed |
///
/// Codex sends the same JSON for the events it has. It has no Notification, StopFailure or PostToolUseFailure
/// (it needs you only through PermissionRequest), and adds Interrupt (Esc on a running turn, no Stop).
///
/// Hermes Agent (shell hooks, snake_case events; details in `extra`):
///
/// | event | requests |
/// | --- | --- |
/// | pre_llm_call | session_start; resolve the last notice |
/// | post_llm_call | add a notice with the reply |
/// | on_session_end (end of every turn) | session_end |
/// | pre_approval_request | add waiting with the full command (see `approvalKey`): answer where Hermes asks |
/// | post_approval_response (answered or timed out) | resolve it |
///
/// Hermes approval hooks only observe, so the notch can never answer them. Subagent and background-review
/// turns are ignored; gateway turns (Telegram, …) are named after the platform and have no terminal link.
///
/// Grok Build: Claude-style event names, camelCase payloads; see `grok(_:link:now:)`. It has no PermissionRequest
/// and its PreToolUse `allow` never skips the prompt, so the notch can never answer Grok either.
///
/// dsh: Perch's own plugin sends normalised events; see `dsh(_:link:now:)`. The notch never answers dsh.
public enum HookAdapter {
    /// Notification types that mean "an agent is blocked on the human". `idle_prompt` is left out on purpose:
    /// Stop already marks the session done, and every finished turn turning orange would dilute the signal.
    public static let waitingNotifications: Set<String> = ["permission_prompt", "elicitation_dialog", "agent_needs_input"]
    /// Hermes's reply notice fades after this long.
    public static let noticeLifetime: TimeInterval = 10 * 60
    static let summaryLength = 140

    public static func waitingKey(agent: String, session: String) -> String { "\(agent):\(session)" }
    public static func noticeKey(agent: String, session: String) -> String { "\(agent):\(session):done" }
    /// Events that start a turn: the human just typed, so that terminal has focus.
    static let turnStarts: Set<String> = ["UserPromptSubmit", "pre_llm_call", "Prompt"]

    /// Whether the human just typed into this event's terminal. A prompt Claude Code injects on its own (a background
    /// task finishing) fires UserPromptSubmit too, while focus may be anywhere; so does a dsh turn its plugin marks
    /// `keep_prompt`.
    public static func startsTurn(_ input: HookInput) -> Bool {
        turnStarts.contains(input.event) && keepsPrompt(input) == nil
    }

    /// `keep_prompt` for a prompt report: set only when the agent injected the prompt.
    static func keepsPrompt(_ input: HookInput) -> Bool? {
        input.keepPrompt == true || isInjected(input.prompt ?? "") ? true : nil
    }

    /// A prompt the agent sent itself rather than the human: Claude Code's `<task-notification>`, which wakes the model
    /// when a background command or agent finishes.
    static func isInjected(_ prompt: String) -> Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<task-notification>")
    }

    /// Another agent running this agent's hooks. Grok runs Claude Code's hooks from ~/.claude/settings.json by default
    /// (`[compat.claude] hooks`); its own `perch hook grok` reports its sessions, so the borrowed call says nothing.
    /// Grok sets `GROK_HOOK_EVENT` for every hook it runs. dsh's Claude Code / Codex hooks bridges (not mounted by
    /// default) run those files too, with no such variable, so for them it is the process chain: `processes` are
    /// `pid`'s ancestors (see `AgentProcess.insideDsh`).
    public static func isForeign(agent: String, environment: [String: String], processes: [Int32: ProcessEntry] = [:],
                                 from pid: Int32 = 0) -> Bool {
        if agent != "grok", environment["GROK_HOOK_EVENT"] != nil { return true }
        return ["claude-code", "codex"].contains(agent) && AgentProcess.insideDsh(agent: agent, from: pid, in: processes)
    }

    public static func requests(for input: HookInput, agent: String, link: String?, now: Date) -> [Request] {
        if agent == "grok" { return grok(input, link: link, now: now) }
        if agent == "dsh" { return dsh(input, link: link, now: now) }
        func report(_ kind: SessionReport.Kind, _ fill: (inout SessionReport) -> Void = { _ in }) -> [Request] {
            [Request(op: .sessionReport, report: sessionReport(input, kind, agent: agent, link: link, now: now, fill))]
        }
        switch input.event {
        case "UserPromptSubmit":
            return report(.prompt) { $0.prompt = promptLine(input.prompt ?? ""); $0.keepPrompt = keepsPrompt(input) }
        case "Notification":
            guard let type = input.notificationType, waitingNotifications.contains(type) else { return [] }
            // A late `permission_prompt` keeps the full command PermissionRequest recorded (keep_detail).
            return report(.waiting) {
                $0.detail = input.message.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty } ?? waitingForAnswer
                $0.keepDetail = type == "permission_prompt"
            }
        case "Stop":
            return report(.stop) { $0.lastMessage = oneLine(input.lastAssistantMessage ?? "") }
        case "StopFailure":
            return report(.failure) { $0.error = input.errorType }
        case "Interrupt":
            return report(.interrupt)
        case "SessionEnd":
            return report(.end)
        case "PostToolUse", "PostToolUseFailure":
            return report(.resume)

        default:
            return hermes(input, agent: agent, link: link, now: now)
        }
    }

    /// What a needs-you session says when the agent asked something without saying what.
    public static let waitingForAnswer = "Waiting for your answer"
    public static let answerInTerminal = "Answer in the terminal"

    /// A report about `input`'s session, carrying what every event knows (agent, project, directory, jump link;
    /// for Claude Code its transcript, where perchd finds the interruptions no hook reports).
    public static func sessionReport(_ input: HookInput, _ kind: SessionReport.Kind, agent: String, link: String?, now: Date,
                                     _ fill: (inout SessionReport) -> Void = { _ in }) -> SessionReport {
        var report = SessionReport(id: input.sessionID, kind: kind, at: now, source: agent, title: projectName(input.cwd),
                                   cwd: input.cwd, link: link)
        if agent == "claude-code" { report.transcriptPath = input.transcriptPath.flatMap { $0.isEmpty ? nil : $0 } }
        fill(&report)
        return report
    }

    // MARK: - Grok

    /// Grok Build's hook events (all run in the foreground, so the adapter must stay quick):
    ///
    /// | event | session report |
    /// | --- | --- |
    /// | UserPromptSubmit | prompt → running; its `promptId` becomes the current turn |
    /// | Notification `permission_prompt` (and other needs-you types) | waiting with Grok's message + "Answer in the terminal" |
    /// | Notification `idle_prompt` | settle: a session still running / waiting goes idle (turns that report no end) |
    /// | PostToolUse / PostToolUseFailure | resume → running (the permission was answered in the terminal) |
    /// | Stop with `reason: end_turn` | stop → done with the last reply's first line; the session-end Stop is ignored |
    /// | StopFailure | failure → failed with the error type |
    /// | StopCancelled | by the user (Ctrl+C, a declined or dismissed prompt): interrupt → idle; by Grok itself (`max_turns`, `no_progress`): failed |
    /// | SessionEnd | end → removed |
    ///
    /// Turn-end reports carry the `promptId` (see `SessionReport.turn`): Grok sends a cancelled turn's report off its
    /// main loop, sometimes after the next prompt. Events from a subagent's own session (`subagentType`) are ignored.
    static func grok(_ input: HookInput, link: String?, now: Date) -> [Request] {
        if let subagent = input.subagentType, !subagent.isEmpty { return [] }
        func report(_ kind: SessionReport.Kind, _ fill: (inout SessionReport) -> Void = { _ in }) -> [Request] {
            [Request(op: .sessionReport, report: sessionReport(input, kind, agent: "grok", link: link, now: now) {
                $0.turn = input.promptID
                fill(&$0)
            })]
        }
        switch input.event {
        case "UserPromptSubmit":
            return report(.prompt) { $0.prompt = promptLine(input.prompt ?? ""); $0.keepPrompt = keepsPrompt(input) }
        case "Notification":
            guard let type = input.notificationType else { return [] }
            if type == "idle_prompt" { return report(.settle) }
            guard waitingNotifications.contains(type) else { return [] }
            // Grok only says "Tool permission requested", without the command.
            let message = input.message.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty } ?? waitingForAnswer
            return report(.waiting) { $0.detail = message + "\n" + answerInTerminal }
        case "PostToolUse", "PostToolUseFailure":
            return report(.resume)
        case "Stop":
            // Grok sends one more Stop when the session ends (`shutdown`, `channel_closed`); SessionEnd covers that.
            guard input.reason == "end_turn" else { return [] }
            return report(.stop) { $0.lastMessage = oneLine(input.lastAssistantMessage ?? "") }
        case "StopFailure":
            return report(.failure) { $0.error = input.errorType }
        case "StopCancelled":
            guard input.cancelledBy == "runtime" else { return report(.interrupt) }
            return report(.failure) { $0.error = input.reason.flatMap { $0.nilIfEmpty } ?? "unknown" }
        case "SessionEnd":
            return report(.end)
        default:
            return []
        }
    }

    // MARK: - dsh

    /// What Perch's dsh plugin sends (one event per `perch hook dsh`, already normalised; dsh's raw events stay in
    /// the plugin, the decisions here):
    ///
    /// | event | session report |
    /// | --- | --- |
    /// | Prompt | prompt → running; `turn` becomes the current turn; `keep_prompt` when nobody typed it |
    /// | ApprovalAsked | waiting with the full command + "Answer in the terminal: <reason>" (never a request) |
    /// | QuestionAsked | waiting with the first question (and how many more) + "Answer in the terminal" |
    /// | Answered (allowed, denied, cancelled; a question answered or dismissed) | resume → running |
    /// | TurnEnd `completed` / `max-tokens` / anything else | stop → done with the last reply's first line |
    /// | TurnEnd `error` | failure → failed with dsh's message |
    /// | TurnEnd `aborted` (Esc) / `blocked` (a hook refused the prompt) | interrupt → idle |
    /// | SessionEnd | end → removed |
    ///
    /// The report time is dsh's own (`at`): the plugin spawns one perch per event without waiting, so reports can
    /// arrive out of order, and perchd drops what is older than the session's last event. Every report carries
    /// `turn`, so a late TurnEnd for an earlier turn is dropped too (as for Grok's `promptId`).
    static func dsh(_ input: HookInput, link: String?, now: Date) -> [Request] {
        func report(_ kind: SessionReport.Kind, _ fill: (inout SessionReport) -> Void = { _ in }) -> [Request] {
            [Request(op: .sessionReport, report: sessionReport(input, kind, agent: "dsh", link: link, now: input.at ?? now) {
                $0.turn = input.turn
                fill(&$0)
            })]
        }
        switch input.event {
        case "Prompt":
            let keep = keepsPrompt(input)
            return report(.prompt) { $0.prompt = keep == true ? nil : promptLine(input.prompt ?? ""); $0.keepPrompt = keep }
        case "ApprovalAsked":
            let reason = input.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return report(.waiting) {
                $0.detail = dshCommand(tool: input.toolName, input: input.toolInput) + "\n" + answerInTerminal
                    + (reason.isEmpty ? "" : ": \(reason)")
            }
        case "QuestionAsked":
            return report(.waiting) { $0.detail = dshQuestion(input.questions ?? []) + "\n" + answerInTerminal }
        case "Answered":
            return report(.resume)
        case "TurnEnd":
            switch input.reason {
            case "error": return report(.failure) { $0.error = input.errorMessage }
            case "aborted", "blocked": return report(.interrupt)
            default: return report(.stop) { $0.lastMessage = oneLine(dshReply(input.lastAssistantMessage ?? "")) }
            }
        case "SessionEnd":
            return report(.end)
        default:
            return []
        }
    }

    /// The reply without dsh-tui's `⏵` narration lines: its `dsh-working-activity` plugin has the model open with a
    /// "⏵ what I'm doing" line, which the TUI shows live and strips from the chat, so the row's Done line should too.
    /// A reply that is nothing but narration keeps it, without the marker.
    static func dshReply(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        func isNarration(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).hasPrefix("⏵") }
        let reply = lines.filter { !isNarration($0) }
        if reply.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { return reply.joined(separator: "\n") }
        return lines.map { line in
            var line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("⏵") { line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
            return line
        }.joined(separator: "\n")
    }

    /// The full command dsh asks about, never shortened: `bash`'s command itself, any other tool its name and every
    /// argument.
    static func dshCommand(tool: String?, input: [String: JSONValue]?) -> String {
        let tool = tool.flatMap { $0.trimmingCharacters(in: .whitespaces).nilIfEmpty } ?? "tool"
        let input = input ?? [:]
        if tool.lowercased() == "bash" {
            if case .string(let command)? = input["command"], !command.isEmpty { return command }
            return tool
        }
        let arguments = input.sorted { $0.key < $1.key }.map { "\($0.key)=\(text($0.value))" }
        return ([tool] + arguments).joined(separator: " ")
    }

    /// A question as the row shows it: the first one (its header if it has no text), and how many more there are.
    static func dshQuestion(_ questions: [HookInput.Question]) -> String {
        let first = questions.first.flatMap { q in
            [q.question, q.header].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }.first
        }
        guard let first else { return waitingForAnswer }
        return questions.count > 1 ? "\(first) (and \(questions.count - 1) more)" : first
    }

    /// A tool argument as text: strings as they are, anything else as compact JSON.
    private static func text(_ value: JSONValue) -> String {
        if case .string(let s) = value { return s }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    // MARK: - Hermes

    /// A Hermes approval that never got its response (Hermes died mid-approval) fades after this long, well past
    /// Hermes's own timeouts (`approvals.timeout` 60 s in the CLI, `gateway_timeout` 300 s).
    public static let approvalLifetime: TimeInterval = 15 * 60
    /// The fixed end of the prompt Hermes gives its background skill / memory review, a fork that shares the
    /// parent's session id (agent/background_review.py). Nothing else tells its turns apart.
    static let backgroundReviewMarker = "You can only call memory and skill management tools"

    static func hermes(_ input: HookInput, agent: String, link: String?, now: Date) -> [Request] {
        let extra = input.extra ?? .init()
        // Delegated children and the background review run turns of their own: Hermes working, not waiting on you.
        if extra.platform == "subagent" || extra.userMessage?.contains(backgroundReviewMarker) == true { return [] }
        let session = input.sessionID
        let platform = gatewayPlatform(extra)
        let place = platform ?? projectName(input.cwd)
        // Gateway turns happen in a chat app: no terminal to jump to, whatever started the gateway.
        let link = platform == nil ? link : nil
        var meta = ["session_id": session]
        if let cwd = input.cwd { meta["cwd"] = cwd }

        switch input.event {
        case "pre_llm_call":
            return [
                Request(op: .sessionStart, session: Session(id: session, source: agent, title: place, link: link, startedAt: now)),
                Request(op: .done, key: noticeKey(agent: agent, session: session)),
            ]
        case "post_llm_call":
            return [Request(op: .add, item: Item(
                title: "\(place) · \(summary(extra.assistantResponse))", kind: .notice, source: agent,
                link: link, meta: meta, key: noticeKey(agent: agent, session: session),
                expiresAt: now.addingTimeInterval(noticeLifetime)
            ))]
        case "on_session_end":
            return [Request(op: .sessionEnd, id: session, at: now)]
        case "pre_approval_request":
            var approval = ["tool": "terminal", "session_key": extra.sessionKey ?? "default"]
            if let cwd = input.cwd { approval["cwd"] = cwd }
            if let reason = extra.description, !reason.isEmpty { approval["terminal_reason"] = reason }
            if let platform { approval["answer_in"] = platform }
            return [Request(op: .add, item: Item(
                title: "\(place) · \(extra.command ?? "a command")", kind: .task, status: .waiting, source: agent,
                link: link, meta: approval, key: approvalKey(agent: agent, extra),
                expiresAt: now.addingTimeInterval(approvalLifetime)
            ))]
        case "post_approval_response":
            return [Request(op: .done, key: approvalKey(agent: agent, extra))]
        default:
            return []
        }
    }

    /// Approval hooks carry the gateway's `session_key` (`default` in the CLI), not the session id; the tool call
    /// id tells apart approvals queued in the same chat (and CLI sessions, which all share `default`).
    static func approvalKey(agent: String, _ extra: HookInput.Extra) -> String {
        let call = extra.toolCallID.flatMap { $0.isEmpty ? nil : ":\($0)" } ?? ""
        return waitingKey(agent: agent, session: (extra.sessionKey ?? "default") + call)
    }

    /// The gateway's platform ("Telegram"); nil in the terminal CLI. Turn events say `platform`; approvals only
    /// say `surface: gateway` and a session key `agent:<profile>:<platform>:…`.
    static func gatewayPlatform(_ extra: HookInput.Extra) -> String? {
        var name: String?
        if let platform = extra.platform, !platform.isEmpty, platform != "cli" {
            name = platform
        } else if extra.surface == "gateway" {
            let parts = (extra.sessionKey ?? "").split(separator: ":")
            name = parts.count > 2 && parts[0] == "agent" ? String(parts[2]) : "Hermes"
        }
        return name.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    // MARK: - PermissionRequest

    /// Default time a PermissionRequest waits for the notch before the terminal's own prompt takes over.
    public static let permissionWait: TimeInterval = 20

    public enum PermissionPlan: Equatable, Sendable {
        /// On the allowlist: post this request and wait for Allow / Deny.
        case ask(Item)
        /// Not approvable from the notch: return no decision at once; the session says why and where to answer.
        case terminal(reason: String)
    }

    public static func permission(for input: HookInput, agent: String, link: String?, allowlist: Allowlist,
                                  wait: TimeInterval = permissionWait, now: Date, home: String = NSHomeDirectory()) -> PermissionPlan {
        let tool = input.toolName ?? "tool"
        let fields = input.toolStrings
        let text = PermissionPrompt.title(tool: tool, input: fields)
        var meta = ["session_id": input.sessionID, "tool": tool, "project": projectName(input.cwd)]
        if let cwd = input.cwd { meta["cwd"] = cwd }
        if let description = fields["description"], !description.isEmpty { meta["description"] = description }
        switch allowlist.verdict(tool: tool, input: fields, home: home) {
        case .notch:
            return .ask(Item(title: text, kind: .request, status: .waiting, source: agent, link: link, meta: meta,
                             options: ["allow", "deny"], expiresAt: now.addingTimeInterval(wait)))
        case .terminal(let reason):
            return .terminal(reason: reason)
        }
    }

    /// The session side of a PermissionRequest: needs you, with the full command, and where to answer when the
    /// notch cannot (an allowlisted request carries its own Allow / Deny).
    public static func permissionReport(for input: HookInput, plan: PermissionPlan, agent: String, link: String?,
                                        now: Date) -> SessionReport {
        var detail = PermissionPrompt.title(tool: input.toolName ?? "tool", input: input.toolStrings)
        if case .terminal(let reason) = plan {
            detail += "\n" + answerInTerminal + (reason.isEmpty ? "" : ": \(reason)")
        }
        return sessionReport(input, .waiting, agent: agent, link: link, now: now) { $0.detail = detail }
    }

    /// The notch request timed out (or was closed without an answer): the terminal's own prompt is showing now.
    public static func terminalReport(after request: Item, input: HookInput, agent: String, link: String?, now: Date) -> SessionReport {
        sessionReport(input, .waiting, agent: agent, link: link, now: now) { $0.detail = request.title + "\n" + answerInTerminal }
    }

    /// What the hook prints for an answer; nil (print nothing, the terminal asks) for anything but allow / deny.
    /// Claude Code and Codex read the same shape, so `agent` does not change it (yet).
    public static func decision(agent: String, answer: String) -> String? {
        guard answer == "allow" || answer == "deny" else { return nil }
        var decision: [String: String] = ["behavior": answer]
        if answer == "deny" { decision["message"] = "Denied by the user from the Perch notch." }
        let output = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision] as [String: Any]]
        guard let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// "~/work/src/perch" → "perch".
    static func projectName(_ cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "agent" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? cwd : name
    }

    /// The first meaningful line of the agent's last message, without markdown decoration, capped.
    /// A prompt's first line as the notch shows it. Claude Code hands shell-mode (`!cmd`) and slash-command prompts
    /// over in tags; those read as what was typed: `$ cmd`, `/name args`. An injected prompt (`isInjected`) has no line.
    static func promptLine(_ prompt: String) -> String? {
        if isInjected(prompt) { return nil }
        func tag(_ name: String) -> String? {
            guard let open = prompt.range(of: "<\(name)>"),
                  let close = prompt.range(of: "</\(name)>", range: open.upperBound..<prompt.endIndex) else { return nil }
            return prompt[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let name = tag("command-name"), !name.isEmpty {
            let command = name.hasPrefix("/") ? name : "/" + name
            return oneLine([command, tag("command-args") ?? ""].filter { !$0.isEmpty }.joined(separator: " "))
        }
        if let command = tag("bash-input"), let line = command.split(whereSeparator: \.isNewline).first {
            // Not `oneLine`: its markdown cleanup would change the command (backticks, `**`).
            let line = "$ " + line.trimmingCharacters(in: .whitespaces)
            return line.count > summaryLength ? String(line.prefix(summaryLength - 1)) + "…" : line
        }
        return oneLine(prompt)
    }

    static func summary(_ message: String?) -> String {
        oneLine(message ?? "") ?? "finished"
    }

    private static func oneLine(_ text: String) -> String? {
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            while let first = line.first, "#>*-`".contains(first) { line.removeFirst() }
            line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            return line.count > summaryLength ? String(line.prefix(summaryLength - 1)) + "…" : line
        }
        return nil
    }
}

extension HookInput {
    /// StopFailure's `error` when it is a string, else "unknown".
    public var errorType: String {
        if case .string(let type)? = error, !type.isEmpty { return type }
        return "unknown"
    }

    /// dsh TurnEnd's `error`: the message itself, or an error object's `message`; else "unknown".
    public var errorMessage: String {
        if case .object(let object)? = error, case .string(let message)? = object["message"], !message.isEmpty { return message }
        return errorType
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
