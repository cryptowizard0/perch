import Foundation
import PerchAppCore
import PerchCore
import PerchSetup
import Testing

/// What the notch shows about setup: the first-run card, the rows above the sessions, Codex's trust hint.
@Suite struct SetupPanelTests {
    static let home = "/Users/me"
    static let claude = "/Users/me/.claude/settings.json"
    static let codex = "/Users/me/.codex/hooks.json"
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func status(_ agent: String, _ state: AgentState, error: String? = nil) -> AgentStatus {
        AgentStatus(agent: agent, state: state, config: agent == "codex" ? Self.codex : Self.claude, error: error)
    }

    func report(_ statuses: [AgentStatus], records: AgentsFile = AgentsFile(), enabled: Bool = true,
                repaired: [String] = [], problems: [SetupProblem] = [], failures: [AgentFailure] = []) -> SetupReport {
        SetupReport(enabled: enabled, home: Self.home, statuses: statuses, records: records, repaired: repaired,
                    problems: problems, failures: failures)
    }

    func state(_ report: SetupReport, cardShownBefore: Bool = true) -> SetupState {
        var state = SetupState()
        state.apply(report, cardShownBefore: cardShownBefore)
        return state
    }

    func codexEvent(at: Date, type: SessionEventType = .updated, source: String = "codex") -> SessionEvent {
        var s = Session(id: "c1", source: source, startedAt: at)
        s.updatedAt = at
        return SessionEvent(type: type, session: s, at: at)
    }

    // MARK: First-run card

    @Test func theCardAppearsOnceOnAFreshRealInstallListingWhatWasFound() throws {
        let fresh = report([status("claude-code", .notAsked), status("codex", .notAsked)])
        var state = SetupState()
        let opens = state.apply(fresh, cardShownBefore: false)
        #expect(opens, "the notch opens on its own")
        let card = try #require(state.card)
        #expect(card.choices.map(\.agent) == ["claude-code", "codex"])
        #expect(card.choices.allSatisfy { $0.checked }, "checked by default")
        #expect(card.choices.map(\.title) == ["Claude Code", "Codex"])
        #expect(card.phase == .choosing && card.canConnect)
        // While the card is up, it is the setup UI: no "found · Connect" rows repeating it.
        #expect(state.rows.isEmpty)
        // A later report in the same launch does not bring a closed card back.
        state.closeCard()
        let reopens = state.apply(fresh, cardShownBefore: false)
        #expect(!reopens)
        #expect(state.card == nil)
        #expect(state.rows.map(\.text) == ["Claude Code found", "Codex found"])
    }

    @Test func theCardListsOnlyDetectedAgents() throws {
        let card = try #require(state(report([status("claude-code", .notDetected), status("codex", .notAsked)]),
                                      cardShownBefore: false).card)
        #expect(card.choices.map(\.agent) == ["codex"])
        // Nothing found: the card still says where Perch lives and that it is waiting for an agent.
        let empty = try #require(state(report([status("claude-code", .notDetected), status("codex", .notDetected)]),
                                       cardShownBefore: false).card)
        #expect(empty.choices.isEmpty && !empty.canConnect)
    }

    @Test func noCardOnceShownOrOnceAnythingWasChosen() {
        let fresh = [status("claude-code", .notAsked), status("codex", .notAsked)]
        #expect(state(report(fresh), cardShownBefore: true).card == nil)
        // install.sh / perch setup already ran, or an agent was turned off: not a first run.
        let chosen = AgentsFile(agents: ["codex": AgentRecord(status: .off)])
        #expect(state(report([status("claude-code", .notAsked), status("codex", .off)], records: chosen),
                      cardShownBefore: false).card == nil)
        #expect(state(report([status("claude-code", .connected), status("codex", .notAsked)]), cardShownBefore: false).card == nil)
    }

    @Test func aDeveloperBuildShowsNoSetupUI() {
        // `.build/Perch.app` or PERCH_HOME: the self-check reports the install is not this app's to maintain.
        let dev = state(report([status("claude-code", .notAsked), status("codex", .needsTrust)], enabled: false),
                        cardShownBefore: false)
        #expect(dev.card == nil)
        #expect(dev.rows.isEmpty)
        #expect(dev.menu.isEmpty)
    }

    @Test func uncheckingAnAgentLeavesItOut() throws {
        var state = state(report([status("claude-code", .notAsked), status("codex", .notAsked)]), cardShownBefore: false)
        state.toggleCardChoice("codex")
        #expect(state.card?.checkedAgents == ["claude-code"])
        state.toggleCardChoice("claude-code")
        #expect(state.card?.canConnect == false)
    }

    @Test func afterConnectTheCardShowsTheResultAndTheStepLeft() throws {
        var state = state(report([status("claude-code", .notAsked), status("codex", .notAsked)]), cardShownBefore: false)
        let connecting = state.startConnecting()
        let agents = try #require(connecting)
        #expect(agents == ["claude-code", "codex"])
        #expect(state.card?.phase == .connecting)
        let after = report([status("claude-code", .connected), status("codex", .needsTrust)])
        state.finishConnecting(agents, report: after)
        guard case .finished(let lines) = state.card?.phase else { Issue.record("not finished"); return }
        #expect(lines.map(\.text) == ["Connected Claude Code", "Connected Codex", "Trust Perch's hooks: run /hooks in codex"])
        #expect(lines.map(\.style) == [.done, .done, .next])
        #expect(state.rows.isEmpty, "the card says it; the trust row waits until the card is closed")
        state.closeCard()
        #expect(state.rows.map(\.kind) == [.trust])
    }

    @Test func trustArrivingWhileTheCardIsOpenDropsTheStep() throws {
        var state = state(report([status("codex", .notAsked)]), cardShownBefore: false)
        let connecting = state.startConnecting()
        let agents = try #require(connecting)
        state.finishConnecting(agents, report: report([status("codex", .needsTrust)],
                                                      records: AgentsFile(agents: ["codex": AgentRecord(status: .on, hooksWrittenAt: t0)])))
        state.markTrusted("codex", at: t0.addingTimeInterval(5))
        guard case .finished(let lines) = state.card?.phase else { Issue.record("not finished"); return }
        #expect(lines.map(\.text) == ["Connected Codex"])
        state.closeCard()
        #expect(state.rows.isEmpty)
    }

    @Test func theTrustRowShowsOnceTheCardIsClosed() throws {
        var state = state(report([status("codex", .notAsked)]), cardShownBefore: false)
        let connecting = state.startConnecting()
        let agents = try #require(connecting)
        state.finishConnecting(agents, report: report([status("codex", .needsTrust)]))
        state.closeCard()
        #expect(state.rows.map(\.kind) == [.trust])
    }

    @Test func aFailedConnectSaysWhy() throws {
        var state = state(report([status("claude-code", .notAsked), status("codex", .notAsked)]), cardShownBefore: false)
        state.toggleCardChoice("codex")
        let connecting = state.startConnecting()
        let agents = try #require(connecting)
        let broken = "/Users/me/.claude/settings.json is not valid JSON (or not an object); fix it first, nothing was changed"
        state.finishConnecting(agents, report: report([status("claude-code", .notAsked, error: broken), status("codex", .notAsked)],
                                                      failures: [AgentFailure(agent: "claude-code", config: Self.claude, message: broken)]))
        guard case .finished(let lines) = state.card?.phase else { Issue.record("not finished"); return }
        #expect(lines == [SetupCard.Line(text: "Couldn't connect Claude Code", detail: broken, style: .problem)])
    }

    // MARK: Rows

    @Test func whichRowEachAgentStateGets() {
        func rows(_ s: AgentStatus) -> [String] { state(report([s])).rows.map(\.text) }
        #expect(rows(status("codex", .notAsked)) == ["Codex found"])
        #expect(rows(status("codex", .needsTrust)) == ["Trust Perch's hooks: run /hooks in codex"])
        #expect(rows(status("codex", .connected)) == [])
        #expect(rows(status("codex", .notDetected)) == [])
        #expect(rows(status("codex", .off)) == [], "an agent the user turned off is never suggested")
        #expect(rows(status("claude-code", .notAsked)) == ["Claude Code found"])
        // Connected but Perch's hooks are gone (`perch uninstall` kept agents.json): the self-check doesn't put them
        // back on its own; the row offers to.
        #expect(rows(status("claude-code", .outdated)) == ["Perch's hooks for Claude Code are missing"])
    }

    @Test func onlyConnectRowsHaveAConnectButton() {
        let rows = state(report([status("claude-code", .outdated), status("codex", .notAsked)], repaired: ["claude-code"])).rows
        #expect(rows.map(\.kind) == [.connect, .updated])
        #expect(rows.map(\.connects) == ["codex", nil])
    }

    @Test func repairedHooksAreReported() {
        let rows = state(report([status("claude-code", .connected), status("codex", .needsTrust)], repaired: ["claude-code", "codex"])).rows
        #expect(rows.map(\.text) == ["Trust Perch's hooks: run /hooks in codex",
                                     "Updated Perch's hooks for Claude Code", "Updated Perch's hooks for Codex"])
    }

    @Test func aFileThatCantBeReadIsAnErrorRowNotAConnectRow() throws {
        let message = "\(Self.codex) is not valid JSON (or not an object); fix it first, nothing was changed"
        for state in [AgentState.notAsked, .outdated] {
            let row = try #require(self.state(report([status("codex", state, error: message)])).rows.first)
            #expect(row.kind == .problem)
            #expect(row.text == "Can't read ~/.codex/hooks.json")
            #expect(row.detail == message)
            #expect(row.connects == nil)
        }
        #expect(self.state(report([status("codex", .off, error: message)])).rows.isEmpty)
    }

    @Test func otherProblemsAreErrorRowsToo() {
        let problem = SetupProblem(agent: "codex", title: "Can't update ~/.codex/hooks.json", detail: "permission denied")
        let rows = state(report([status("codex", .outdated)], problems: [problem])).rows
        // The failed repair says so; it doesn't also offer to connect.
        #expect(rows.map(\.text) == ["Can't update ~/.codex/hooks.json"])
        #expect(rows.first?.detail == "permission denied")
    }

    @Test func aProblemGoesWhenTheNextReportNoLongerHasItUnlessTheSelfCheckFoundIt() {
        let agentsJSON = SetupProblem(agent: nil, title: "Can't read ~/.perch/agents.json", detail: "not valid")
        let perchd = SetupProblem(agent: nil, title: "Can't start perchd", detail: "bootstrap failed", lasting: true)
        var state = state(report([status("codex", .connected)], problems: [agentsJSON, perchd]))
        #expect(state.rows.map(\.text) == ["Can't read ~/.perch/agents.json", "Can't start perchd"])
        // The user fixed agents.json; nothing retries starting perchd before the next launch.
        state.apply(report([status("codex", .connected)]), cardShownBefore: true)
        #expect(state.rows.map(\.text) == ["Can't start perchd"])
    }

    @Test func unreadableChoicesAreNeverAFirstRun() {
        var broken = report([status("claude-code", .notAsked), status("codex", .notAsked)])
        broken.choicesUnknown = true
        #expect(state(broken, cardShownBefore: false).card == nil, "agents.json may say codex is off")
    }

    @Test func rowsAreOrderedProblemsTrustConnectUpdated() {
        let problem = SetupProblem(agent: nil, title: "Can't start perchd", detail: "launchctl bootstrap failed")
        let rows = state(report([status("claude-code", .notAsked), status("codex", .needsTrust)],
                                repaired: ["codex"], problems: [problem])).rows
        #expect(rows.map(\.kind) == [.problem, .trust, .connect, .updated])
    }

    @Test func setupRowsSitAboveTheSessionGroups() {
        var running = Session(id: "s1", source: "claude-code", startedAt: t0)
        running.status = .running
        let setup = state(report([status("codex", .needsTrust)]))
        let panel = Panel(sessions: [running], setup: setup)
        #expect(panel.sections.count == 2)
        guard case .setup(let rows) = panel.sections.first, case .group(let group) = panel.sections.last else {
            Issue.record("setup first, then the groups"); return
        }
        #expect(rows.map(\.kind) == [.trust])
        #expect(group.status == .running)
        // The card goes first too.
        let first = Panel(sessions: [running], setup: state(report([status("codex", .notAsked)]), cardShownBefore: false))
        guard case .card = first.sections.first else { Issue.record("card first"); return }
        // No setup: only the groups, as before.
        #expect(Panel(sessions: [running]).sections == [.group(Panel(sessions: [running]).groups[0])])
        // Setup rows make the expanded notch taller.
        #expect(PanelLayout.listHeight(panel) > PanelLayout.listHeight(Panel(sessions: [running])))
    }

    @Test func dismissingARowHidesItForThisLaunch() throws {
        let r = report([status("claude-code", .notAsked), status("codex", .needsTrust)])
        var state = state(r)
        let trust = try #require(state.rows.first { $0.kind == .trust })
        state.dismiss(trust.id)
        #expect(state.rows.map(\.kind) == [.connect])
        state.apply(r, cardShownBefore: true)
        #expect(state.rows.map(\.kind) == [.connect], "still hidden after the next refresh")
        // The next launch starts with a fresh state: the row is back.
        #expect(self.state(r).rows.map(\.kind) == [.trust, .connect])
    }

    // MARK: Agents menu

    @Test func theAgentsMenuChecksConnectedAgents() {
        let menu = state(report([status("claude-code", .connected), status("codex", .off)])).menu
        #expect(menu.map(\.agent) == ["claude-code", "codex"])
        #expect(menu.map(\.title) == ["Claude Code", "Codex"])
        #expect(menu.map(\.on) == [true, false])
        #expect(menu.allSatisfy { $0.available })
        for on in [AgentState.outdated, .needsTrust, .connected] {
            #expect(state(report([status("codex", on)])).menu.first?.on == true)
        }
        // Not set up on this Mac: nothing to connect.
        let missing = state(report([status("codex", .notDetected)])).menu.first
        #expect(missing?.on == false && missing?.available == false)
    }

    // MARK: Codex trust

    @Test func aCodexUpdateAfterTheHooksWereWrittenProvesTrust() {
        let records = AgentsFile(agents: ["codex": AgentRecord(status: .on, config: Self.codex, hooksWrittenAt: t0)])
        var state = state(report([status("codex", .needsTrust)], records: records))
        #expect(state.provesTrust(codexEvent(at: t0.addingTimeInterval(-1))) == nil, "ran the old hooks")
        #expect(state.provesTrust(codexEvent(at: t0)) == nil)
        #expect(state.provesTrust(codexEvent(at: t0.addingTimeInterval(5), source: "claude-code")) == nil)
        #expect(state.provesTrust(codexEvent(at: t0.addingTimeInterval(5), type: .ended)) == nil)
        let later = codexEvent(at: t0.addingTimeInterval(5))
        #expect(state.provesTrust(later) == "codex")

        state.markTrusted("codex", at: later.session.updatedAt)
        #expect(state.rows.isEmpty, "the trust row goes away")
        #expect(state.records["codex"]?.trustedAt == t0.addingTimeInterval(5))
        #expect(state.provesTrust(codexEvent(at: t0.addingTimeInterval(9))) == nil, "already trusted")
    }

    @Test func withoutAWriteTimeAnyCodexUpdateProvesTrust() {
        // Hooks from before agents.json existed (v0.3): any event shows Codex runs them.
        let records = AgentsFile(agents: ["codex": AgentRecord(status: .on, config: Self.codex)])
        let state = state(report([status("codex", .needsTrust)], records: records))
        #expect(state.provesTrust(codexEvent(at: t0)) == "codex")
        #expect(self.state(report([status("codex", .needsTrust)], enabled: false)).provesTrust(codexEvent(at: t0)) == nil)
    }
}
