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
        A file recorded by `perch setup` in ~/.perch/agents.json is used first. A backup is written next to the file.
        Records the agent as connected in agents.json (`perch setup` keeps its hooks up to date).
        """
    )
    @Argument(help: "claude-code | codex | hermes") var agent: String
    @Option(help: "Settings file to edit (default: the agent's user settings).") var settings: String?
    @Option(help: "perch binary the hooks run (default: ~/.perch/bin/perch, installed by `perch setup`).") var binary: String?
    @Option(help: "Seconds a permission request waits for the notch before the terminal asks.")
    var wait: Int = Int(HookAdapter.permissionWait)
    @Flag(help: "Print the resulting settings instead of writing them.") var dryRun = false
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let target = try HookFiles.for(agent)
        let installer = Installer()
        var agents = try installer.loadAgents()
        let path = settings ?? installer.environment.configPath(for: target, recorded: agents[agent]?.config)
        let perch = binary ?? installer.environment.perchBinary.path
        guard (5...300).contains(wait) else { throw CLIError("--wait must be between 5 and 300 seconds", code: 64) }
        let old = try HookFiles.read(path)
        let text = try target.installing(old, path: path, perch: HookFiles.shellQuote(perch), wait: wait)
        if dryRun { return print(text, terminator: "") }
        if perch.contains("/.build/") {
            warn("hooks run \(perch); `swift package clean` would break them. Copy perch somewhere stable and install with --binary.")
        } else if !FileManager.default.isExecutableFile(atPath: perch) {
            warn("hooks run \(perch), which does not exist yet; `perch setup` installs it.")
        }
        try HookFiles.write(text, to: path)
        let changed = try target.perchHooks(in: old, path: path) != target.perchHooks(in: text, path: path)
        agents.turnOn(agent, config: path, hooksChanged: changed, at: Date())
        try installer.saveAgents(agents)
        if json { return printJSON(Response(ok: true)) }
        print("installed Perch hooks for \(agent) in \(path): \(target.eventNames.joined(separator: ", "))")
        if let note = target.installNote { print(note) }
    }
}

struct HooksUninstall: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Remove Perch's hooks (only Perch's) and record the agent as disconnected.")
    @Argument(help: "claude-code | codex | hermes") var agent: String
    @Option(help: "Settings file to edit (default: the agent's user settings).") var settings: String?
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let target = try HookFiles.for(agent)
        let installer = Installer()
        var agents = try installer.loadAgents()
        // Disconnecting: `perch setup` and the app leave this agent alone from now on.
        let result = try installer.disconnect(target, path: settings, recordingIn: &agents)
        try installer.saveAgents(agents)
        if json { return printJSON(Response(ok: true)) }
        let path = result.config
        if !result.existed { return print("no \(path); nothing to remove") }
        print(result.removed > 0 ? "removed \(result.removed) Perch hook\(result.removed == 1 ? "" : "s") from \(path)" : "no Perch hooks in \(path)")
    }
}

private func warn(_ message: String) {
    FileHandle.standardError.write(Data("perch: warning: \(message)\n".utf8))
}
