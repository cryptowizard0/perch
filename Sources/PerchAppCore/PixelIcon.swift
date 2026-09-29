import Foundation

/// A 12×12 monochrome agent icon, drawn cell by cell without antialiasing (the view picks the colour).
/// Our own drawings of an idea, not traced logos, and no trademark files are bundled.
/// A new agent needs one more bitmap here; anything unknown gets the robot.
public struct PixelIcon: Equatable, Sendable {
    public static let size = 12

    public let name: String
    /// `size` strings of `size` characters: `#` lit, `.` empty. Top row first.
    public let rows: [String]

    public init(name: String, rows: [String]) {
        self.name = name
        self.rows = rows
    }

    public func isOn(x: Int, y: Int) -> Bool {
        guard rows.indices.contains(y) else { return false }
        let row = Array(rows[y])
        return row.indices.contains(x) && row[x] == "#"
    }

    /// Lit cells as (x, y), row by row.
    public var cells: [(x: Int, y: Int)] {
        rows.enumerated().flatMap { y, row in
            row.enumerated().compactMap { x, char in char == "#" ? (x, y) : nil }
        }
    }

    public static func `for`(agent source: String) -> PixelIcon {
        switch source {
        case "claude-code", "claude": return .claudeCode
        case "codex": return .codex
        case "hermes": return .hermes
        default: return .robot
        }
    }

    public static let all: [PixelIcon] = [.claudeCode, .codex, .hermes, .robot]

    /// A blocky little monster.
    public static let claudeCode = PixelIcon(name: "claude-code", rows: [
        "............",
        "..########..",
        "..########..",
        "..#..##..#..",
        "..#..##..#..",
        "############",
        "############",
        "..########..",
        "..########..",
        "..#.#..#.#..",
        "..#.#..#.#..",
        "............",
    ])

    /// A prompt: `>_`.
    public static let codex = PixelIcon(name: "codex", rows: [
        "............",
        "............",
        "##..........",
        ".##.........",
        "..##........",
        "...##.......",
        "..##........",
        ".##.........",
        "##....######",
        "......######",
        "............",
        "............",
    ])

    /// A pair of wings.
    public static let hermes = PixelIcon(name: "hermes", rows: [
        "............",
        "##........##",
        "###......###",
        ".###....###.",
        "####....####",
        ".####..####.",
        "..########..",
        "...######...",
        "....####....",
        ".....##.....",
        "............",
        "............",
    ])

    /// Any other agent.
    public static let robot = PixelIcon(name: "robot", rows: [
        ".....##.....",
        ".....##.....",
        ".##########.",
        ".#........#.",
        ".#.##..##.#.",
        ".#.##..##.#.",
        ".#........#.",
        ".#..####..#.",
        ".#........#.",
        ".##########.",
        "..##....##..",
        "............",
    ])
}
