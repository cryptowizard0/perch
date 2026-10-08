import PerchAppCore
import Testing

@Suite struct PixelIconTests {
    /// 12 or 24 cells a side in the same 12 pt square: a 24-cell icon is one Retina pixel per cell.
    @Test func everyIconIsASquareGridAndDrawsSomething() {
        for icon in PixelIcon.all {
            #expect([12, 24].contains(icon.grid), "\(icon.name)")
            #expect(icon.rows.count == icon.grid, "\(icon.name)")
            #expect(icon.rows.allSatisfy { $0.count == icon.grid }, "\(icon.name)")
            #expect(icon.cellSize * Double(icon.grid) == Double(PixelIcon.size), "\(icon.name)")
            #expect(icon.rows.allSatisfy { $0.allSatisfy { $0 == "#" || $0 == "." } }, "\(icon.name)")
            #expect(!icon.cells.isEmpty, "\(icon.name)")
        }
        #expect(Set(PixelIcon.all.map(\.rows)).count == PixelIcon.all.count)
    }

    @Test func agentsGetTheirIconUnknownGetsTheRobot() {
        #expect(PixelIcon.for(agent: "claude-code") == .claudeCode)
        #expect(PixelIcon.for(agent: "claude") == .claudeCode)
        #expect(PixelIcon.for(agent: "codex") == .codex)
        #expect(PixelIcon.for(agent: "hermes") == .hermes)
        #expect(PixelIcon.for(agent: "unknown") == .robot)
        #expect(PixelIcon.for(agent: "aider") == .robot)
    }

    @Test func cellsAreTheLitSquares() {
        let icon = PixelIcon.codex
        for (y, row) in icon.rows.enumerated() {
            for (x, char) in row.enumerated() {
                #expect(icon.isOn(x: x, y: y) == (char == "#"))
            }
        }
        #expect(icon.cells.count == icon.rows.joined().filter { $0 == "#" }.count)
        #expect(!icon.isOn(x: -1, y: 0) && !icon.isOn(x: icon.grid, y: 0) && !icon.isOn(x: 0, y: icon.grid))
    }

    /// The ChatGPT-like knot needs the finer grid; the others stay chunky.
    @Test func codexIsTheFineOne() {
        #expect(PixelIcon.codex.grid == 24 && PixelIcon.codex.cellSize == 0.5)
        #expect(PixelIcon.claudeCode.grid == 12 && PixelIcon.claudeCode.cellSize == 1)
    }
}
