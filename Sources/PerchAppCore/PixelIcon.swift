import Foundation

/// A 12 pt monochrome agent icon, drawn cell by cell without antialiasing (the view picks the colour).
/// Our own drawings, no trademark files bundled. A new agent needs one more bitmap here; anything unknown gets the robot.
public struct PixelIcon: Equatable, Sendable {
    /// Points a side, whatever the grid.
    public static let size = 12

    public let name: String
    /// `grid` strings of `grid` characters: `#` lit, `.` empty. Top row first.
    public let rows: [String]

    /// Cells a side: 12 (one point each, chunky) or 24 (half a point, one Retina pixel) for shapes 12 cannot hold.
    public var grid: Int { rows.count }
    /// Points per cell.
    public var cellSize: Double { Double(Self.size) / Double(grid) }

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

    /// A woven six-loop knot around a hexagonal hole, after ChatGPT's mark (the user's call: `>_` did not read).
    /// Generated from six interlocking capsules, each passing under the next, then fixed as a bitmap.
    public static let codex = PixelIcon(name: "codex", rows: [
        "..........###...........",
        ".........#...##.........",
        "........#.....#.........",
        ".......##.....##........",
        "....##.##############...",
        "..######...##...##...#..",
        ".##...#....#.....#...##.",
        ".#...##....#......#..##.",
        ".#..###....#...####..##.",
        ".#..#.#....#..##..##.#..",
        "..###..########....##...",
        "..##.....#####......#...",
        "...#......#####.....##..",
        "...##....########..###..",
        "..#.##..##..#....#.#..#.",
        ".##..####...#....###..#.",
        ".##..#......#....##...#.",
        ".##...#.....#....#...##.",
        "..#...##...##...######..",
        "...##############.##....",
        "........##.....##.......",
        ".........#.....#........",
        ".........##...#.........",
        "...........###..........",
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
