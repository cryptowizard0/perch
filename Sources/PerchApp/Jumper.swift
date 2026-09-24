import AppKit
import PerchAppCore
import PerchCore

/// Performs a row's jump: back to the agent's terminal, or open a URL / path.
enum Jumper {
    private static let queue = DispatchQueue(label: "dev.perch.app.jump")

    static func jump(_ link: String?) {
        switch JumpTarget(link: link) {
        case .open(let url): NSWorkspace.shared.open(url)
        case .terminal(let terminal): jump(to: terminal)
        case nil: break
        }
    }

    /// Ghostty: focus the exact terminal over AppleScript (osascript, so a slow reply or the one-time
    /// Automation prompt never blocks the UI). Other terminals, or if that fails: bring the app forward.
    static func jump(to terminal: TerminalLink) {
        queue.async {
            if terminal.app == "ghostty", osascript(GhosttyScript.focus(terminal)) != nil { return }
            DispatchQueue.main.async { activate(terminal) }
        }
    }

    private static func activate(_ terminal: TerminalLink) {
        let bundleID = terminal.bundleID ?? (terminal.app == "ghostty" ? "com.mitchellh.ghostty" : nil)
        guard let bundleID else { return }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            running.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func osascript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let error = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            NSLog("Perch: jump to Ghostty failed: \(String(decoding: error, as: UTF8.self))")
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}
