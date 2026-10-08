import Foundation
import Testing
@testable import PerchCore

/// Claude Code sends no hook when you answer No at its permission prompt or press Esc there (#8); its transcript
/// is the only place the end of that turn shows up.
@Suite struct ClaudeTranscriptTests {
    /// Shaped like a real transcript (2.1.258): one JSON object per line, newest last.
    func line(_ type: String, at time: String, _ content: String? = nil, extra: String = "") -> String {
        let message = content.map { #","message":{"role":"\#(type)","content":\#($0)}"# } ?? ""
        return #"{"type":"\#(type)","timestamp":"2026-10-08T03:\#(time)Z","sessionId":"s1"\#(message)\#(extra)}"#
    }
    var prompt: String { line("user", at: "26:43.100", #""Run rm -rf /tmp/perch-m8/nothing""#) }
    var toolUse: String { line("assistant", at: "26:55.297", #"[{"type":"tool_use","name":"Bash","input":{"command":"rm -rf x"}}]"#) }
    var rejected: String {
        line("user", at: "27:00.697", #"[{"type":"tool_result","content":"The user doesn't want to proceed with this tool use.","is_error":true}]"#)
    }
    var marker: String { line("user", at: "27:00.700", #"[{"type":"text","text":"[Request interrupted by user for tool use]"}]"#) }
    var turnEnd: String { line("system", at: "27:00.704", extra: #","subtype":"turn_duration","durationMs":11452"#) }

    func at(_ time: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: "2026-10-08T03:\(time)Z")!
    }

    @Test func noAtThePermissionPrompt() {
        let tail = [prompt, toolUse, rejected, marker, turnEnd].joined(separator: "\n") + "\n"
        #expect(ClaudeTranscript.interruption(tail: tail) == at("27:00.700"))
    }

    @Test func escWhileRunningSaysItWithoutForToolUse() {
        let esc = line("user", at: "30:00.000", #"[{"type":"text","text":"[Request interrupted by user]"}]"#)
        #expect(ClaudeTranscript.interruption(tail: [prompt, esc].joined(separator: "\n")) == at("30:00.000"))
        // Some versions write the content as a plain string.
        let plain = line("user", at: "30:01.000", #""[Request interrupted by user]""#)
        #expect(ClaudeTranscript.interruption(tail: plain) == at("30:01.000"))
    }

    @Test func aTurnThatEndedNormallyIsNotAnInterruption() {
        let reply = line("assistant", at: "28:00.000", #"[{"type":"text","text":"Done."}]"#)
        let end = line("system", at: "28:00.010", extra: #","subtype":"turn_duration""#)
        #expect(ClaudeTranscript.interruption(tail: [prompt, reply, end].joined(separator: "\n")) == nil)
        // A tool still running, or waiting for an answer: not over.
        #expect(ClaudeTranscript.interruption(tail: [prompt, toolUse].joined(separator: "\n")) == nil)
    }

    @Test func anOldInterruptionFollowedByANewPromptIsHistory() {
        let next = line("user", at: "31:00.000", #""and now something else""#)
        let tail = [marker, turnEnd, line("file-history-snapshot", at: "31:00.000"), next].joined(separator: "\n")
        #expect(ClaudeTranscript.interruption(tail: tail) == nil)
    }

    @Test func metaEntriesAndACutFirstLineAreSkipped() {
        let meta = line("user", at: "27:01.000", #""<local-command-caveat>…</local-command-caveat>""#, extra: #","isMeta":true"#)
        let cut = String(toolUse.dropFirst(25))  // the tail starts mid-line
        let tail = [cut, rejected, marker, turnEnd, meta, line("attachment", at: "27:02.000")].joined(separator: "\n")
        #expect(ClaudeTranscript.interruption(tail: tail) == at("27:00.700"))
        #expect(ClaudeTranscript.interruption(tail: "") == nil)
        #expect(ClaudeTranscript.interruption(tail: "not json\n{\"type\":") == nil)
    }
}
