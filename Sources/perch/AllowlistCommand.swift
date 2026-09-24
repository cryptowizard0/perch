import ArgumentParser
import Foundation
import PerchCore

struct AllowlistCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "allowlist",
        abstract: "What may be approved from the notch (~/.perch/allowlist.json). Everything else: go to the terminal.",
        subcommands: [AllowlistShow.self, AllowlistCheck.self, AllowlistInit.self],
        defaultSubcommand: AllowlistShow.self
    )
}

struct AllowlistShow: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Print the rules in effect.")
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let url = PerchPaths.allowlist
        let (list, error) = Allowlist.load(from: url)
        if let error { FileHandle.standardError.write(Data("perch: \(error)\n".utf8)) }
        if json { return print(String(decoding: try list.rendered(), as: UTF8.self)) }
        let exists = FileManager.default.fileExists(atPath: url.path)
        print("\(url.path)\(exists ? "" : " (not created; defaults apply — `perch allowlist init` to edit)")")
        print("tools:           \(list.tools.joined(separator: ", "))")
        print("bash:            \(list.bash.joined(separator: " · "))")
        print("protected_paths: \(list.protectedPaths.joined(separator: ", "))")
    }
}

struct AllowlistCheck: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Would this be approvable from the notch? e.g. perch allowlist check Bash \"npm test\"",
        discussion: "The value is the tool's main input: Bash command, Read/Edit/Write file_path, WebFetch url, Glob/Grep pattern."
    )
    @Argument(help: "Tool name: Bash, Read, Edit, WebFetch, …") var tool: String
    @Argument(help: "Command, path, URL or pattern.") var value: String = ""
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let (list, error) = Allowlist.load(from: PerchPaths.allowlist)
        if let error { FileHandle.standardError.write(Data("perch: \(error)\n".utf8)) }
        let verdict = list.verdict(tool: tool, input: [PermissionPrompt.mainField(of: tool): value])
        switch verdict {
        case .notch:
            json ? print(#"{"ok":true,"verdict":"notch"}"#) : print("notch: Allow / Deny from the notch")
        case .terminal(let reason):
            if json {
                let data = try JSONSerialization.data(withJSONObject: ["ok": true, "verdict": "terminal", "reason": reason], options: [.sortedKeys])
                print(String(decoding: data, as: UTF8.self))
            } else {
                print("terminal: \(reason)")
            }
        }
    }
}

struct AllowlistInit: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "init", abstract: "Write the defaults to ~/.perch/allowlist.json to edit.")
    @Flag(help: "Overwrite an existing file.") var force = false

    func run() throws {
        let url = PerchPaths.allowlist
        if FileManager.default.fileExists(atPath: url.path) && !force {
            throw CLIError("\(url.path) exists; edit it, or pass --force to reset it to the defaults")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (try Allowlist.defaults.rendered() + Data("\n".utf8)).write(to: url, options: .atomic)
        print("wrote \(url.path)")
    }
}
