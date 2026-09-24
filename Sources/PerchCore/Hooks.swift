import Foundation

/// What Claude Code (and Codex, same shape) sends a command hook on stdin. Only the fields Perch uses.
public struct HookInput: Decodable, Equatable, Sendable {
    public var sessionID: String
    public var event: String
    public var cwd: String?
    public var notificationType: String?
    public var message: String?
    public var lastAssistantMessage: String?

    enum CodingKeys: String, CodingKey {
        case cwd, message
        case sessionID = "session_id"
        case event = "hook_event_name"
        case notificationType = "notification_type"
        case lastAssistantMessage = "last_assistant_message"
    }

    public init(sessionID: String, event: String, cwd: String? = nil, notificationType: String? = nil,
                message: String? = nil, lastAssistantMessage: String? = nil) {
        self.sessionID = sessionID
        self.event = event
        self.cwd = cwd
        self.notificationType = notificationType
        self.message = message
        self.lastAssistantMessage = lastAssistantMessage
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
public enum HookAdapter {
    /// Notification types that mean "an agent is blocked on the human". `idle_prompt` is left out on purpose:
    /// Stop already posts a notice, and every finished turn turning orange would dilute the signal.
    public static let waitingNotifications: Set<String> = ["permission_prompt", "elicitation_dialog", "agent_needs_input"]
    /// The Stop notice fades after this long.
    public static let noticeLifetime: TimeInterval = 10 * 60
    static let summaryLength = 140

    public static func waitingKey(agent: String, session: String) -> String { "\(agent):\(session)" }
    public static func noticeKey(agent: String, session: String) -> String { "\(agent):\(session):done" }

    public static func requests(for input: HookInput, agent: String, link: String?, now: Date) -> [Request] {
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
        default:
            return []
        }
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
