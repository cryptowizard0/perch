import Foundation

/// What Claude Code (and Codex, same shape) sends a command hook on stdin. Only the fields Perch uses;
/// Codex's extra fields (`turn_id`, `model`, …) and nulls are ignored. Hermes shell hooks send the same
/// top-level fields and put the event's details in `extra`.
public struct HookInput: Decodable, Equatable, Sendable {
    public var sessionID: String
    public var event: String
    public var cwd: String?
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
        case cwd, message, extra, prompt, error
        case sessionID = "session_id"
        case event = "hook_event_name"
        case notificationType = "notification_type"
        case lastAssistantMessage = "last_assistant_message"
        case toolName = "tool_name"
        case toolInput = "tool_input"
    }

    public init(sessionID: String, event: String, cwd: String? = nil, notificationType: String? = nil,
                message: String? = nil, lastAssistantMessage: String? = nil, toolName: String? = nil,
                toolInput: [String: JSONValue]? = nil, extra: Extra? = nil, prompt: String? = nil, error: JSONValue? = nil) {
        self.prompt = prompt
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
/// Until the notch shows sessions, the waiting / notice items it shows today are still posted next to them.
///
/// | event | session report | items |
/// | --- | --- | --- |
/// | UserPromptSubmit | prompt (first line) → running | resolve this session's waiting item and last "finished" notice |
/// | Notification (needs you) | waiting with the message (a recorded command stays) | add waiting, key `<agent>:<session>` |
/// | PermissionRequest | waiting with the full command; see `permission(for:…)`, handled by `perch hook` itself | request or waiting |
/// | PostToolUse / PostToolUseFailure | resume → running; resolves the session's request | resolve the waiting item |
/// | Stop | stop → done with the last reply's first line | resolve the waiting item; add a notice, key `<agent>:<session>:done` |
/// | StopFailure | failure → failed with the error type | resolve the waiting item |
/// | Interrupt (Codex) | interrupt → idle | resolve the waiting item |
/// | SessionEnd | end → removed | resolve the waiting item |
///
/// Codex sends the same JSON for the events it has. It has no Notification, StopFailure or PostToolUseFailure
/// (its waiting items come only from PermissionRequest), and adds Interrupt (Esc on a running turn, no Stop).
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
public enum HookAdapter {
    /// Notification types that mean "an agent is blocked on the human". `idle_prompt` is left out on purpose:
    /// Stop already posts a notice, and every finished turn turning orange would dilute the signal.
    public static let waitingNotifications: Set<String> = ["permission_prompt", "elicitation_dialog", "agent_needs_input"]
    /// The Stop notice fades after this long.
    public static let noticeLifetime: TimeInterval = 10 * 60
    static let summaryLength = 140

    public static func waitingKey(agent: String, session: String) -> String { "\(agent):\(session)" }
    public static func noticeKey(agent: String, session: String) -> String { "\(agent):\(session):done" }
    /// Events that start a turn: the human just typed, so that terminal has focus.
    public static let turnStarts: Set<String> = ["UserPromptSubmit", "pre_llm_call"]

    /// `alreadyWaiting`: this session already has an active waiting item. A late `permission_prompt` notification
    /// then leaves it alone, so the full command text from PermissionRequest is not replaced by a generic message.
    public static func requests(for input: HookInput, agent: String, link: String?, now: Date,
                                alreadyWaiting: Bool = false) -> [Request] {
        let session = input.sessionID
        let waiting = waitingKey(agent: agent, session: session)
        let project = projectName(input.cwd)
        var meta = ["session_id": session]
        if let cwd = input.cwd { meta["cwd"] = cwd }

        func report(_ kind: SessionReport.Kind, _ fill: (inout SessionReport) -> Void = { _ in }) -> Request {
            Request(op: .sessionReport, report: sessionReport(input, kind, agent: agent, link: link, now: now, fill))
        }
        let resolveWaiting = Request(op: .done, key: waiting)
        switch input.event {
        case "UserPromptSubmit":
            return [
                report(.prompt) { $0.prompt = oneLine(input.prompt ?? "") },
                resolveWaiting,
                Request(op: .done, key: noticeKey(agent: agent, session: session)),
            ]
        case "Notification":
            guard let type = input.notificationType, waitingNotifications.contains(type) else { return [] }
            let question = report(.waiting) {
                $0.detail = input.message.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty } ?? waitingForAnswer
                $0.keepDetail = type == "permission_prompt"
            }
            if alreadyWaiting && type == "permission_prompt" { return [question] }
            meta["notification_type"] = type
            let message = oneLine(input.message ?? "") ?? "needs you"
            return [question, Request(op: .add, item: Item(
                title: "\(project) · \(message)", kind: .task, status: .waiting, source: agent,
                link: link, meta: meta, key: waiting
            ))]
        case "Stop":
            return [
                report(.stop) { $0.lastMessage = oneLine(input.lastAssistantMessage ?? "") },
                resolveWaiting,
                Request(op: .add, item: Item(
                    title: "\(project) · \(summary(input.lastAssistantMessage))", kind: .notice, source: agent,
                    link: link, meta: meta, key: noticeKey(agent: agent, session: session),
                    expiresAt: now.addingTimeInterval(noticeLifetime)
                )),
            ]
        case "StopFailure":
            return [report(.failure) { $0.error = input.errorType }, resolveWaiting]
        case "Interrupt":
            return [report(.interrupt), resolveWaiting]
        case "SessionEnd":
            return [report(.end), resolveWaiting]
        case "PostToolUse", "PostToolUseFailure":
            return [report(.resume), resolveWaiting]

        default:
            return hermes(input, agent: agent, link: link, now: now)
        }
    }

    /// What a needs-you session says when the agent asked something without saying what.
    public static let waitingForAnswer = "Waiting for your answer"
    public static let answerInTerminal = "Answer in the terminal"

    /// A report about `input`'s session, carrying what every event knows (agent, project, directory, jump link).
    public static func sessionReport(_ input: HookInput, _ kind: SessionReport.Kind, agent: String, link: String?, now: Date,
                                     _ fill: (inout SessionReport) -> Void = { _ in }) -> SessionReport {
        var report = SessionReport(id: input.sessionID, kind: kind, at: now, source: agent, title: projectName(input.cwd),
                                   cwd: input.cwd, link: link)
        fill(&report)
        return report
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
        /// Not approvable from the notch: post this waiting "go to terminal" item and return no decision at once.
        case terminal(Item)
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
            meta["terminal_reason"] = reason
            return .terminal(goToTerminal(text: text, agent: agent, session: input.sessionID, cwd: input.cwd, link: link, meta: meta))
        }
    }

    /// The session side of a PermissionRequest: needs you, with the full command, and where to answer when the
    /// notch cannot (an allowlisted request carries its own Allow / Deny).
    public static func permissionReport(for input: HookInput, plan: PermissionPlan, agent: String, link: String?,
                                        now: Date) -> SessionReport {
        var detail = PermissionPrompt.title(tool: input.toolName ?? "tool", input: input.toolStrings)
        if case .terminal(let item) = plan {
            detail += "\n" + answerInTerminal + (item.meta?["terminal_reason"].map { ": \($0)" } ?? "")
        }
        return sessionReport(input, .waiting, agent: agent, link: link, now: now) { $0.detail = detail }
    }

    /// The notch request timed out: the terminal's own prompt is showing now.
    public static func terminalReport(after request: Item, input: HookInput, agent: String, link: String?, now: Date) -> SessionReport {
        sessionReport(input, .waiting, agent: agent, link: link, now: now) { $0.detail = request.title + "\n" + answerInTerminal }
    }

    /// After a notch request timed out (or was closed without an answer): the terminal prompt is showing now.
    public static func goToTerminal(after request: Item, agent: String, session: String) -> Item {
        goToTerminal(text: request.title, agent: agent, session: session, cwd: request.meta?["cwd"], link: request.link,
                     meta: request.meta ?? [:])
    }

    private static func goToTerminal(text: String, agent: String, session: String, cwd: String?, link: String?,
                                     meta: [String: String]) -> Item {
        Item(title: "\(projectName(cwd)) · \(text)", kind: .task, status: .waiting, source: agent, link: link, meta: meta,
             key: waitingKey(agent: agent, session: session))
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
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
