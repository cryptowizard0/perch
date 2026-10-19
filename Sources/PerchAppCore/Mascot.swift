import Foundation
import PerchCore

/// Perch's mascot in the collapsed notch (#22): a pixel cyclops whose look and motion tell the panel's signal.
/// Drawn cell by cell like `PixelIcon`, one point a cell; this only says which cells, the view picks the colours.
///
/// Running trots, Needs you waves and flashes its antenna, Idle sleeps with a drifting "z"; Failed, Done and
/// "nothing to show" stand still. Entering Needs you / Failed / Done (the panel's pulse) plays a reaction: the first
/// beat is timed to its chime (#35), then a second act (an "!", a fall and some smoke, confetti). Asleep, idle, failed
/// or done, it now and then plays a quirk from its mood's set (a yawn, a look around, a snot bubble; a sigh, rubbing
/// its head; a sway, a hum). Failed keeps its X eye and Done its happy eye through theirs (#59). It also feels the
/// time: a turn running over 10 minutes makes it sweat (#60); Needs you insists after a minute and knocks on the glass
/// from five (#61). After you answer it, it bows (Allow) or scratches its head (Deny) (#62).
public enum Mascot {
    /// The canvas, in points: the 13 × 13 sprite at `origin`, with room above for the hop and beside for the
    /// shake and the sparkles. Idle's "z" drifts past the right edge, up to `overflowWidth`.
    public static let width = 15
    public static let height = 16
    public static let overflowWidth = 18
    static let origin = (x: 1, y: 3)
    /// Reactions and quirks may also use this much room around the canvas (the band has it above and below, the
    /// wing's inset on the left); everything else stays on the canvas.
    public static let margin = 6

    /// What the mascot shows: the panel's signal, or asleep with no sessions or no perchd.
    public enum Mood: Equatable, Sendable, CaseIterable {
        case running, waiting, failed, done, idle, asleep

        public init(signal: SessionStatus?, online: Bool = true) {
            guard online, let signal else {
                self = .asleep
                return
            }
            switch signal {
            case .running: self = .running
            case .waiting: self = .waiting
            case .failed: self = .failed
            case .done: self = .done
            case .idle: self = .idle
            }
        }

        /// Frames a second it needs while not reacting; 0 = it stands still and never redraws.
        public var fps: Double {
            switch self {
            case .running: return 5
            case .waiting: return 4
            case .idle: return 1
            case .failed, .done, .asleep: return 0
            }
        }

        /// How long the entry reaction lasts; nil for moods that have none.
        public var reactionDuration: TimeInterval? {
            switch self {
            case .waiting: return 1.3
            case .failed: return 1.6
            case .done: return 1.5
            case .running, .idle, .asleep: return nil
            }
        }

        /// The quirks it plays now and then; none while running or waiting.
        public var quirks: [Quirk] {
            switch self {
            case .idle, .asleep: return [.yawn, .lookAround, .bubble]
            case .failed: return [.sigh, .rubHead]
            case .done: return [.sway, .hum]
            case .running, .waiting: return []
            }
        }
    }

    /// Frames a second while a reaction plays.
    public static let reactionFPS: Double = 14

    /// How often to redraw: fast while a reaction or quirk plays, else the mood's own rate (0 for the still moods).
    public static func fps(_ mood: Mood, reacting: Bool, quirking: Bool) -> Double {
        reacting || quirking ? reactionFPS : mood.fps
    }

    /// An entry reaction `age` seconds in. It plays the look of the mood that caused it, which may not be the
    /// signal's (a session finishing while another needs you hops blue, then goes back to orange).
    public struct Reaction: Equatable, Sendable {
        public let mood: Mood
        public let age: TimeInterval

        public init(mood: Mood, age: TimeInterval) {
            self.mood = mood
            self.age = age
        }

        public var isOver: Bool { age < 0 || age >= (mood.reactionDuration ?? 0) }
    }

    public enum Ink: Equatable, Hashable, Sendable, CaseIterable {
        /// The state's colour.
        case body
        /// The eye white, the lit antenna tip, the sparkles.
        case white
        /// Pupil, lids and mouth: near-black, so they read as cut-outs on the black notch.
        case dark
        /// Idle's "z", smoke, the snot bubble.
        case faint
        /// Done's confetti, three colours.
        case confetti0, confetti1, confetti2
    }

    public struct Cell: Equatable, Hashable, Sendable {
        public let x: Int
        public let y: Int
        public let ink: Ink

        public init(x: Int, y: Int, ink: Ink) {
            self.x = x
            self.y = y
            self.ink = ink
        }
    }

    /// The cells to draw `time` seconds into any clock (the loops repeat), sorted row by row. A reaction wins over
    /// a quirk; a quirk plays only in the mood whose set has it.
    ///
    /// `since` is when the signal's state began, on the same clock: the oldest running turn's start (Running sweats
    /// from `sweatAfter`), the longest wait's start (Needs you insists from `insistAfter`, knocks from `knockAfter`).
    /// Nil leaves time out of it.
    ///
    /// Precedence, highest first: the entry reaction, an answer's bow or scratch, a quirk, the mood's own loop.
    public static func frame(_ mood: Mood, time: TimeInterval, since: TimeInterval? = nil, reaction: Reaction? = nil,
                             answer: AnswerPlay? = nil, quirk: QuirkPlay? = nil) -> [Cell] {
        if let reaction, !reaction.isOver {
            return draw(look(reaction.mood, time: time, reaction: reaction.age))
        }
        if let answer, !answer.isOver {
            return draw(look(answer.answer, age: answer.age, mood: mood))
        }
        if let quirk, mood.quirks.contains(quirk.quirk), !quirk.isOver {
            return draw(look(quirk.quirk, age: quirk.age, mood: mood))
        }
        return draw(look(mood, time: time, reaction: nil, waited: since.map { time - $0 }))
    }

    // MARK: - Answers

    /// What it does after you answer it (#62): a bow for Allow (or any other option), a sheepish head scratch for Deny.
    /// Neither a quirk nor a pulse: no banner, no sound; it plays in the signal's colour.
    public enum Answer: Equatable, Sendable, CaseIterable {
        case bow, scratch

        /// The reaction to sending `value` to a request.
        public init(response value: String) {
            self = value == "deny" ? .scratch : .bow
        }

        public var duration: TimeInterval {
            switch self {
            case .bow: return 1.2
            case .scratch: return 1.4
            }
        }
    }

    public struct AnswerPlay: Equatable, Sendable {
        public let answer: Answer
        public let age: TimeInterval

        public init(_ answer: Answer, age: TimeInterval) {
            self.answer = answer
            self.age = age
        }

        public var isOver: Bool { age < 0 || age >= answer.duration }
    }

    // MARK: - Time in the state

    /// A running turn this old makes it sweat: a drop by its head, and every `wipePeriod` it wipes its forehead.
    public static let sweatAfter: TimeInterval = 600
    public static let wipePeriod: TimeInterval = 6
    /// Where in each `wipePeriod` the wipe plays, and when the next drop has formed.
    static let wipe: Range<TimeInterval> = 2..<3
    static let dropBack: TimeInterval = 3.6

    /// Needs you after this long waves both arms together, hops every `hopPeriod` and flashes its tip faster.
    public static let insistAfter: TimeInterval = 60
    static let hopPeriod: TimeInterval = 4
    static let hop: Range<TimeInterval> = 2..<2.5
    /// From this long it also knocks on the glass, every `knockPeriod`; nothing changes after that.
    public static let knockAfter: TimeInterval = 300
    public static let knockPeriod: TimeInterval = 8
    /// A lean in, then three knocks, a quarter second each way.
    static let knockDuration: TimeInterval = 1.75

    // MARK: - Quirks

    /// Something it does now and then, then goes back to its mood's look.
    public enum Quirk: Equatable, Sendable, CaseIterable {
        /// Asleep or idle: stretches both arms up with a big yawn.
        case yawn
        /// Asleep or idle: opens its eye, looks left, right, and dozes off again.
        case lookAround
        /// Asleep or idle: a snot bubble grows, pops and wakes it for a moment.
        case bubble
        /// Failed: sinks a point, its antenna flops over, a wisp of smoke, back up.
        case sigh
        /// Failed: one arm up on its head, rubbing twice.
        case rubHead
        /// Done: sways side to side, blinking once mid-sway.
        case sway
        /// Done: hums; a ♪ rises and drifts off like Idle's "z".
        case hum

        public var duration: TimeInterval {
            switch self {
            case .yawn: return 2.4
            case .lookAround: return 2.6
            case .bubble: return 2.8
            case .sigh: return 2.4
            case .rubHead: return 2.4
            case .sway: return 2.4
            case .hum: return 2.8
            }
        }
    }

    public struct QuirkPlay: Equatable, Sendable {
        public let quirk: Quirk
        public let age: TimeInterval

        public init(_ quirk: Quirk, age: TimeInterval) {
            self.quirk = quirk
            self.age = age
        }

        public var isOver: Bool { age < 0 || age >= quirk.duration }
    }

    /// One quirk in every `quirkPeriod` of the reference clock, at a scrambled moment and of a scrambled kind, so it
    /// feels random but needs no state (and tests can find them).
    public static let quirkPeriod: TimeInterval = 240

    /// The quirk of the period containing `time`, drawn from `quirks` (not empty), and when it starts.
    static func quirk(inPeriodOf time: TimeInterval, from quirks: [Quirk]) -> (quirk: Quirk, start: TimeInterval) {
        let period = (time / quirkPeriod).rounded(.down)
        let hash = UInt64(bitPattern: Int64(period)) &* 0x9E37_79B9_7F4A_7C15
        let offset = 20 + Double((hash >> 33) % 180)
        let quirk = quirks[Int((hash >> 13) % UInt64(quirks.count))]
        return (quirk, period * quirkPeriod + offset)
    }

    /// The next quirk `mood` starts after `time`: the same moment whatever the mood, of a kind from its set. Nil for
    /// the moods without quirks.
    public static func nextQuirk(after time: TimeInterval, in mood: Mood) -> (quirk: Quirk, start: TimeInterval)? {
        let quirks = mood.quirks
        guard !quirks.isEmpty else { return nil }
        let this = quirk(inPeriodOf: time, from: quirks)
        return this.start > time ? this : quirk(inPeriodOf: time + quirkPeriod, from: quirks)
    }

    /// The quirks to schedule: the mood's, but none while perchd is offline or motion is reduced.
    public static func quirks(_ mood: Mood, online: Bool, reduceMotion: Bool) -> [Quirk] {
        online && !reduceMotion ? mood.quirks : []
    }

    /// The one frame shown when motion is reduced.
    public static func still(_ mood: Mood) -> [Cell] {
        frame(mood, time: 0)
    }

    // MARK: - Looks

    struct Look {
        var eye = Eye.open
        var mouth = Mouth.neutral
        var antenna = Antenna.up
        var tipLit = false
        var arms = Arms.down
        var feetTucked = false
        var dx = 0
        var dy = 0
        /// Idle's "z", 0…2 steps up.
        var z: Int?
        var sparkle = false
        /// Needs you's "!" beside its head.
        var exclaim = false
        /// Failed's fall: on its side, feet to the right.
        var lying = false
        /// Smoke over it, 0…3 steps up.
        var smoke: Int?
        /// Done's confetti, this long after the burst.
        var confetti: TimeInterval?
        /// The snot bubble: 0…2 growing, 3 popped.
        var bubble: Int?
        /// Failed's sigh: a wisp of smoke off the antenna, 0…2 steps up.
        var wisp: Int?
        /// Done's hum: a ♪, 0…3 steps up and to the right.
        var note: Int?
        /// A long run's sweat drop by its head.
        var sweat = false
        /// A knock on the glass: a white glint by the hand.
        var glint = false
    }

    /// `waited`: how long the signal's state has lasted, when known.
    static func look(_ mood: Mood, time: TimeInterval, reaction age: TimeInterval?, waited: TimeInterval? = nil) -> Look {
        var look = Look()
        let t = max(time, 0)
        func step(_ seconds: Double) -> Int { Int((t / seconds).rounded(.down)) }
        func at<T>(_ frames: [T], fps: Double, _ age: TimeInterval) -> T? {
            let index = Int((age * fps).rounded(.down))
            return frames.indices.contains(index) ? frames[index] : nil
        }

        switch mood {
        case .running:
            if step(0.2) % 2 == 1 {
                look.feetTucked = true
                look.dy = -1
                look.antenna = .left
            }
            look.eye = [Eye.open, .right, .open, .left][step(0.8) % 4]
            // Late in the cycle, so the still frame (t = 0) has its eye open. Longer than a redraw (≤ ~0.22 s once
            // the display rounds the 5 fps interval up) so every cycle catches it, whatever the sampling phase.
            if (3.6..<3.9).contains(t.truncatingRemainder(dividingBy: 4)) { look.eye = .blink }
            if let waited, waited >= sweatAfter {
                // It keeps trotting; the hand comes up to its brow and wipes the drop away, then a new one forms.
                let cycle = t.truncatingRemainder(dividingBy: wipePeriod)
                if wipe.contains(cycle) {
                    look.arms = .wipe(across: Int(((cycle - wipe.lowerBound) / 0.25).rounded(.down)) % 2 == 1)
                } else {
                    look.sweat = cycle < wipe.lowerBound || cycle >= dropBack
                }
            }
        case .waiting:
            look.eye = .up
            look.mouth = .open
            look.arms = step(0.25) % 2 == 1 ? .leftUp : .rightUp
            look.tipLit = step(0.5) % 2 == 1
            if let waited, waited >= insistAfter {
                look.arms = step(0.25) % 2 == 1 ? .bothUp : .down
                look.tipLit = step(0.25) % 2 == 1
                if hop.contains(waited.truncatingRemainder(dividingBy: hopPeriod)) {
                    look.dy = waited.truncatingRemainder(dividingBy: hopPeriod) < hop.lowerBound + 0.25 ? -2 : -1
                    look.feetTucked = true
                    look.arms = .bothUp
                }
                let knock = (waited - knockAfter).truncatingRemainder(dividingBy: knockPeriod)
                if waited >= knockAfter, knock < knockDuration {
                    // Leans in, eye wide, and knocks three times; a white glint at its hand on each.
                    let beat = Int((knock / 0.25).rounded(.down))
                    look.dy = 1
                    look.feetTucked = false
                    look.eye = .wide
                    look.arms = .knock(hit: beat % 2 == 1)
                    look.glint = beat % 2 == 1
                }
            }
            if let age, let dy = at([-2, -3, -2, 0, -2, -3, -2, 0], fps: 12, age) {
                look.dy = dy
                look.feetTucked = true
                look.arms = .bothUp
            } else if let age {
                // "!" — and the antenna flashing twice as fast.
                look.exclaim = true
                look.arms = .down
                look.tipLit = Int((age * 8).rounded(.down)) % 2 == 0
            }
        case .failed:
            look.eye = .cross
            look.mouth = .frown
            look.antenna = .bent
            if let age, let dx = at([1, -1, 1, -1, 1, -1, 0], fps: 14, age) {
                look.dx = dx
            } else if let age, age < 1.3 {
                // Falls over, smokes a little, gets back up with a hop.
                look.lying = true
                look.dy = 1
                look.feetTucked = true
                if age >= 0.6 { look.smoke = min(Int(((age - 0.6) / 0.2).rounded(.down)), 3) }
            } else if let age, age < 1.45 {
                look.dy = -1
            }
        case .done:
            look.eye = .happy
            look.mouth = .smile
            if let age, let index = at(Array(0..<8), fps: 12, age) {
                look.dy = [-2, -3, -3, -2, 0, 0, 0, 0][index]
                look.arms = index < 5 ? .bothUp : .down
                look.feetTucked = index < 4
                look.sparkle = index % 2 == 0
            } else if let age {
                // Confetti, and a little dance under it.
                look.confetti = age - 0.6
                look.arms = Int((age * 6).rounded(.down)) % 2 == 0 ? .leftUp : .rightUp
            }
        case .idle:
            look.eye = .closed
            look.mouth = .small
            look.antenna = .drooping
            look.z = step(1) % 3
        case .asleep:
            look.eye = .closed
            look.mouth = .small
            look.antenna = .drooping
        }
        return look
    }

    /// A bow or scratch over the mood's still look. Failed keeps its X eye: the signal never softens.
    static func look(_ answer: Answer, age: TimeInterval, mood: Mood) -> Look {
        var look = look(mood, time: 0, reaction: nil)
        look.z = nil
        var eye: Eye?
        switch answer {
        case .bow:
            // Leans forward, eye down, antenna tipped towards you; holds; comes back up.
            if age < 0.95 {
                look.dy = 1
                look.antenna = .forward
                look.arms = .down
                eye = .down
            }
        case .scratch:
            switch age {
            case ..<0.2, 1.2...: look.arms = .leftUp
            default:
                look.arms = .behindHead(scratching: Int(((age - 0.2) / 0.15).rounded(.down)) % 2 == 1)
                look.mouth = .small
                eye = .right
            }
        }
        if let eye, mood != .failed { look.eye = eye }
        return look
    }

    static func look(_ quirk: Quirk, age: TimeInterval, mood: Mood) -> Look {
        var look = look(mood, time: 0, reaction: nil)
        look.z = nil
        switch quirk {
        case .yawn:
            switch age {
            case ..<0.3, 1.5..<2.0: look.eye = .drowsy
            case ..<1.5:
                look.eye = .squeezed
                look.mouth = .yawn
                look.arms = .bothUp
                look.antenna = .up
                look.dy = age < 0.5 || age >= 1.3 ? 0 : -1
            default: break
            }
        case .lookAround:
            switch age {
            case ..<0.3, 1.9..<2.2: look.eye = .drowsy
            case ..<0.9: look.eye = .left
            case ..<1.5: look.eye = .right
            case ..<1.9: look.eye = .open
            default: break
            }
            if (0.3..<1.9).contains(age) {
                look.antenna = .up
                look.mouth = .neutral
            }
        case .bubble:
            switch age {
            case ..<0.6: look.bubble = 0
            case ..<1.2: look.bubble = 1
            case ..<2.2: look.bubble = 2
            case ..<2.4: look.bubble = 3
            default:
                // Startled awake for a moment.
                look.eye = .open
                look.antenna = .up
                look.mouth = .open
                look.dy = age < 2.55 ? -1 : 0
            }
        case .sigh:
            switch age {
            case ..<0.3, 1.9..<2.2: look.antenna = .flat
            case ..<1.9:
                look.dy = 1
                look.antenna = .flat
                if age >= 0.7 { look.wisp = min(Int(((age - 0.7) / 0.4).rounded(.down)), 2) }
            default: break
            }
        case .rubHead:
            switch age {
            case ..<0.3, 1.9..<2.2: look.arms = .rightUp
            case ..<1.9: look.arms = .onHead(reaching: Int(((age - 0.3) / 0.4).rounded(.down)) % 2 == 1)
            default: break
            }
        case .sway:
            // Side to side, the antenna trailing behind.
            let dx = [-1, -1, 0, 1, 1, 0, -1, 0][min(Int((age / 0.3).rounded(.down)), 7)]
            look.dx = dx
            look.antenna = dx < 0 ? .drooping : dx > 0 ? .left : .up
            if (1.0..<1.2).contains(age) { look.eye = .happyBlink }
        case .hum:
            look.mouth = .small
            if (0.3..<2.3).contains(age) { look.note = Int(((age - 0.3) / 0.5).rounded(.down)) }
        }
        return look
    }

    // MARK: - Drawing

    /// The body between the antenna and the feet, rows 2–11 of the sprite.
    static let body = [
        "...#######...",
        "..#########..",
        ".###########.",
        ".###########.",
        ".###########.",
        ".###########.",
        ".###########.",
        ".###########.",
        "..#########..",
        "..#########..",
    ]

    /// The 5 × 5 eye at (4, 4): `w` white, `o` dark, `.` body.
    enum Eye {
        case open, up, left, right, blink, closed, happy, cross, drowsy, squeezed
        /// Leaning in to knock: wide open, staring straight out.
        case wide
        /// Looking down (a bow).
        case down
        /// Done's blink: the happy arc squeezed flatter, still a "^".
        case happyBlink

        var rows: [String] {
            switch self {
            case .open: return [".www.", "wwwww", "wwoww", "wwwww", ".www."]
            case .up: return [".www.", "wwoww", "wwwww", "wwwww", ".www."]
            case .left: return [".www.", "wwwww", "wowww", "wwwww", ".www."]
            case .right: return [".www.", "wwwww", "wwwow", "wwwww", ".www."]
            case .blink: return [".....", ".....", ".ooo.", ".....", "....."]
            case .closed: return [".....", ".....", ".....", ".ooo.", "....."]
            case .happy: return [".....", "..o..", ".o.o.", "o...o", "....."]
            case .cross: return [".www.", "wowow", "wwoww", "wowow", ".www."]
            case .drowsy: return [".....", ".....", "ooooo", "wwoww", ".www."]
            case .squeezed: return [".....", "o...o", ".o.o.", "..o..", "....."]
            case .happyBlink: return [".....", ".....", ".ooo.", "o...o", "....."]
            case .wide: return ["wwwww", "wwwww", "wwoww", "wwwww", "wwwww"]
            case .down: return [".www.", "wwwww", "wwwww", "wwoww", ".www."]
            }
        }
    }

    enum Mouth {
        case neutral, open, smile, frown, small, yawn

        var cells: [(Int, Int)] {
            switch self {
            case .neutral: return [(5, 10), (6, 10), (7, 10)]
            case .open: return [(5, 10), (6, 10), (7, 10), (5, 11), (6, 11), (7, 11)]
            case .smile: return [(4, 10), (8, 10), (5, 11), (6, 11), (7, 11)]
            case .frown: return [(5, 10), (6, 10), (7, 10), (4, 11), (8, 11)]
            case .small: return [(6, 10)]
            case .yawn: return [(5, 9), (6, 9), (7, 9), (5, 10), (6, 10), (7, 10), (5, 11), (6, 11), (7, 11)]
            }
        }
    }

    /// Tip first.
    enum Antenna {
        case up, left, drooping, bent
        /// Failed's sigh: bent all the way over onto its head.
        case flat
        /// A bow: tipped towards you, so only its base shows, the tip in front of it.
        case forward

        var cells: [(Int, Int)] {
            switch self {
            case .up: return [(6, 0), (6, 1)]
            case .left: return [(5, 0), (6, 1)]
            case .drooping: return [(7, 0), (6, 1)]
            case .bent: return [(7, 1), (6, 1)]
            case .flat: return [(8, 1), (7, 1)]
            case .forward: return [(6, 1)]
            }
        }
    }

    enum Arms {
        case down, leftUp, rightUp, bothUp
        /// Failed's rub: the right arm over the top of its head, the hand reaching further in or back.
        case onHead(reaching: Bool)
        /// A long run's wipe: the right hand at its brow, or further across it.
        case wipe(across: Bool)
        /// A long wait's knock: the right hand raised, up against the glass or drawn back.
        case knock(hit: Bool)
        /// Deny's scratch: the left hand up behind its head, scratching back and forth.
        case behindHead(scratching: Bool)

        var cells: [(Int, Int)] {
            let left = [(0, 8), (0, 9)], right = [(12, 8), (12, 9)]
            let leftRaised = [(0, 4), (0, 5)], rightRaised = [(12, 4), (12, 5)]
            switch self {
            case .down: return left + right
            case .leftUp: return leftRaised + right
            case .rightUp: return left + rightRaised
            case .bothUp: return leftRaised + rightRaised
            case .onHead(let reaching): return left + [(12, 5), (12, 4), (11, 3), (10, 2), (9, 1)] + (reaching ? [(8, 1)] : [])
            case .wipe(let across): return left + (across ? [(12, 4), (11, 3), (10, 2)] : [(12, 5), (12, 4), (11, 3)])
            case .knock(let hit): return left + (hit ? rightRaised : [(12, 5), (12, 6)])
            case .behindHead(let scratching): return [(0, 5), (0, 4), (1, 3), scratching ? (2, 2) : (1, 2)] + right
            }
        }
    }

    static let z = ["####", "..#.", ".#..", "####"]
    static let note = [".##", ".#.", "##.", "##."]

    /// Done's confetti: launched from the top of its head with these velocities (points a second), then falling.
    static let confettiBits: [(vx: Double, vy: Double, ink: Ink)] = [
        (-14, -30, .confetti0), (14, -30, .confetti1), (-6, -36, .confetti2), (6, -36, .confetti0),
        (-20, -20, .confetti1), (20, -20, .confetti2), (-10, -26, .white), (10, -26, .white),
        (0, -38, .confetti1), (-24, -14, .confetti2), (24, -14, .confetti0),
    ]
    static let gravity = 70.0

    static func draw(_ look: Look) -> [Cell] {
        var cells: [Point: Ink] = [:]
        let ox = origin.x + look.dx, oy = origin.y + look.dy
        // Lying: the sprite turned a quarter, antenna to the left and feet to the right.
        func put(_ x: Int, _ y: Int, _ ink: Ink) {
            let (px, py) = look.lying ? (y, 12 - x) : (x, y)
            cells[Point(x: ox + px, y: oy + py)] = ink
        }
        /// Around the sprite (never turned with it).
        func overlay(_ x: Int, _ y: Int, _ ink: Ink) { cells[Point(x: ox + x, y: oy + y)] = ink }

        for (row, line) in body.enumerated() {
            for (x, char) in line.enumerated() where char == "#" { put(x, row + 2, .body) }
        }
        for (index, (x, y)) in look.antenna.cells.enumerated() { put(x, y, index == 0 && look.tipLit ? .white : .body) }
        for (x, y) in look.arms.cells { put(x, y, .body) }
        for (x, y) in look.feetTucked ? [(4, 12), (8, 12)] : [(3, 12), (4, 12), (8, 12), (9, 12)] { put(x, y, .body) }
        for (row, line) in look.eye.rows.enumerated() {
            for (x, char) in line.enumerated() where char != "." { put(4 + x, 4 + row, char == "w" ? .white : .dark) }
        }
        for (x, y) in look.mouth.cells { put(x, y, .dark) }
        if look.sparkle { overlay(-1, 2, .white); overlay(13, 2, .white) }
        if look.exclaim { for y in [-1, 0, 1, 3] { overlay(11, y, .white) } }
        if look.sweat { overlay(12, 2, .white); overlay(12, 3, .white) }
        if look.glint { overlay(13, 4, .white) }
        if let step = look.smoke {
            for (x, y) in [(5, 0), (7, -1), (6, -3), (8, -4)] { overlay(x, y - step, .faint) }
        }
        if let bubble = look.bubble {
            let ring: [(Int, Int)]
            switch bubble {
            case 0: ring = [(12, 10)]
            case 1: ring = [(12, 9), (13, 9), (12, 10), (13, 10)]
            case 2: ring = [(13, 8), (12, 9), (14, 9), (13, 10)]
            default: ring = [(11, 7), (15, 7), (11, 11), (15, 11)]
            }
            for (x, y) in ring { overlay(x, y, bubble == 3 ? .white : .faint) }
        }
        if let age = look.confetti, age >= 0 {
            // Clipped to the room around the canvas: bits that fly further are gone.
            let bounds = -margin..<(width + margin)
            for bit in confettiBits {
                let x = 6 + Int((bit.vx * age).rounded())
                let y = 1 + Int((bit.vy * age + gravity * age * age / 2).rounded())
                let point = Point(x: ox + x, y: oy + y)
                if bounds.contains(point.x), (-margin..<(height + margin)).contains(point.y), cells[point] == nil {
                    cells[point] = bit.ink
                }
            }
        }
        if let step = look.wisp {
            for (x, y) in [(9, 0), (10, -1)] { overlay(x, y - step, .faint) }
        }
        if let step = look.note {
            for (row, line) in note.enumerated() {
                for (x, char) in line.enumerated() where char == "#" { overlay(13 + step + x, 3 - 2 * step + row, .faint) }
            }
        }
        if let step = look.z {
            for (row, line) in z.enumerated() {
                for (x, char) in line.enumerated() where char == "#" { overlay(13 + x, 1 - 2 * step + row, .faint) }
            }
        }
        return cells.map { Cell(x: $0.key.x, y: $0.key.y, ink: $0.value) }
            .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    }

    struct Point: Hashable {
        let x: Int
        let y: Int
    }
}
