import Foundation
import PerchCore
import PerchSetup

/// What the self-check, Connect, disconnect or a trust update found (`AppSetup` produces it, off the main thread).
public struct SetupReport: Equatable, Sendable {
    /// This app maintains the install (inside /Applications or ~/Applications, no PERCH_HOME). False: no setup UI.
    public var enabled: Bool
    /// The user's home, to write paths as `~/…`.
    public var home: String
    public var statuses: [AgentStatus]
    public var records: AgentsFile
    /// Agents whose outdated Perch hooks were rewritten.
    public var repaired: [String]
    /// What went wrong besides a hook file Perch can't read (that one is in `statuses`).
    public var problems: [SetupProblem]
    /// Agents a Connect could not connect, and why.
    public var failures: [AgentFailure]
    /// agents.json could not be read: the user's choices are unknown, so this is never a first run.
    public var choicesUnknown: Bool

    public init(enabled: Bool, home: String, statuses: [AgentStatus] = [], records: AgentsFile = AgentsFile(),
                repaired: [String] = [], problems: [SetupProblem] = [], failures: [AgentFailure] = [],
                choicesUnknown: Bool = false) {
        self.choicesUnknown = choicesUnknown
        self.enabled = enabled
        self.home = home
        self.statuses = statuses
        self.records = records
        self.repaired = repaired
        self.problems = problems
        self.failures = failures
    }
}

/// Something setup could not do, as an error row: a short title, the full message under it.
public struct SetupProblem: Equatable, Sendable {
    public var agent: String?
    public var title: String
    public var detail: String
    /// Found by the launch self-check (installing the binaries, starting perchd, a repair), which nothing retries
    /// before the next launch: the row stays until then or until dismissed. Other problems last until the next report.
    public var lasting: Bool

    public init(agent: String?, title: String, detail: String, lasting: Bool = false) {
        self.agent = agent
        self.title = title
        self.detail = detail
        self.lasting = lasting
    }
}

/// One row above the session groups.
public struct SetupRow: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// A file Perch can't read or write, perchd that won't start, …
        case problem
        /// Codex runs Perch's hooks only after `/hooks`.
        case trust
        /// Found and never asked (or its hooks are gone): a Connect button.
        case connect
        /// The self-check rewrote outdated hooks.
        case updated
    }

    public let id: String
    public let kind: Kind
    public let text: String
    public let detail: String?
    /// The agent the row's Connect button connects; nil: no button.
    public let connects: String?
}

/// The first-run card: the agents found, each checked; Connect / Not now; then what happened and the step left.
public struct SetupCard: Equatable, Sendable {
    public struct Choice: Equatable, Sendable {
        public let agent: String
        public let config: String
        public var checked: Bool
        public var title: String { AgentNames.display(agent) }
    }

    public struct Line: Equatable, Sendable {
        public enum Style: Equatable, Sendable { case done, next, problem }
        public let text: String
        public let detail: String?
        public let style: Style

        public init(text: String, detail: String? = nil, style: Style) {
            self.text = text
            self.detail = detail
            self.style = style
        }
    }

    public enum Phase: Equatable, Sendable {
        case choosing
        case connecting
        case finished([Line])
    }

    public var choices: [Choice]
    public var phase: Phase = .choosing

    public var checkedAgents: [String] { choices.filter(\.checked).map(\.agent) }
    public var canConnect: Bool { phase == .choosing && !checkedAgents.isEmpty }

    /// A first run: nobody chose anything yet (no agents.json entry, nothing connected) and the card was never shown.
    static func firstRun(_ report: SetupReport, shownBefore: Bool) -> SetupCard? {
        guard report.enabled, !shownBefore, !report.choicesUnknown, report.records.agents.isEmpty,
              report.statuses.allSatisfy({ $0.state == .notAsked || $0.state == .notDetected }) else { return nil }
        return SetupCard(choices: report.statuses.filter { $0.state == .notAsked }
            .map { Choice(agent: $0.agent, config: $0.config, checked: true) })
    }

    static func outcome(of agents: [String], _ report: SetupReport) -> [Line] {
        var lines: [Line] = []
        var next: [Line] = []
        for agent in agents {
            let name = AgentNames.display(agent)
            if let failure = report.failures.first(where: { $0.agent == agent }) {
                lines.append(Line(text: "Couldn't connect \(name)", detail: failure.message, style: .problem))
                continue
            }
            lines.append(Line(text: "Connected \(name)", style: .done))
            if report.statuses.first(where: { $0.agent == agent })?.state == .needsTrust {
                next.append(Line(text: SetupState.trustText(agent), style: .next))
            }
        }
        return lines + next
    }
}

/// One entry of the right-click Agents submenu.
public struct AgentToggle: Equatable, Sendable {
    public let agent: String
    public var title: String { AgentNames.display(agent) }
    /// Connected (checkmark).
    public let on: Bool
    /// Set up on this Mac, or already on: something to toggle.
    public let available: Bool
}

/// Everything setup shows in the notch for this launch. Pure: `SetupModel` feeds it reports and user actions.
public struct SetupState: Equatable, Sendable {
    public private(set) var enabled = false
    public private(set) var home = ""
    public private(set) var statuses: [AgentStatus] = []
    public private(set) var records = AgentsFile()
    public private(set) var repaired: [String] = []
    public private(set) var problems: [SetupProblem] = []
    /// Row ids dismissed with right-click; only for this launch (never saved).
    public private(set) var dismissed: Set<String> = []
    public private(set) var card: SetupCard?
    private var cardDecided = false

    public init() {}

    /// Takes in a report. The first report of a launch decides the first-run card; returns true when it appears
    /// (the notch opens on its own).
    @discardableResult
    public mutating func apply(_ report: SetupReport, cardShownBefore: Bool) -> Bool {
        enabled = report.enabled
        home = report.home
        statuses = report.statuses
        records = report.records
        for agent in report.repaired where !repaired.contains(agent) { repaired.append(agent) }
        // A problem the report no longer has is fixed; the self-check's own last for the launch.
        problems = problems.filter(\.lasting)
        for problem in report.problems where !problems.contains(problem) { problems.append(problem) }
        guard !cardDecided else { return false }
        cardDecided = true
        card = SetupCard.firstRun(report, shownBefore: cardShownBefore)
        return card != nil
    }

    // MARK: Card

    public mutating func toggleCardChoice(_ agent: String) {
        guard var card, card.phase == .choosing, let i = card.choices.firstIndex(where: { $0.agent == agent }) else { return }
        card.choices[i].checked.toggle()
        self.card = card
    }

    /// Connect: the agents to connect, or nil when there is nothing to do.
    public mutating func startConnecting() -> [String]? {
        guard let card, card.canConnect else { return nil }
        self.card?.phase = .connecting
        return card.checkedAgents
    }

    public mutating func finishConnecting(_ agents: [String], report: SetupReport) {
        apply(report, cardShownBefore: true)
        card?.phase = .finished(SetupCard.outcome(of: agents, report))
    }

    /// Not now, or Done after Connect.
    public mutating func closeCard() {
        card = nil
    }

    // MARK: Rows

    /// Problems, then trust, then connect, then what was updated; none while the card is up or in a developer build.
    public var rows: [SetupRow] {
        guard enabled, card == nil else { return [] }
        var problemRows: [SetupRow] = []
        var trust: [SetupRow] = []
        var connect: [SetupRow] = []
        for problem in problems {
            problemRows.append(SetupRow(id: "problem:\(problem.title)", kind: .problem, text: problem.title,
                                        detail: problem.detail, connects: nil))
        }
        for status in statuses where status.state != .off && status.state != .notDetected {
            let agent = status.agent
            let name = AgentNames.display(agent)
            if let error = status.error {
                problemRows.append(SetupRow(id: "unreadable:\(agent)", kind: .problem, text: "Can't read \(tilde(status.config))",
                                            detail: error, connects: nil))
                continue
            }
            switch status.state {
            case .notAsked:
                connect.append(SetupRow(id: "connect:\(agent)", kind: .connect, text: "\(name) found", detail: nil, connects: agent))
            case .needsTrust:
                trust.append(SetupRow(id: "trust:\(agent)", kind: .trust, text: Self.trustText(agent), detail: nil, connects: nil))
            case .outdated where !repaired.contains(agent) && !problems.contains(where: { $0.agent == agent }):
                // The self-check repairs outdated hooks; it left these alone because Perch's hooks are gone.
                connect.append(SetupRow(id: "missing:\(agent)", kind: .connect, text: "Perch's hooks for \(name) are missing",
                                        detail: nil, connects: agent))
            default:
                break
            }
        }
        let updated = repaired.map { agent in
            SetupRow(id: "updated:\(agent)", kind: .updated, text: "Updated Perch's hooks for \(AgentNames.display(agent))",
                     detail: nil, connects: nil)
        }
        return (problemRows + trust + connect + updated).filter { !dismissed.contains($0.id) }
    }

    public mutating func dismiss(_ id: String) {
        dismissed.insert(id)
    }

    static func trustText(_ agent: String) -> String {
        "Trust Perch's hooks: run /hooks in \(agent)"
    }

    /// A path under the user's home written as `~/…`.
    public func tilde(_ path: String) -> String {
        Self.tilde(path, home: home)
    }

    static func tilde(_ path: String, home: String) -> String {
        guard !home.isEmpty, path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    // MARK: Agents menu

    public var menu: [AgentToggle] {
        guard enabled else { return [] }
        return statuses.map { status in
            let on = [.connected, .outdated, .needsTrust].contains(status.state)
            return AgentToggle(agent: status.agent, on: on, available: on || status.state != .notDetected)
        }
    }

    // MARK: Trust

    /// The agent this event proves trusted: it waits for trust, and the event reports a turn after Perch last
    /// wrote its hooks (so the agent ran the new hooks). `updated_at` is the report's time; perchd's own changes
    /// (done → idle, seen) keep it.
    public func provesTrust(_ event: SessionEvent) -> String? {
        guard enabled, event.type == .updated,
              let status = statuses.first(where: { $0.agent == event.session.source }), status.state == .needsTrust else { return nil }
        if let written = records[status.agent]?.hooksWrittenAt, event.session.updatedAt <= written { return nil }
        return status.agent
    }

    /// Records trust at once, so the row goes before agents.json is rewritten.
    public mutating func markTrusted(_ agent: String, at time: Date) {
        records.markTrusted(agent, at: time)
        if case .finished(let lines) = card?.phase {
            card?.phase = .finished(lines.filter { $0.text != Self.trustText(agent) })
        }
        statuses = statuses.map { status in
            status.agent == agent && status.state == .needsTrust
                ? AgentStatus(agent: agent, state: .connected, config: status.config, error: status.error) : status
        }
    }
}

public enum AgentNames {
    /// How the notch writes an agent's name.
    public static func display(_ agent: String) -> String {
        switch agent {
        case "claude-code": return "Claude Code"
        case "codex": return "Codex"
        case "hermes": return "Hermes"
        default: return agent
        }
    }
}
