import ArgumentParser
import Foundation
import PerchCore

// `perch` — the CLI. This is the ONLY contract agents and humans use; storage is a
// daemon implementation detail. Every subcommand supports `--json`.
// Milestone 1 wires these commands to perchd over the Unix socket.

@main
struct Perch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "perch",
        abstract: "Where your agents wait. A notch-resident queue for AI agents.",
        version: PerchVersion.string,
        subcommands: [Add.self, Ls.self, Done.self, Respond.self, Rm.self, Watch.self, Hooks.self]
    )
}

struct NotImplemented: Error, CustomStringConvertible {
    let what: String
    var description: String { "\(what) is not implemented yet — see docs/MILESTONES.md" }
}

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Add an item.")

    @Argument(help: "Title.") var title: String
    @Option(help: "task | notice | request") var kind: String = "task"
    @Option(help: "open | waiting | done | dismissed") var status: String = "open"
    @Option(help: "Who is adding: human, claude-code, codex, hermes, …") var source: String = "human"
    @Option(help: "Due time: @15:00 or +30m") var due: String?
    @Option(help: "URL, file path or terminal session ref to jump back to.") var link: String?
    @Option(help: "Idempotency key; re-adding the same key updates instead of duplicating.") var key: String?
    @Option(help: "request only: comma-separated options, e.g. allow,deny") var options: String?
    @Option(help: "request only: seconds until the request expires.") var expires: Int?
    @Flag(help: "request only: block until responded or expired, then print the response.") var wait = false
    @Flag(help: "Print JSON.") var json = false

    func validate() throws {
        guard ItemKind(rawValue: kind) != nil else { throw ValidationError("kind must be task, notice or request") }
        guard ItemStatus(rawValue: status) != nil else { throw ValidationError("status must be open, waiting, done or dismissed") }
    }

    func run() throws { throw NotImplemented(what: "perch add") }
}

struct Ls: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List items.")
    @Option(help: "Filter by status.") var status: String?
    @Option(help: "Filter by source.") var source: String?
    @Flag(help: "Print JSON.") var json = false
    func run() throws { throw NotImplemented(what: "perch ls") }
}

struct Done: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Mark an item done.")
    @Argument var id: String
    @Flag(help: "Print JSON.") var json = false
    func run() throws { throw NotImplemented(what: "perch done") }
}

struct Respond: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Respond to a request (e.g. allow / deny).")
    @Argument var id: String
    @Argument var value: String
    @Flag(help: "Print JSON.") var json = false
    func run() throws { throw NotImplemented(what: "perch respond") }
}

struct Rm: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Remove an item.")
    @Argument var id: String
    @Flag(help: "Print JSON.") var json = false
    func run() throws { throw NotImplemented(what: "perch rm") }
}

struct Watch: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stream events (one JSON object per line).")
    @Flag(help: "Print JSON.") var json = false
    func run() throws { throw NotImplemented(what: "perch watch") }
}

struct Hooks: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install or remove agent hook adapters.",
        subcommands: [HooksInstall.self, HooksUninstall.self]
    )
}

struct HooksInstall: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install", abstract: "Install hooks for an agent.")
    @Argument(help: "claude-code | codex") var agent: String
    func run() throws { throw NotImplemented(what: "perch hooks install") }
}

struct HooksUninstall: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Remove hooks for an agent.")
    @Argument(help: "claude-code | codex") var agent: String
    func run() throws { throw NotImplemented(what: "perch hooks uninstall") }
}
