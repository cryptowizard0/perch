import ArgumentParser
import Foundation
import PerchClient
import PerchCore

/// `perch hook <agent>` — the hook adapter. Claude Code runs it with the hook JSON on stdin (see HookAdapter).
/// Contract with the agent: print nothing (SessionStart / UserPromptSubmit stdout would be added to the
/// model's context), always exit 0, never block for long. Failures go to ~/.perch/hook.log.
struct Hook: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Hook adapter: reads an agent's hook JSON on stdin and reports to perchd. Prints nothing, exits 0.",
        discussion: "Installed by `perch hooks install`. Agents: \(Hook.agents.joined(separator: ", "))."
    )
    static let agents = ["claude-code", "codex"]

    @Argument(help: "claude-code | codex") var agent: String

    func run() {
        let now = Date()
        guard Self.agents.contains(agent) else { return HookLog.write("unknown agent '\(agent)'") }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let input: HookInput
        do {
            input = try JSONDecoder().decode(HookInput.self, from: data)
        } catch {
            return HookLog.write("unreadable \(agent) hook input: \(error)")
        }
        let client = PerchClient()
        let link = terminalLink(for: input, client: client)
        for request in HookAdapter.requests(for: input, agent: agent, link: link, now: now) {
            do {
                let response = try client.send(request, timeout: 2)
                // Resolving a waiting item that is not there is the normal case.
                if !response.ok, request.op != .done {
                    HookLog.write("\(input.event) \(request.op.rawValue): \(response.error ?? "failed")")
                }
            } catch {
                HookLog.write("\(input.event): \(error)")
                if case ClientError.daemonNotRunning = error { return }
            }
        }
    }

    /// Where "jump back" goes. Captured when the human submits a prompt (that terminal has focus right then);
    /// later events reuse the session's link, since by then focus may be anywhere.
    func terminalLink(for input: HookInput, client: PerchClient) -> String? {
        let env = ProcessInfo.processInfo.environment
        let program = env["TERM_PROGRAM"].flatMap { $0.isEmpty ? nil : $0.lowercased() }
        let bundle = env["__CFBundleIdentifier"].flatMap { $0.isEmpty ? nil : $0 }
        guard program != nil || bundle != nil else { return nil }
        var link = TerminalLink(app: program ?? "app", cwd: input.cwd, bundleID: bundle)
        if input.event == "UserPromptSubmit" {
            if link.app == "ghostty" { link.terminalID = Ghostty.focusedTerminal(near: input.cwd) }
            return link.string
        }
        let sessions = (try? client.send(Request(op: .sessions), timeout: 2))?.sessions ?? []
        return sessions.first { $0.id == input.sessionID }?.link ?? link.string
    }
}

/// Ghostty ≥ 1.3 is scriptable: ask which terminal (tab / split) has focus.
enum Ghostty {
    static func focusedTerminal(near cwd: String?) -> String? {
        let script = """
        tell application "Ghostty"
            if not frontmost then return ""
            set t to focused terminal of selected tab of front window
            return (id of t) & linefeed & (working directory of t)
        end tell
        """
        guard let output = osascript(script, timeout: 3) else { return nil }
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let id = lines.first, !id.isEmpty else { return nil }
        // A shell cd'd elsewhere is fine; a terminal in an unrelated directory means focus already moved on.
        if let cwd, lines.count > 1, !lines[1].isEmpty {
            let wd = lines[1]
            guard cwd == wd || cwd.hasPrefix(wd + "/") || wd.hasPrefix(cwd + "/") else { return nil }
        }
        return id
    }

    static func osascript(_ script: String, timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
    }
}

/// Hooks must stay silent, so their failures are appended here (kept under 256 KB).
enum HookLog {
    static func write(_ message: String) {
        let url = PerchPaths.hookLog
        let limit = 256 * 1024
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > limit {
            try? FileManager.default.removeItem(at: url)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? handle.write(contentsOf: Data("\(stamp) \(message)\n".utf8))
    }
}
