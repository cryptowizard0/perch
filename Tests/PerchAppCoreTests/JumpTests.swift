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
        #expect(JumpTarget.url(terminal) == nil)
    }

    @Test func openableLinks() {
        #expect(JumpTarget.url("https://github.com/x/pull/42")?.absoluteString == "https://github.com/x/pull/42")
        #expect(JumpTarget.url("zed://file/tmp/a.swift")?.scheme == "zed")
        #expect(JumpTarget.url("/Users/me/project")?.isFileURL == true)
        #expect(JumpTarget.url("~/project")?.path == NSHomeDirectory() + "/project")
        #expect(JumpTarget.url("tmux:main:2") == nil)
        #expect(JumpTarget.url("  ") == nil)
    }

    @Test func ghosttyScriptEscapes() {
        let script = GhosttyScript.focus(TerminalLink(app: "ghostty", terminalID: "T1", cwd: #"/w/a "quoted" \dir"#))
        #expect(script.contains(#"every terminal whose id is "T1""#))
        #expect(script.contains(#"every terminal whose working directory is "/w/a \"quoted\" \\dir""#))
        #expect(script.contains("focus (item 1 of matches)"))
    }
}
