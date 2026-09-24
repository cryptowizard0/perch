import ArgumentParser
import Foundation
import PerchClient
import PerchCore

// `perch` — the CLI. This is the ONLY contract agents and humans use; storage is a
// daemon implementation detail. Every subcommand supports `--json`: on success stdout gets
// perchd's response (`{"ok":true,…}`), on failure `{"ok":false,"error":"…"}` and a non-zero exit.

@main
struct Perch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "perch",
        abstract: "Where your agents wait. A notch-resident queue for AI agents.",
        version: PerchVersion.string,
        subcommands: [Add.self, Ls.self, Get.self, Done.self, Update.self, Respond.self, Rm.self, Watch.self, Hooks.self]
    )

    /// Like ParsableCommand.main(), but failures honour `--json` (including argument errors).
    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)  // `perch watch | …` must see each line as it happens
        let wantsJSON = CommandLine.arguments.dropFirst().contains("--json")
        do {
            var command = try parseAsRoot()
            try command.run()
        } catch let error as CLIError {
            fail(error.message, code: error.code, json: wantsJSON)
        } catch {
            let code = exitCode(for: error)
            if wantsJSON && code != .success {
                fail(message(for: error), code: code.rawValue, json: true)
            }
            exit(withError: error)
        }
    }

    static func fail(_ message: String, code: Int32, json: Bool) -> Never {
        if json {
            printJSON(Response.failure(message))
        } else {
            FileHandle.standardError.write(Data("perch: \(message)\n".utf8))
        }
        Foundation.exit(code)
    }
}

/// A failure with one human-readable line. Exit code 1 unless stated.
struct CLIError: Error {
    let message: String
    var code: Int32 = 1
    init(_ message: String, code: Int32 = 1) {
        self.message = message
        self.code = code
    }
}

// MARK: - Subcommands

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add an item. Prints its id.",
        discussion: """
        With --key, adding again updates the same item instead of creating a new one.

        With --kind request --wait, blocks until someone responds and prints the answer (exit 0).
        If the request expires (--expires), is closed or removed first, exits 3 with no answer.
        """
    )

    @Argument(help: "Title.") var title: String
    @Option(help: "task | notice | request") var kind: String = "task"
    @Option(help: "open | waiting | done | dismissed (default: waiting for requests, open otherwise)") var status: String?
    @Option(help: "Who is adding: human, claude-code, codex, hermes, …") var source: String = "human"
    @Option(help: "Due time: @15:00 (next time the clock shows it), +30m / +2h / +1d, or ISO-8601.") var due: String?
    @Option(help: "URL, file path or terminal session ref to jump back to.") var link: String?
    @Option(help: "Idempotency key; re-adding the same key updates instead of duplicating.") var key: String?
    @Option(help: "Extra data as key=value; repeatable (e.g. --meta cwd=$PWD --meta tool=Bash).") var meta: [String] = []
    @Option(help: "request only: comma-separated options (default: allow,deny).") var options: String?
    @Option(help: "Seconds until the item expires and is dismissed (notices, requests).") var expires: Int?
    @Flag(help: "request only: block until answered (prints it, exit 0) or expired / closed (exit 3).") var wait = false
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        guard let kind = ItemKind(rawValue: kind) else { throw CLIError("--kind must be task, notice or request") }
        let status = try status.map { raw -> ItemStatus in
            guard let s = ItemStatus(rawValue: raw) else { throw CLIError("--status must be open, waiting, done or dismissed") }
            return s
        } ?? (kind == .request ? .waiting : .open)
        if wait && kind != .request { throw CLIError("--wait only works with --kind request") }
        if let expires, expires <= 0 { throw CLIError("--expires must be a positive number of seconds") }
        var metaDict: [String: String] = [:]
        for pair in meta {
            guard let eq = pair.firstIndex(of: "="), eq != pair.startIndex else {
                throw CLIError("--meta expects key=value, got '\(pair)'")
            }
            metaDict[String(pair[..<eq])] = String(pair[pair.index(after: eq)...])
        }
        let now = Date()
        let item = Item(
            title: title,
            kind: kind,
            status: status,
            source: source,
            dueAt: try due.map { try parseDue($0, now: now) },
            link: link,
            meta: metaDict.isEmpty ? nil : metaDict,
            key: key,
            options: options.map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } },
            expiresAt: expires.map { now.addingTimeInterval(TimeInterval($0)) }
        )
        if wait { return try addAndWait(item) }
        let response = try call(Request(op: .add, item: item))
        json ? printJSON(response) : print(response.item?.id ?? "")
    }

    /// Exit 0 and print the answer once someone responds; exit 3 if the request expires, is closed
    /// without an answer, or is removed. A caller that gets no answer must fall back to asking in the
    /// terminal — never treat "no answer" as permission.
    func addAndWait(_ item: Item) throws {
        let stream: EventStream
        do { stream = try PerchClient().watch() } catch { throw CLIError(String(describing: error)) }
        defer { stream.close() }
        // Subscribed before adding, so the answer cannot arrive before we listen.
        var current = try call(Request(op: .add, item: item)).item!
        while current.response == nil && (current.status == .open || current.status == .waiting) {
            // perchd dismisses the request at expires_at; the slack only guards against a wedged daemon.
            let timeout = current.expiresAt.map { max($0.timeIntervalSinceNow, 0) + 5 }
            let event: Event?
            do {
                event = try stream.next(timeout: timeout)
            } catch ClientError.timeout {
                throw CLIError("request \(current.id) expired without a response", code: 3)
            } catch {
                throw CLIError(String(describing: error))
            }
            guard let event else { throw CLIError("perchd stopped while waiting for \(current.id)") }
            guard event.item.id == current.id else { continue }
            if event.type == .removed { throw CLIError("request \(current.id) was removed without a response", code: 3) }
            current = event.item
        }
        guard let answer = current.response else {
            let why = current.status == .dismissed ? "expired" : "was closed"
            throw CLIError("request \(current.id) \(why) without a response", code: 3)
        }
        json ? printJSON(Response(ok: true, item: current)) : print(answer)
    }

    func parseDue(_ text: String, now: Date) throws -> Date {
        do {
            return try DueParser.parse(text, now: now)
        } catch {
            throw CLIError(String(describing: error))
        }
    }
}

struct Ls: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List items in queue order.",
        discussion: "Shows open and waiting items unless --status or --all is given."
    )
    @Option(help: "Filter by status: open | waiting | done | dismissed.") var status: String?
    @Option(help: "Filter by source.") var source: String?
    @Option(help: "Filter by kind: task | notice | request.") var kind: String?
    @Flag(help: "Include done and dismissed items.") var all = false
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        var filter = Request.Filter(source: source, all: all ? true : nil)
        if let status {
            guard let s = ItemStatus(rawValue: status) else { throw CLIError("--status must be open, waiting, done or dismissed") }
            filter.status = s
        }
        if let kind {
            guard let k = ItemKind(rawValue: kind) else { throw CLIError("--kind must be task, notice or request") }
            filter.kind = k
        }
        let response = try call(Request(op: .list, filter: filter))
        if json { return printJSON(response) }
        let items = response.items ?? []
        if items.isEmpty {
            FileHandle.standardError.write(Data("nothing here\n".utf8))
        }
        let sourceWidth = items.map(\.source.count).max() ?? 0
        for item in items {
            print(Format.row(item, sourceWidth: sourceWidth))
        }
    }
}

struct Get: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show one item.")
    @Argument var id: String
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let response = try call(Request(op: .get, id: id))
        if json { return printJSON(response) }
        if let item = response.item { print(Format.details(item)) }
    }
}

struct Done: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Mark an item done.")
    @Argument var id: String
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let response = try call(Request(op: .done, id: id))
        if json { return printJSON(response) }
        if let item = response.item { print("done \(item.id)  \(item.title)") }
    }
}

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Change an item's title, kind or due time.",
        discussion: """
        Snooze: perch update <id> --due +30m. Keep a notice as a task: perch update <id> --kind task
        (it stops expiring). Requests keep their kind.
        """
    )
    @Argument var id: String
    @Option(help: "New title.") var title: String?
    @Option(help: "task | notice") var kind: String?
    @Option(help: "Due time: @15:00, +30m / +2h / +1d, or ISO-8601.") var due: String?
    @Flag(help: "Remove the due time.") var noDue = false
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        if title == nil && kind == nil && due == nil && !noDue {
            throw CLIError("give at least one of --title, --kind, --due, --no-due", code: 64)
        }
        if due != nil && noDue { throw CLIError("--due and --no-due cannot be combined", code: 64) }
        let newKind = try kind.map { raw -> ItemKind in
            guard let k = ItemKind(rawValue: raw), k != .request else { throw CLIError("--kind must be task or notice") }
            return k
        }
        let patch = Request.Patch(
            title: title,
            kind: newKind,
            dueAt: try due.map { raw in
                do { return try DueParser.parse(raw, now: Date()) } catch { throw CLIError(String(describing: error)) }
            },
            clearDue: noDue ? true : nil
        )
        let response = try call(Request(op: .update, id: id, patch: patch))
        if json { return printJSON(response) }
        if let item = response.item { print("updated \(item.id)  \(item.title)") }
    }
}

struct Respond: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Respond to a request (e.g. allow / deny).")
    @Argument var id: String
    @Argument var value: String
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let response = try call(Request(op: .respond, id: id, value: value))
        if json { return printJSON(response) }
        if let item = response.item { print("\(item.id) → \(item.response ?? value)") }
    }
}

struct Rm: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Remove an item.")
    @Argument var id: String
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let response = try call(Request(op: .remove, id: id))
        if json { return printJSON(response) }
        if let item = response.item { print("removed \(item.id)  \(item.title)") }
    }
}

struct Watch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stream events as they happen (with --json: one event object per line)."
    )
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let stream: EventStream
        do { stream = try PerchClient().watch() } catch { throw CLIError(String(describing: error)) }
        while true {
            let event: Event?
            do { event = try stream.next() } catch { throw CLIError(String(describing: error)) }
            guard let event else { throw CLIError("perchd stopped") }
            if json {
                printJSON(event)
            } else {
                print(Format.event(event))
            }
        }
    }
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
    @Flag(help: "Print JSON.") var json = false
    func run() throws { throw CLIError("perch hooks install is not implemented yet (milestone M3)") }
}

struct HooksUninstall: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Remove hooks for an agent.")
    @Argument(help: "claude-code | codex") var agent: String
    @Flag(help: "Print JSON.") var json = false
    func run() throws { throw CLIError("perch hooks uninstall is not implemented yet (milestone M3)") }
}

// MARK: - Helpers

/// One round trip to perchd; `ok:false` becomes a CLIError carrying perchd's message.
func call(_ request: Request, timeout: TimeInterval = 10) throws -> Response {
    let response: Response
    do {
        response = try PerchClient().send(request, timeout: timeout)
    } catch {
        throw CLIError(String(describing: error))
    }
    guard response.ok else { throw CLIError(response.error ?? "perchd returned an error") }
    return response
}

func printJSON<T: Encodable>(_ value: T) {
    let data = (try? PerchJSON.encoder.encode(value)) ?? Data(#"{"ok":false,"error":"cannot encode output"}"#.utf8)
    print(String(decoding: data, as: UTF8.self))
}
