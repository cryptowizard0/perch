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
    /// PermissionRequest / PostToolUse.
    public var toolName: String?
    public var toolInput: [String: JSONValue]?
    /// Hermes: the event's keyword arguments.
    public var extra: Extra?

    /// The Hermes `extra` fields Perch reads (the rest, like the whole conversation history, is skipped).
    public struct Extra: Decodable, Equatable, Sendable {
        public var assistantResponse: String?
        public var platform: String?
        /// pre_approval_request / post_approval_response.
        public var command: String?
        public var description: String?
        public var sessionKey: String?
        public var surface: String?

        enum CodingKeys: String, CodingKey {
            case platform, command, description, surface
            case assistantResponse = "assistant_response"
            case sessionKey = "session_key"
        }

        public init(assistantResponse: String? = nil, platform: String? = nil, command: String? = nil,
                    description: String? = nil, sessionKey: String? = nil, surface: String? = nil) {
            self.assistantResponse = assistantResponse
            self.platform = platform
            self.command = command
            self.description = description
            self.sessionKey = sessionKey
            self.surface = surface
        }
    }

    enum CodingKeys: String, CodingKey {
        case cwd, message, extra
        case sessionID = "session_id"
        case event = "hook_event_name"
        case notificationType = "notification_type"
        case lastAssistantMessage = "last_assistant_message"
        case toolName = "tool_name"
        case toolInput = "tool_input"
    }

    public init(sessionID: String, event: String, cwd: String? = nil, notificationType: String? = nil,
                message: String? = nil, lastAssistantMessage: String? = nil, toolName: String? = nil,
                toolInput: [String: JSONValue]? = nil, extra: Extra? = nil) {
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
/// | event | requests |
/// | --- | --- |
/// | UserPromptSubmit | session_start; resolve this session's waiting item and last "finished" notice (you are back) |
/// | Notification (needs you) | add waiting, key `<agent>:<session>` |
/// | Stop | session_end; resolve the waiting item; add a notice with the last message, key `<agent>:<session>:done` |
/// | StopFailure / SessionEnd / Interrupt | session_end; resolve the waiting item |
/// | PostToolUse / PostToolUseFailure | resolve the waiting item (a tool ran, so the permission prompt is answered) |
/// | PermissionRequest | see `permission(for:…)`: blocking, handled by `perch hook` itself |
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
/// | pre_approval_request | add waiting with the full command, key `hermes:<session_key>`: answer where Hermes asks |
/// | post_approval_response (answered or timed out) | resolve it |
///
/// Hermes approval hooks only observe, so the notch can never answer them. They carry the gateway's
/// `session_key` (`default` in the CLI, `agent:main:<platform>:…` in the gateway), not the session id.
public enum HookAdapter {
    /// Notification types that mean "an agent is blocked on the human". `idle_prompt` is left out on purpose:
    /// Stop already posts a notice, and every finished turn turning orange would dilute the signal.
    public static let waitingNotifications: Set<String> = ["permission_prompt", "elicitation_dialog", "agent_needs_input"]
    /// The Stop notice fades after this long.
    public static let noticeLifetime: TimeInterval = 10 * 60
    static let summaryLength = 140

    public static func waitingKey(agent: String, session: String) -> String { "\(agent):\(session)" }
    /// Events that start a turn: the human just typed, so that terminal has focus.
    public static let turnStarts: Set<String> = ["UserPromptSubmit", "pre_llm_call"]
    public static func noticeKey(agent: String, session: String) -> String { "\(agent):\(session):done" }

    /// `alreadyWaiting`: this session already has an active waiting item. A late `permission_prompt` notification
    /// then leaves it alone, so the full command text from PermissionRequest is not replaced by a generic message.
    public static func requests(for input: HookInput, agent: String, link: String?, now: Date,
                                alreadyWaiting: Bool = false) -> [Request] {
        let session = input.sessionID
        let waiting = waitingKey(agent: agent, session: session)
        let project = projectName(input.cwd)
        var meta = ["session_id": session]
        if let cwd = input.cwd { meta["cwd"] = cwd }

        switch input.event {
        case "UserPromptSubmit":
            return [
                Request(op: .sessionStart, session: Session(id: session, source: agent, title: project, link: link, startedAt: now)),
                Request(op: .done, key: waiting),
                Request(op: .done, key: noticeKey(agent: agent, session: session)),
            ]
        case "Notification":
            guard let type = input.notificationType, waitingNotifications.contains(type) else { return [] }
            if alreadyWaiting && type == "permission_prompt" { return [] }
            meta["notification_type"] = type
            let message = oneLine(input.message ?? "") ?? "needs you"
            return [Request(op: .add, item: Item(
                title: "\(project) · \(message)", kind: .task, status: .waiting, source: agent,
                link: link, meta: meta, key: waiting
            ))]
        case "Stop":
            return [
                Request(op: .sessionEnd, id: session, at: now),
                Request(op: .done, key: waiting),
                Request(op: .add, item: Item(
                    title: "\(project) · \(summary(input.lastAssistantMessage))", kind: .notice, source: agent,
                    link: link, meta: meta, key: noticeKey(agent: agent, session: session),
                    expiresAt: now.addingTimeInterval(noticeLifetime)
                )),
            ]
        case "StopFailure", "SessionEnd", "Interrupt":
            return [Request(op: .sessionEnd, id: session, at: now), Request(op: .done, key: waiting)]
        case "PostToolUse", "PostToolUseFailure":
            return [Request(op: .done, key: waiting)]

        // Hermes
        case "pre_llm_call":
            return [
                Request(op: .sessionStart, session: Session(id: session, source: agent, title: hermesPlace(input), link: link, startedAt: now)),
                Request(op: .done, key: noticeKey(agent: agent, session: session)),
            ]
        case "post_llm_call":
            return [Request(op: .add, item: Item(
                title: "\(hermesPlace(input)) · \(summary(input.extra?.assistantResponse))", kind: .notice, source: agent,
                link: link, meta: meta, key: noticeKey(agent: agent, session: session),
                expiresAt: now.addingTimeInterval(noticeLifetime)
            ))]
        case "on_session_end":
            return [Request(op: .sessionEnd, id: session, at: now)]
        case "pre_approval_request":
            let extra = input.extra ?? .init()
            let sessionKey = extra.sessionKey ?? "default"
            var approval = ["tool": "terminal", "session_key": sessionKey]
            if let cwd = input.cwd { approval["cwd"] = cwd }
            if let reason = extra.description, !reason.isEmpty { approval["terminal_reason"] = reason }
            if let platform = gatewayPlatform(extra) { approval["answer_in"] = platform.prefix(1).uppercased() + platform.dropFirst() }
            return [Request(op: .add, item: Item(
                title: "\(hermesPlace(input)) · \(extra.command ?? "a command")", kind: .task, status: .waiting, source: agent,
                link: link, meta: approval, key: waitingKey(agent: agent, session: sessionKey)
            ))]
        case "post_approval_response":
            return [Request(op: .done, key: waitingKey(agent: agent, session: input.extra?.sessionKey ?? "default"))]

        default:
            return []
        }
    }

    /// Where a Hermes turn happens: the chat platform for the gateway, else the project directory.
    static func hermesPlace(_ input: HookInput) -> String {
        if let platform = input.extra.flatMap(gatewayPlatform) { return platform }
        if let platform = input.extra?.platform, !platform.isEmpty, platform != "cli" { return platform }
        return projectName(input.cwd)
    }

    /// `agent:<profile>:<platform>:…` → platform, for approvals asked through the gateway.
    private static func gatewayPlatform(_ extra: HookInput.Extra) -> String? {
        guard extra.surface == "gateway", let key = extra.sessionKey else { return nil }
        let parts = key.split(separator: ":")
        guard parts.count > 2, parts[0] == "agent" else { return nil }
        return String(parts[2])
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
