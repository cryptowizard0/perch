import ArgumentParser
import Foundation
import PerchCore
import PerchSetup

struct Hooks: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install or remove agent hook adapters.",
        subcommands: [HooksInstall.self, HooksUninstall.self]
    )
}

struct HooksInstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Add Perch's hooks to an agent's settings (other hooks are kept).",
        discussion: """
        claude-code: ~/.claude/settings.json ($CLAUDE_CONFIG_DIR/settings.json if set).
        codex: ~/.codex/hooks.json ($CODEX_HOME/hooks.json if set); Codex runs them only after you trust them in /hooks.
        hermes: ~/.hermes/config.yaml ($HERMES_HOME/config.yaml if set); Hermes asks once before running them.
        A backup is written next to the file.
        """
    )
    @Argument(help: "claude-code | codex | hermes") var agent: String
    @Option(help: "Settings file to edit (default: the agent's user settings).") var settings: String?
    @Option(help: "perch binary the hooks run (default: this one).") var binary: String?
    @Option(help: "Seconds a permission request waits for the notch before the terminal asks.")
    var wait: Int = Int(HookAdapter.permissionWait)
    @Flag(help: "Print the resulting settings instead of writing them.") var dryRun = false
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let target = try HookFiles.for(agent)
        let path = settings ?? target.defaultPath
        let perch = try binary ?? HookFiles.currentBinary()
        guard (5...300).contains(wait) else { throw CLIError("--wait must be between 5 and 300 seconds", code: 64) }
        let text = try target.installing(HookFiles.read(path), path: path, perch: HookFiles.shellQuote(perch), wait: wait)
        if dryRun { return print(text, terminator: "") }
        if perch.contains("/.build/") {
            FileHandle.standardError.write(Data("perch: warning: hooks run \(perch); `swift package clean` would break them. Copy perch somewhere stable and install with --binary.\n".utf8))
        }
        try HookFiles.write(text, to: path)
        if json { return printJSON(Response(ok: true)) }
        print("installed Perch hooks for \(agent) in \(path): \(target.eventNames.joined(separator: ", "))")
        if let note = target.installNote { print(note) }
    }
}

struct HooksUninstall: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Remove Perch's hooks (only Perch's).")
    @Argument(help: "claude-code | codex | hermes") var agent: String
    @Option(help: "Settings file to edit (default: the agent's user settings).") var settings: String?
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let target = try HookFiles.for(agent)
        let path = settings ?? target.defaultPath
        guard let text = try HookFiles.read(path) else {
            return json ? printJSON(Response(ok: true)) : print("no \(path); nothing to remove")
        }
        let (kept, removed) = try target.removing(text, path: path)
        if removed > 0 { try HookFiles.write(kept, to: path) }
        if json { return printJSON(Response(ok: true)) }
        print(removed > 0 ? "removed \(removed) Perch hook\(removed == 1 ? "" : "s") from \(path)" : "no Perch hooks in \(path)")
    }
}

