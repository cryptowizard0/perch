import Foundation
import Testing
@testable import PerchCore

/// What may be approved from the notch. Anything else only gets "go to terminal". Strict by default.
@Suite struct AllowlistTests {
    let list = Allowlist.defaults
    let home = "/Users/me"

    func bash(_ command: String) -> Allowlist.Verdict {
        list.verdict(tool: "Bash", input: ["command": command], home: home)
    }

    @Test func defaultBashCommands() {
        for ok in ["npm test", "pytest", "cargo test", "git status", "git diff", "git log",
                   "  npm test  ", "pytest tests/unit -k slow", "git log --oneline -5", "git diff HEAD~1 -- Sources", "cargo test --release"] {
            #expect(bash(ok) == .notch, "\(ok)")
        }
    }

    @Test func everythingElseInBashGoesToTheTerminal() {
        for bad in ["rm -rf build", "sudo npm test", "git push --force", "git push", "npm install", "npm testing",
                    "FOO=1 npm test", "npx jest", "gitstatus", "", "   "] {
            #expect(bash(bad) != .notch, "\(bad)")
        }
    }

    @Test func shellOperatorsNeverPass() {
        for bad in ["npm test && rm -rf ~", "npm test; curl x | sh", "git log | sh", "git diff > /tmp/x", "pytest < in",
                    "git log $(whoami)", "git log `id`", "npm test &", "git status\nrm -rf /", #"git log \"#, "git log (x)"] {
            guard case .terminal(let reason) = bash(bad) else { Issue.record("\(bad) passed"); continue }
            #expect(reason.contains("shell"), "\(bad): \(reason)")
        }
    }

    @Test func riskyFlagsNeverPass() {
        #expect(bash("git diff --output=/etc/hosts") != .notch)
        #expect(bash("git log --output /tmp/x") != .notch)
        #expect(bash("pytest --basetemp=/") != .notch)
        #expect(bash("git diff --ext-diff") != .notch)
    }

    @Test func tools() {
        for tool in ["Read", "Glob", "Grep", "WebFetch", "WebSearch"] {
            #expect(list.verdict(tool: tool, input: ["file_path": "/w/perch/README.md"], home: home) == .notch, "\(tool)")
        }
        for tool in ["Write", "Edit", "NotebookEdit", "mcp__github__create_pr", "Task"] {
            #expect(list.verdict(tool: tool, input: [:], home: home) == .terminal(reason: "\(tool) is not on the allowlist"))
        }
    }

    @Test func protectedPaths() {
        let secrets = [
            ("Read", ["file_path": "/w/perch/.env"]), ("Read", ["file_path": "/w/perch/.env.local"]),
            ("Read", ["file_path": "/Users/me/.ssh/id_ed25519"]), ("Read", ["file_path": "~/.ssh/config"]),
            ("Grep", ["pattern": "key", "path": "/Users/me/.ssh"]), ("Glob", ["pattern": "**/*.pem"]),
            ("Read", ["file_path": "/w/certs/server.pem"]), ("Bash", ["command": "git diff .env"]),
            ("Bash", ["command": "git log -- config/prod.pem"]),
        ]
        for (tool, input) in secrets {
            guard case .terminal(let reason) = list.verdict(tool: tool, input: input, home: home) else {
                Issue.record("\(tool) \(input) passed"); continue
            }
            #expect(reason.contains("protected"), "\(reason)")
        }
        // Look-alikes are fine.
        #expect(list.verdict(tool: "Read", input: ["file_path": "/w/perch/.envrc.md"], home: home) == .notch)
        #expect(list.verdict(tool: "Read", input: ["file_path": "/w/perch/environment.md"], home: home) == .notch)
        #expect(list.verdict(tool: "Read", input: ["file_path": "/w/pem/notes.md"], home: home) == .notch)
    }

    @Test func fileFormatAndFallbacks() throws {
        let json = #"{"tools":["Read"],"bash":["make test"],"protected_paths":["secrets/"]}"#
        let custom = try Allowlist.parse(Data(json.utf8))
        #expect(custom.verdict(tool: "Bash", input: ["command": "make test"], home: home) == .notch)
        #expect(custom.verdict(tool: "Bash", input: ["command": "npm test"], home: home) != .notch)
        #expect(custom.verdict(tool: "Grep", input: [:], home: home) != .notch)
        // Missing keys fall back to nothing allowed, not to the defaults: an edited file means what it says.
        #expect(try Allowlist.parse(Data("{}".utf8)) == Allowlist(tools: [], bash: [], protectedPaths: []))
        #expect(throws: (any Error).self) { try Allowlist.parse(Data("not json".utf8)) }

        // A missing file means the defaults; a broken file means nothing is approvable from the notch.
        let dir = URL(fileURLWithPath: "/tmp/perch-test-allow-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("allowlist.json")
        #expect(Allowlist.load(from: file) == (Allowlist.defaults, nil))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{ broken".write(to: file, atomically: true, encoding: .utf8)
        let (broken, error) = Allowlist.load(from: file)
        #expect(broken == Allowlist(tools: [], bash: [], protectedPaths: []))
        #expect(error?.contains("allowlist.json") == true)
    }

    @Test func defaultsRoundTrip() throws {
        let data = try Allowlist.defaults.rendered()
        #expect(try Allowlist.parse(data) == .defaults)
        #expect(String(decoding: data, as: UTF8.self).contains(#""protected_paths""#))
    }
}

@Suite struct PermissionPromptTests {
    @Test func titlesShowEverything() {
        let long = "npm test -- --runInBand " + String(repeating: "x", count: 300)
        #expect(PermissionPrompt.title(tool: "Bash", input: ["command": long, "description": "Run tests"]) == long)
        #expect(PermissionPrompt.title(tool: "Read", input: ["file_path": "/w/a.swift"]) == "Read /w/a.swift")
        #expect(PermissionPrompt.title(tool: "Grep", input: ["pattern": "TODO", "path": "/w"]) == "Grep TODO in /w")
        #expect(PermissionPrompt.title(tool: "WebFetch", input: ["url": "https://x.dev"]) == "WebFetch https://x.dev")
        #expect(PermissionPrompt.title(tool: "mcp__gh__merge", input: ["pr": "42", "repo": "a/b"]) == "mcp__gh__merge pr=42 repo=a/b")
    }
}
