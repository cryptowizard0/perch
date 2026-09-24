import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// Runs the built `perch` binary (next to the test bundle) against an in-process perchd.
struct CLI {
    /// swift-testing runs inside swiftpm-testing-helper, so find the products dir from `--test-bundle-path`
    /// (…/debug/perchPackageTests.xctest/Contents/MacOS/…), falling back to `.build/debug` in the package.
    static let binary: URL? = {
        var candidates: [URL] = []
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--test-bundle-path"), i + 1 < args.count {
            var url = URL(fileURLWithPath: args[i + 1])
            while url.path != "/" && url.pathExtension != "xctest" { url.deleteLastPathComponent() }
            candidates.append(url.deletingLastPathComponent().appendingPathComponent("perch"))
        }
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(packageRoot.appendingPathComponent(".build/debug/perch"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }()

    let home: URL

    /// macOS scans a freshly linked binary on its first launch (~1 s); run it once before timing anything.
    static func warmUp() throws {
        try CLI(home: URL(fileURLWithPath: "/tmp")).run("--version")
    }

    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
        var json: Response { try! PerchJSON.decoder.decode(Response.self, from: Data(stdout.utf8)) }
    }

    @discardableResult
    func run(_ args: String...) throws -> Result {
        try run(args)
    }

    func run(_ args: [String]) throws -> Result {
        try start(args)()
    }

    /// Starts `perch` in the background; call the returned closure to wait for it.
    func start(_ args: [String]) throws -> () throws -> Result {
        let process = Process()
        process.executableURL = Self.binary!
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment.merging(["PERCH_HOME": home.path]) { $1 }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        return {
            let stdout = out.fileHandleForReading.readDataToEndOfFile()
            let stderr = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Result(status: process.terminationStatus,
                          stdout: String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .newlines),
                          stderr: String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .newlines))
        }
    }
}

@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct CLITests {

    @Test func clearErrorWhenDaemonIsNotRunning() throws {
        let cli = CLI(home: URL(fileURLWithPath: "/tmp/perch-test-nodaemon"))
        let plain = try cli.run("ls")
        #expect(plain.status == 1)
        #expect(plain.stdout.isEmpty)
        #expect(plain.stderr.hasPrefix("perch: perchd is not running"))
        #expect(!plain.stderr.contains("\n"))

        let json = try cli.run("ls", "--json")
        #expect(json.status == 1)
        #expect(json.json.ok == false)
        #expect(json.json.error?.hasPrefix("perchd is not running") == true)
    }

    @Test func addPrintsIdAndLsShowsIt() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let id = try cli.run("add", "review PR #42", "--source", "codex", "--link", "https://x/pr/42").stdout
        #expect(id.count == 4)
        let listed = try cli.run("ls", "--json").json.items ?? []
        #expect(listed.map(\.id) == [id])
        #expect(listed.first?.link == "https://x/pr/42")
        #expect(try cli.run("ls").stdout.contains("review PR #42"))
    }

    @Test func everySubcommandHasJSON() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let added = try cli.run("add", "npm test", "--kind", "request", "--meta", "cwd=/tmp", "--json").json
        let id = try #require(added.item?.id)
        #expect(added.item?.status == .waiting)
        #expect(added.item?.meta == ["cwd": "/tmp"])
        #expect(try cli.run("get", id, "--json").json.item == added.item)
        #expect(try cli.run("respond", id, "allow", "--json").json.item?.response == "allow")
        let task = try #require(try cli.run("add", "t", "--json").json.item)
        #expect(try cli.run("done", task.id, "--json").json.item?.status == .done)
        #expect(try cli.run("rm", task.id, "--json").json.ok)
        #expect(try cli.run("ls", "--all", "--json").json.items?.map(\.id) == [id])
    }

    @Test func failuresAreJSONWithNonZeroExit() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let unknown = try cli.run("done", "zzzz", "--json")
        #expect(unknown.status != 0)
        #expect(unknown.stdout == #"{"error":"no item with id 'zzzz'","ok":false}"#)
        let badKind = try cli.run("add", "x", "--kind", "bogus", "--json")
        #expect(badKind.status != 0)
        #expect(badKind.json.error == "--kind must be task, notice or request")
        let missingArg = try cli.run("respond", "--json")
        #expect(missingArg.status != 0)
        #expect(missingArg.json.ok == false)
    }

    @Test func repeatedKeyDoesNotDuplicate() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let first = try cli.run("add", "needs permission", "--status", "waiting", "--key", "session-1").stdout
        let second = try cli.run("add", "needs input", "--status", "waiting", "--key", "session-1").stdout
        #expect(first == second)
        #expect(try cli.run("ls", "--json").json.items?.map(\.title) == ["needs input"])
    }

    @Test func dueSyntax() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let before = Date()
        let relative = try #require(try cli.run("add", "in half an hour", "--due", "+30m", "--json").json.item?.dueAt)
        #expect(abs(relative.timeIntervalSince(before) - 1800) < 5)
        let clock = try #require(try cli.run("add", "at three", "--due", "@15:00", "--json").json.item?.dueAt)
        #expect(Calendar.current.component(.hour, from: clock) == 15)
        #expect(clock > before && clock.timeIntervalSince(before) <= 86_400)
        let bad = try cli.run("add", "x", "--due", "soon")
        #expect(bad.status == 1)
        #expect(bad.stderr == "perch: invalid due 'soon': use @15:00, +30m or an ISO-8601 time")
    }

    @Test func waitPrintsTheAnswer() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let finish = try cli.start(["add", "npm test", "--kind", "request", "--source", "claude-code", "--wait", "--expires", "20"])
        let request = try waitForItem(d)
        #expect(request.status == .waiting)
        _ = try d.client.send(Request(op: .respond, id: request.id, value: "allow"))
        let result = try finish()
        #expect(result.status == 0)
        #expect(result.stdout == "allow")
    }

    @Test func waitWithJSONPrintsTheAnsweredItem() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let finish = try cli.start(["add", "rm -rf build", "--kind", "request", "--wait", "--json"])
        let request = try waitForItem(d)
        _ = try d.client.send(Request(op: .respond, id: request.id, value: "deny"))
        let result = try finish()
        #expect(result.status == 0)
        #expect(result.json.item?.response == "deny")
    }

    @Test func waitExitsThreeWhenTheRequestExpires() throws {
        let d = try TestDaemon()
        let started = Date()
        let result = try CLI(home: d.home).run("add", "nobody home", "--kind", "request", "--wait", "--expires", "1")
        #expect(result.status == 3)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.hasSuffix("expired without a response"))
        #expect(Date().timeIntervalSince(started) < 4)
    }

    @Test func waitExitsThreeWhenClosedOrRemoved() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let closed = try cli.start(["add", "a", "--kind", "request", "--wait"])
        _ = try d.client.send(Request(op: .done, id: try waitForItem(d).id))
        #expect(try closed().status == 3)

        let removed = try cli.start(["add", "b", "--kind", "request", "--wait", "--json"])
        _ = try d.client.send(Request(op: .remove, id: try waitForItem(d).id))
        let result = try removed()
        #expect(result.status == 3)
        #expect(result.json.error?.hasSuffix("was removed without a response") == true)
    }

    @Test func waitRequiresARequest() throws {
        let d = try TestDaemon()
        let result = try CLI(home: d.home).run("add", "x", "--wait")
        #expect(result.status == 1)
        #expect(result.stderr == "perch: --wait only works with --kind request")
    }

    /// Polls until exactly one active item exists (the one the background `perch` just added).
    private func waitForItem(_ d: TestDaemon) throws -> Item {
        for _ in 0..<200 {
            if let item = try d.client.send(Request(op: .list)).items?.first { return item }
            Thread.sleep(forTimeInterval: 0.02)
        }
        throw CLIError("background perch never added its item")
    }
}

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct UpdateCLITests {
    @Test func snoozeRetitleAndPromote() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let id = try cli.run("add", "codex finished", "--kind", "notice", "--expires", "300").stdout
        let before = Date()
        let snoozed = try cli.run("update", id, "--due", "+30m", "--kind", "task", "--title", "follow up", "--json").json.item
        #expect(snoozed?.kind == .task)
        #expect(snoozed?.title == "follow up")
        #expect(snoozed?.expiresAt == nil)
        #expect(abs((snoozed?.dueAt ?? .distantPast).timeIntervalSince(before) - 1800) < 5)

        let plain = try cli.run("update", id, "--no-due")
        #expect(plain.status == 0)
        #expect(plain.stdout == "updated \(id)  follow up")
        #expect(try cli.run("get", id, "--json").json.item?.dueAt == nil)
    }

    @Test func errors() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let id = try cli.run("add", "t").stdout
        let nothing = try cli.run("update", id)
        #expect(nothing.status == 64)
        #expect(nothing.stderr == "perch: give at least one of --title, --kind, --due, --no-due")
        #expect(try cli.run("update", id, "--due", "+1h", "--no-due", "--json").json.error
                == "--due and --no-due cannot be combined")
        #expect(try cli.run("update", id, "--kind", "bogus").stderr == "perch: --kind must be task or notice")
        #expect(try cli.run("update", "zzzz", "--title", "x", "--json").json.error == "no item with id 'zzzz'")
    }
}
