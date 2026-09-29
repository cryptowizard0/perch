import PerchAppCore
import Testing

@Suite struct PixelIconTests {
    @Test func everyIconIs12By12AndDrawsSomething() {
        for icon in PixelIcon.all {
            #expect(icon.rows.count == PixelIcon.size, "\(icon.name)")
            #expect(icon.rows.allSatisfy { $0.count == PixelIcon.size }, "\(icon.name)")
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
        #expect(!icon.isOn(x: -1, y: 0) && !icon.isOn(x: 12, y: 0) && !icon.isOn(x: 0, y: 12))
    }
}
