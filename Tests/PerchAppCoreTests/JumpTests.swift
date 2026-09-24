import Foundation
import PerchCore
import Testing
@testable import PerchAppCore

@Suite struct JumpTests {
    @Test func targets() {
        let terminal = "perch-terminal://ghostty?id=T1&cwd=/w/perch"
        #expect(JumpTarget(link: terminal) == .terminal(TerminalLink(app: "ghostty", terminalID: "T1", cwd: "/w/perch")))
        #expect(JumpTarget(link: "https://x/pr/1") == .open(URL(string: "https://x/pr/1")!))
        #expect(JumpTarget(link: "/tmp") == .open(URL(fileURLWithPath: "/tmp")))
        #expect(JumpTarget(link: "tmux:main") == nil)
        #expect(JumpTarget(link: nil) == nil)
        // NSWorkspace cannot open our own scheme; only JumpTarget handles it.
        #expect(RowFormat.linkURL(terminal) == nil)
    }

    @Test func ghosttyScriptEscapes() {
        let script = GhosttyScript.focus(TerminalLink(app: "ghostty", terminalID: "T1", cwd: #"/w/a "quoted" \dir"#))
        #expect(script.contains(#"every terminal whose id is "T1""#))
        #expect(script.contains(#"every terminal whose working directory is "/w/a \"quoted\" \\dir""#))
        #expect(script.contains("focus (item 1 of matches)"))
    }
}
