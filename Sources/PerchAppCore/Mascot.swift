import Foundation
import PerchCore

/// Perch's mascot in the collapsed notch (#22): a pixel cyclops whose look and motion tell the panel's signal.
/// Drawn cell by cell like `PixelIcon`, one point a cell; this only says which cells, the view picks the colours.
///
/// Running trots, Needs you waves and flashes its antenna, Idle sleeps with a drifting "z"; Failed, Done and
/// "nothing to show" stand still. Entering Needs you / Failed / Done (the panel's pulse) plays a short reaction.
public enum Mascot {
    /// The canvas, in points: the 13 × 13 sprite at `origin`, with room above for the hop and beside for the
    /// shake and the sparkles. Idle's "z" drifts past the right edge, up to `overflowWidth`.
    public static let width = 15
    public static let height = 16
    public static let overflowWidth = 18
    static let origin = (x: 1, y: 3)

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
            case .waiting: return 0.7
            case .failed: return 0.5
            case .done: return 0.6
            case .running, .idle, .asleep: return nil
            }
        }
    }

    /// Frames a second while a reaction plays.
    public static let reactionFPS: Double = 14

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

    public enum Ink: Equatable, Hashable, Sendable {
        /// The state's colour.
        case body
        /// The eye white, the lit antenna tip, the sparkles.
        case white
        /// Pupil, lids and mouth: near-black, so they read as cut-outs on the black notch.
        case dark
        /// Idle's "z".
        case faint
    }

    public struct Cell: Equatable, Hashable, Sendable {
        public let x: Int
        public let y: Int
        public let ink: Ink
    }

    /// The cells to draw `time` seconds into any clock (the loops repeat), sorted row by row.
    public static func frame(_ mood: Mood, time: TimeInterval, reaction: Reaction? = nil) -> [Cell] {
        if let reaction, !reaction.isOver {
            return draw(look(reaction.mood, time: time, reaction: reaction.age))
        }
        return draw(look(mood, time: time, reaction: nil))
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
    }

    static func look(_ mood: Mood, time: TimeInterval, reaction age: TimeInterval?) -> Look {
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
        case .waiting:
            look.eye = .up
            look.mouth = .open
            look.arms = step(0.25) % 2 == 1 ? .leftUp : .rightUp
            look.tipLit = step(0.5) % 2 == 1
            if let age, let dy = at([-2, -3, -2, 0, -2, -3, -2, 0], fps: 12, age) {
                look.dy = dy
                look.feetTucked = true
                look.arms = .bothUp
            }
        case .failed:
            look.eye = .cross
            look.mouth = .frown
            look.antenna = .bent
            if let age, let dx = at([1, -1, 1, -1, 1, -1, 0], fps: 14, age) { look.dx = dx }
        case .done:
            look.eye = .happy
            look.mouth = .smile
            if let age, let index = at(Array(0..<8), fps: 12, age) {
                look.dy = [-2, -3, -3, -2, 0, 0, 0, 0][index]
                look.arms = index < 5 ? .bothUp : .down
                look.feetTucked = index < 4
                look.sparkle = index % 2 == 0
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
        case open, up, left, right, blink, closed, happy, cross

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
            }
        }
    }

    enum Mouth {
        case neutral, open, smile, frown, small

        var cells: [(Int, Int)] {
            switch self {
            case .neutral: return [(5, 10), (6, 10), (7, 10)]
            case .open: return [(5, 10), (6, 10), (7, 10), (5, 11), (6, 11), (7, 11)]
            case .smile: return [(4, 10), (8, 10), (5, 11), (6, 11), (7, 11)]
            case .frown: return [(5, 10), (6, 10), (7, 10), (4, 11), (8, 11)]
            case .small: return [(6, 10)]
            }
        }
    }

    /// Tip first.
    enum Antenna {
        case up, left, drooping, bent

        var cells: [(Int, Int)] {
            switch self {
            case .up: return [(6, 0), (6, 1)]
            case .left: return [(5, 0), (6, 1)]
            case .drooping: return [(7, 0), (6, 1)]
            case .bent: return [(7, 1), (6, 1)]
            }
        }
    }

    enum Arms {
        case down, leftUp, rightUp, bothUp

        var cells: [(Int, Int)] {
            let left = [(0, 8), (0, 9)], right = [(12, 8), (12, 9)]
            let leftRaised = [(0, 4), (0, 5)], rightRaised = [(12, 4), (12, 5)]
            switch self {
            case .down: return left + right
            case .leftUp: return leftRaised + right
            case .rightUp: return left + rightRaised
            case .bothUp: return leftRaised + rightRaised
            }
        }
    }

    static let z = ["####", "..#.", ".#..", "####"]

    static func draw(_ look: Look) -> [Cell] {
        var cells: [Point: Ink] = [:]
        let ox = origin.x + look.dx, oy = origin.y + look.dy
        func put(_ x: Int, _ y: Int, _ ink: Ink) { cells[Point(x: ox + x, y: oy + y)] = ink }

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
        if look.sparkle { put(-1, 2, .white); put(13, 2, .white) }
        if let step = look.z {
            for (row, line) in z.enumerated() {
                for (x, char) in line.enumerated() where char == "#" { put(13 + x, 1 - 2 * step + row, .faint) }
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
