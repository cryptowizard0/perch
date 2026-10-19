import Foundation

/// The Done banner run (#64): on Done, the mascot hops, runs right into the notch, comes out on the right wing and
/// pulls the banner open behind it like a curtain, stands on its far end under the confetti while it shows, then runs
/// back the same way, rolling it up. A pure path: where the mascot is, whether the notch hides it and how much of the
/// banner shows, as functions of time (the reference clock, like `Mascot.frame`) and the band's geometry.
///
/// Positions are the mascot canvas's left edge, in points from the band's left edge.
public struct DoneRun: Equatable, Sendable {
    /// The collapsed band: the left wing, then the notch (0 wide for the menu bar pill, where nothing hides it).
    public struct Band: Equatable, Sendable {
        public var leftWing: Double
        public var notchWidth: Double

        public init(leftWing: Double, notchWidth: Double) {
            self.leftWing = leftWing
            self.notchWidth = notchWidth
        }

        /// Where the right wing, and the banner, begin.
        public var notchEnd: Double { leftWing + notchWidth }
    }

    public enum Move: Equatable, Sendable {
        /// Done's hop, timed to the chime; again in place when another Done swaps the banner.
        case hop
        /// Running out or back, pulling the banner open or rolling it up.
        case run
        /// On the banner's far end, swaying under the confetti.
        case stand
        /// Straight home: something needs you or failed.
        case dash
    }

    public struct Position: Equatable, Sendable {
        public var x: Double
        /// Entirely over the notch, so the hardware hides it.
        public var hidden: Bool
        /// How much of the right wing shows from its inner edge (the banner behind the mascot); nil: all of it.
        public var reveal: Double?
        public var move: Move
        /// How far into this move.
        public var age: TimeInterval
        public var facingRight: Bool

        public init(x: Double, hidden: Bool, reveal: Double?, move: Move, age: TimeInterval, facingRight: Bool) {
            self.x = x
            self.hidden = hidden
            self.reveal = reveal
            self.move = move
            self.age = age
            self.facingRight = facingRight
        }
    }

    /// Its spot on the left wing, where the collapsed bar draws it.
    public static let home = Double(NotchGeometry.collapsedInset)
    public static let speed: Double = 240
    /// Done's reaction up to the end of its hop.
    public static let hopDuration: TimeInterval = 8.0 / 12
    public static let dashDuration: TimeInterval = 0.3
    /// How much the right wing grows so it can stand at the banner's end.
    public static let room = Double(Mascot.width)
    /// It stands this far into the banner's trailing inset.
    static let overlap: Double = 4

    /// Whether a banner that just went up starts a run: only a Done banner, only while nothing needs you or has
    /// failed (so an orange or red mascot never leaves its spot), never with Reduce Motion. No cooldown.
    public static func flies(_ banner: Banner?, panel: Panel, reduceMotion: Bool) -> Bool {
        guard let banner, banner.status == .done, !reduceMotion else { return false }
        return !panel.sessions.contains { $0.status == .waiting || $0.status == .failed }
    }

    struct Leg: Equatable, Sendable {
        var start: TimeInterval
        /// Where it was headed, and when it would have got there.
        var from: Double
        var to: Double
        var arrival: TimeInterval
        var move: Move
        /// Cut short by an interruption.
        var cut: TimeInterval?

        init(start: TimeInterval, end: TimeInterval, from: Double, to: Double, move: Move) {
            self.start = start
            arrival = end
            self.from = from
            self.to = to
            self.move = move
        }

        var end: TimeInterval { cut ?? arrival }

        func x(at time: TimeInterval) -> Double {
            guard arrival > start else { return to }
            return from + (to - from) * min(max((min(time, end) - start) / (arrival - start), 0), 1)
        }
    }

    public let band: Band
    /// The banner's wing (`Banner.wing`), without the room.
    public private(set) var bannerWing: Double
    private(set) var legs: [Leg] = []
    /// It dashed home: the banner is no longer its.
    public private(set) var interrupted = false

    /// A run starting `start` with a banner `bannerWing` wide that shows `bannerDuration` once fully open.
    public init(start: TimeInterval, band: Band, bannerWing: Double, bannerDuration: TimeInterval) {
        self.band = band
        self.bannerWing = bannerWing
        legs = [Leg(start: start, end: start + Self.hopDuration, from: Self.home, to: Self.home, move: .hop)]
        runOut(at: start + Self.hopDuration, from: Self.home, showing: bannerDuration)
    }

    /// Where it stands at the banner's end.
    var far: Double { band.notchEnd + bannerWing - Self.overlap }

    /// When it's home again; `position` is nil from then on.
    public var end: TimeInterval { legs.last?.end ?? 0 }

    /// When it has fully opened the banner (its time starts then).
    public var opened: TimeInterval? {
        legs.last { $0.move == .stand }?.start
    }

    /// When the banner has rolled up behind it on the way back, so it can go; nil once it isn't the run's.
    public var bannerEnd: TimeInterval? {
        guard !interrupted, let back = legs.last, back.move == .run, back.to < back.from else { return nil }
        let rolled = back.from <= band.notchEnd ? back.start : back.start + (back.from - band.notchEnd) / Self.speed
        return min(rolled, back.end)
    }

    public func position(at time: TimeInterval) -> Position? {
        guard let first = legs.first, time >= first.start, time < end, let leg = legs.last(where: { $0.start <= time }) else {
            return nil
        }
        let x = leg.x(at: time)
        let hidden = x >= band.leftWing && x + Double(Mascot.width) <= band.notchEnd
        var reveal: Double?
        if !interrupted && leg.move != .stand { reveal = min(max(x - band.notchEnd, 0), bannerWing) }
        return Position(x: x, hidden: hidden, reveal: reveal, move: leg.move, age: time - leg.start,
                        facingRight: leg.move == .run ? leg.to >= leg.from : true)
    }

    // MARK: - Interruptions

    /// Another Done swapped the banner: it hops in place if it is standing on the right (else carries on), then runs to
    /// the new banner's end and its time starts over.
    public mutating func anotherDone(at time: TimeInterval, bannerWing: Double, bannerDuration: TimeInterval) {
        guard !interrupted, time < end, let leg = legs.last(where: { $0.start <= time }) else { return }
        self.bannerWing = bannerWing
        switch leg.move {
        case .hop:
            // Still hopping: let it finish, then run.
            cut(at: leg.end)
            runOut(at: leg.end, from: leg.to, showing: bannerDuration)
        case .stand:
            let x = leg.x(at: time)
            cut(at: time)
            legs.append(Leg(start: time, end: time + Self.hopDuration, from: x, to: x, move: .hop))
            runOut(at: time + Self.hopDuration, from: x, showing: bannerDuration)
        case .run, .dash:
            let x = leg.x(at: time)
            cut(at: time)
            runOut(at: time, from: x, showing: bannerDuration)
        }
    }

    /// Something needs you or failed: straight home in `dashDuration`, banner or not.
    public mutating func dashHome(at time: TimeInterval) {
        guard time < end, let leg = legs.last(where: { $0.start <= time }) else { return }
        let x = leg.x(at: time)
        cut(at: time)
        interrupted = true
        if abs(x - Self.home) >= 1 { legs.append(Leg(start: time, end: time + Self.dashDuration, from: x, to: Self.home, move: .dash)) }
    }

    /// The banner went early (its session left Done): back home now, at a run.
    public mutating func returnNow(at time: TimeInterval) {
        guard !interrupted, time < end, let leg = legs.last(where: { $0.start <= time }) else { return }
        if leg.move == .run && leg.to < leg.from { return }
        let x = leg.x(at: time)
        cut(at: time)
        legs.append(Leg(start: time, end: time + abs(x - Self.home) / Self.speed, from: x, to: Self.home, move: .run))
    }

    /// Drops what comes after `time`, ending the current leg there.
    private mutating func cut(at time: TimeInterval) {
        legs = legs.compactMap { leg in
            guard leg.start < time else { return nil }
            var leg = leg
            if leg.end > time { leg.cut = time }
            return leg
        }
    }

    /// Out to the banner's end from `x`, stands for `duration`, then back home.
    private mutating func runOut(at time: TimeInterval, from x: Double, showing duration: TimeInterval) {
        let arrive = time + abs(far - x) / Self.speed
        legs.append(Leg(start: time, end: arrive, from: x, to: far, move: .run))
        legs.append(Leg(start: arrive, end: arrive + duration, from: far, to: far, move: .stand))
        let back = arrive + duration
        legs.append(Leg(start: back, end: back + (far - Self.home) / Self.speed, from: far, to: Self.home, move: .run))
    }
}
