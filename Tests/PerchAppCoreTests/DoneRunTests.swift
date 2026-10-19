import Foundation
import PerchAppCore
import PerchCore
import Testing

/// The Done banner run's path (#64).
@Suite struct DoneRunTests {
    /// A 14" MacBook Pro's notch, a 37 pt left wing (mascot and a running digit), a 200 pt banner.
    let band = DoneRun.Band(leftWing: 37, notchWidth: 185)
    let pill = DoneRun.Band(leftWing: 37, notchWidth: 0)
    let t0 = 1000.0
    let wing = 200.0

    func run(_ duration: TimeInterval, band: DoneRun.Band? = nil) -> DoneRun {
        DoneRun(start: t0, band: band ?? self.band, bannerWing: wing, bannerDuration: duration)
    }

    /// From the left wing to the banner's end and back: 7 → 418 (222 + 200 − 4).
    var trip: Double { (418.0 - DoneRun.home) / DoneRun.speed }

    func samples(_ run: DoneRun) -> [(TimeInterval, DoneRun.Position)] {
        stride(from: t0, to: run.end, by: 0.01).compactMap { t in run.position(at: t).map { (t, $0) } }
    }

    @Test(arguments: [4.0, 12.0])
    func theWholeRun(_ duration: TimeInterval) throws {
        let run = run(duration)
        let hop = DoneRun.hopDuration
        // 1. The hop, in place.
        #expect(run.position(at: t0)?.move == .hop && run.position(at: t0 + hop - 0.01)?.x == DoneRun.home)
        #expect(run.position(at: t0 - 0.01) == nil)
        // 2–3. Out, right, through the notch, onto the right wing.
        let out = try #require(run.position(at: t0 + hop + 0.5))
        #expect(out.move == .run && out.facingRight && abs(out.x - (DoneRun.home + 0.5 * DoneRun.speed)) < 1e-9)
        // 4. On the banner's far end for the banner's time, fully open.
        let opened = t0 + hop + trip
        #expect(abs(try #require(run.opened) - opened) < 1e-9)
        let standing = try #require(run.position(at: opened + duration / 2))
        #expect(standing.move == .stand && standing.x == 418 && standing.reveal == nil && !standing.hidden)
        // 5. Back the same way, rolling the banner up, then home.
        let back = try #require(run.position(at: opened + duration + 0.5))
        #expect(back.move == .run && !back.facingRight && abs(back.x - (418 - 0.5 * DoneRun.speed)) < 1e-9)
        #expect(abs(run.end - (opened + duration + trip)) < 1e-9)
        #expect(run.position(at: run.end) == nil)
        // The banner can go once it's rolled up, as the mascot reaches the notch.
        #expect(abs(try #require(run.bannerEnd) - (opened + duration + (418 - 222) / DoneRun.speed)) < 1e-9)
    }

    @Test func hiddenExactlyWhileOverTheNotch() {
        let positions = samples(run(4))
        for (t, p) in positions {
            #expect(p.hidden == (p.x >= 37 && p.x + 15 <= 222), "\(t)")
        }
        // Both ways.
        let hidden = positions.filter { $0.1.hidden }
        #expect(hidden.contains { $0.1.facingRight } && hidden.contains { !$0.1.facingRight })
        #expect(positions.contains { !$0.1.hidden && $0.1.x > 222 })
    }

    /// The banner shows from the right wing's inner edge to the mascot: pulled open going out, rolled up coming back.
    @Test func theBannerFollowsTheMascot() {
        for (t, p) in samples(run(4)) {
            switch p.move {
            case .stand: #expect(p.reveal == nil, "\(t)")
            case .hop, .run: #expect(p.reveal == min(max(p.x - 222, 0), wing), "\(t)")
            case .dash: Issue.record("no dash")
            }
        }
        let run = run(4)
        let opened = run.opened!
        #expect(run.position(at: opened - 0.2)!.reveal! < run.position(at: opened - 0.1)!.reveal!)
        #expect(run.position(at: opened + 4.2)!.reveal! > run.position(at: opened + 4.3)!.reveal!)
        #expect(run.position(at: t0)!.reveal == 0)
    }

    /// The menu bar pill has no notch: nothing hides it; the banner starts at the pill's middle.
    @Test func thePillHidesNothing() {
        let run = run(4, band: pill)
        #expect(samples(run).allSatisfy { !$0.1.hidden })
        #expect(run.position(at: run.opened! + 1)!.x == 37 + wing - 4)
    }

    /// Needs you or Failed: straight home in 0.3 s, wherever it was, and the banner is no longer its.
    @Test func somethingUrgentSendsItDashingHome() throws {
        for at in [0.3, 1.5, 3.5, 7.5] {
            var run = run(4)
            let t = t0 + at
            let x = try #require(run.position(at: t)).x
            run.dashHome(at: t)
            #expect(run.interrupted && run.bannerEnd == nil)
            if abs(x - DoneRun.home) < 1 {
                #expect(run.position(at: t) == nil, "\(at)")
                continue
            }
            let mid = try #require(run.position(at: t + 0.15))
            #expect(mid.move == .dash && mid.reveal == nil && abs(mid.x - (x + DoneRun.home) / 2) < 1e-9, "\(at)")
            #expect(abs(run.end - (t + DoneRun.dashDuration)) < 1e-9 && run.position(at: t + DoneRun.dashDuration) == nil, "\(at)")
            #expect(run.position(at: t - 0.01)?.x == self.run(4).position(at: t - 0.01)?.x, "\(at)")
        }
    }

    /// Another Done while it stands there: it hops in place, and the new banner gets its full time.
    @Test func anotherDoneHopsInPlaceAndRestartsTheTimer() throws {
        var run = run(4)
        let t = run.opened! + 2
        run.anotherDone(at: t, bannerWing: 150, bannerDuration: 6)
        let hop = try #require(run.position(at: t + 0.1))
        #expect(hop.move == .hop && hop.x == 418)
        // Then over to the new, shorter banner's end and its 6 s.
        let opened = try #require(run.opened)
        #expect(abs(opened - (t + DoneRun.hopDuration + 50 / DoneRun.speed)) < 1e-9)
        #expect(run.position(at: opened + 5.9)?.move == .stand && run.position(at: opened + 5.9)?.x == 368)
        #expect(run.position(at: opened + 6.1)?.move == .run)
        #expect(abs(run.end - (opened + 6 + (368 - DoneRun.home) / DoneRun.speed)) < 1e-9)
    }

    /// Another Done while it's still running out, or already heading back: it (re)heads for the new banner's end.
    @Test func anotherDoneOnTheWayCarriesOn() throws {
        var out = run(4)
        let t = t0 + DoneRun.hopDuration + 0.5
        let x = try #require(out.position(at: t)).x
        out.anotherDone(at: t, bannerWing: wing, bannerDuration: 12)
        #expect(out.position(at: t + 0.1)?.move == .run && out.position(at: t + 0.1)!.x > x)
        #expect(abs(out.opened! - (t0 + DoneRun.hopDuration + trip)) < 1e-9)
        #expect(out.position(at: out.opened! + 11.9)?.move == .stand)

        var back = run(4)
        let turning = back.opened! + 4.5
        back.anotherDone(at: turning, bannerWing: wing, bannerDuration: 4)
        #expect(back.position(at: turning + 0.1)!.facingRight)
        #expect(abs(back.opened! - (turning + 0.5)) < 1e-9)

        // During the first hop: it finishes the hop, then runs as before.
        var hopping = run(4)
        hopping.anotherDone(at: t0 + 0.2, bannerWing: wing, bannerDuration: 4)
        #expect(hopping == self.run(4))
    }

    /// The banner went early: home at a run.
    @Test func theBannerGoingEarlySendsItBack() throws {
        var run = run(12)
        let t = run.opened! + 1
        run.returnNow(at: t)
        let p = try #require(run.position(at: t + 0.1))
        #expect(p.move == .run && !p.facingRight)
        #expect(abs(run.end - (t + trip)) < 1e-9)
    }
}

extension DoneRunTests {
    func session(_ id: String, _ status: SessionStatus) -> Session {
        var s = Session(id: id, source: "claude-code", title: id)
        s.status = status
        s.lastMessage = "Pushed"
        return s
    }

    /// It flies only when Done is the signal: nothing waiting or failed elsewhere (running is fine; the count stays).
    @Test func itFliesOnlyWhenNothingIsMoreUrgentThanDone() {
        let done = Banner(id: 1, session: session("d", .done))
        let table: [([SessionStatus], Bool)] = [
            ([], true), ([.done], true), ([.idle], true), ([.running, .running], true),
            ([.waiting], false), ([.failed], false), ([.running, .failed], false), ([.idle, .waiting], false),
        ]
        for (others, flies) in table {
            let panel = Panel(sessions: [session("d", .done)] + others.enumerated().map { session("s\($0.offset)", $0.element) })
            #expect(DoneRun.flies(done, panel: panel, reduceMotion: false) == flies, "\(others)")
        }
        let panel = Panel(sessions: [session("d", .done)])
        #expect(!DoneRun.flies(done, panel: panel, reduceMotion: true))
        #expect(!DoneRun.flies(nil, panel: panel, reduceMotion: false))
        #expect(!DoneRun.flies(Banner(id: 2, session: session("w", .waiting)), panel: Panel(sessions: [session("w", .waiting)]),
                               reduceMotion: false))
    }
}
