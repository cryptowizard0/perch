import Foundation

/// What Claude Code (and Codex, same shape) sends a command hook on stdin. Only the fields Perch uses.
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

    enum CodingKeys: String, CodingKey {
        case cwd, message
        case sessionID = "session_id"
        case event = "hook_event_name"
        case notificationType = "notification_type"
        case lastAssistantMessage = "last_assistant_message"
        case toolName = "tool_name"
        case toolInput = "tool_input"
    }

    public init(sessionID: String, event: String, cwd: String? = nil, notificationType: String? = nil,
                message: String? = nil, lastAssistantMessage: String? = nil, toolName: String? = nil,
                toolInput: [String: JSONValue]? = nil) {
        self.sessionID = sessionID
        self.event = event
        self.cwd = cwd
        self.notificationType = notificationType
        self.message = message
        self.lastAssistantMessage = lastAssistantMessage
        self.toolName = toolName
        self.toolInput = toolInput
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
/// | StopFailure / SessionEnd | session_end; resolve the waiting item |
/// | PostToolUse / PostToolUseFailure | resolve the waiting item (a tool ran, so the permission prompt is answered) |
/// | PermissionRequest | see `permission(for:…)`: blocking, handled by `perch hook` itself |
public enum HookAdapter {
    /// Notification types that mean "an agent is blocked on the human". `idle_prompt` is left out on purpose:
    /// Stop already posts a notice, and every finished turn turning orange would dilute the signal.
    public static let waitingNotifications: Set<String> = ["permission_prompt", "elicitation_dialog", "agent_needs_input"]
    /// The Stop notice fades after this long.
    public static let noticeLifetime: TimeInterval = 10 * 60
    static let summaryLength = 140

    public static func waitingKey(agent: String, session: String) -> String { "\(agent):\(session)" }
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
        case "StopFailure", "SessionEnd":
            return [Request(op: .sessionEnd, id: session, at: now), Request(op: .done, key: waiting)]
        case "PostToolUse", "PostToolUseFailure":
            return [Request(op: .done, key: waiting)]
        default:
            return []
        }
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
