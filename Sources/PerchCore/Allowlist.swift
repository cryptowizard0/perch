import Foundation

/// Which permission requests may be approved from the notch (`~/.perch/allowlist.json`). Everything else only
/// gets "go to terminal". Strict on purpose: approving `rm -rf` from a few hundred pixels is how accidents happen.
///
/// - `tools`: approvable whatever their input (paths are still checked against `protected_paths`)
/// - `bash`: approvable commands; arguments may follow (`pytest tests/unit`), but never shell operators
///   (`; & | $ \` > < ( ) \ newline`) or the flags in `riskyFlags`
/// - `protected_paths`: any tool input touching these goes to the terminal: a name (`.env`, also matches `.env.local`),
///   a `~/` prefix (`~/.ssh`), or a `*.ext` suffix (`*.pem`)
public struct Allowlist: Codable, Equatable, Sendable {
    public var tools: [String]
    public var bash: [String]
    public var protectedPaths: [String]

    public init(tools: [String], bash: [String], protectedPaths: [String]) {
        self.tools = tools
        self.bash = bash
        self.protectedPaths = protectedPaths
    }

    public static let defaults = Allowlist(
        tools: ["Read", "Glob", "Grep", "WebFetch", "WebSearch"],
        bash: ["npm test", "pytest", "cargo test", "git status", "git diff", "git log"],
        protectedPaths: [".env", "~/.ssh", "*.pem"]
    )

    /// Flags that turn a harmless command into one that writes or runs something else.
    public static let riskyFlags = ["--output", "--basetemp", "--ext-diff", "--exec", "--upload-pack"]
    static let shellOperators = Set(";&|$`><()\\\n\r")

    enum CodingKeys: String, CodingKey {
        case tools, bash
        case protectedPaths = "protected_paths"
    }

    /// Missing keys mean "nothing": an edited file means exactly what it says.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tools = try c.decodeIfPresent([String].self, forKey: .tools) ?? []
        bash = try c.decodeIfPresent([String].self, forKey: .bash) ?? []
        protectedPaths = try c.decodeIfPresent([String].self, forKey: .protectedPaths) ?? []
    }

    public enum Verdict: Equatable, Sendable {
        /// Allow / Deny buttons in the notch.
        case notch
        /// Only "go to terminal".
        case terminal(reason: String)
    }

    /// `input`: the tool input's string fields (`command`, `file_path`, `path`, `pattern`, `url`, …).
    public func verdict(tool: String, input: [String: String], home: String = NSHomeDirectory()) -> Verdict {
        for key in input.keys.sorted() where key != "description" {
            if let hit = protectedHit(input[key]!, home: home) { return .terminal(reason: "touches protected path \(hit)") }
        }
        if tool == "Bash" { return bashVerdict(input["command"] ?? "") }
        return tools.contains(tool) ? .notch : .terminal(reason: "\(tool) is not on the allowlist")
    }

    private func bashVerdict(_ raw: String) -> Verdict {
        let command = raw.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return .terminal(reason: "empty command") }
        if command.contains(where: Self.shellOperators.contains) {
            return .terminal(reason: "uses shell operators (pipes, redirects, chaining, substitution)")
        }
        let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let entry = bash.first(where: { entry in
            let prefix = entry.split(whereSeparator: \.isWhitespace).map(String.init)
            return !prefix.isEmpty && words.starts(with: prefix)
        }) else {
            return .terminal(reason: "`\(words.prefix(2).joined(separator: " "))` is not on the allowlist")
        }
        let arguments = words.dropFirst(entry.split(whereSeparator: \.isWhitespace).count)
        if let flag = arguments.first(where: { arg in Self.riskyFlags.contains { arg.hasPrefix($0) } }) {
            return .terminal(reason: "flag \(flag) can write or run other things")
        }
        return .notch
    }

    /// The protected pattern `value` touches, if any.
    func protectedHit(_ value: String, home: String) -> String? {
        let expanded = value.replacingOccurrences(of: "~/", with: home + "/")
        let components = expanded.split(whereSeparator: { "/ \t\n\"'=:".contains($0) }).map(String.init)
        for pattern in protectedPaths {
            if pattern.hasPrefix("~/") {
                let absolute = home + "/" + pattern.dropFirst(2)
                if expanded.contains(absolute + "/") || expanded.hasSuffix(absolute) || components.contains(String(pattern.dropFirst(2))) {
                    return pattern
                }
            } else if pattern.hasPrefix("*.") {
                let suffix = String(pattern.dropFirst(1))
                if components.contains(where: { $0.hasSuffix(suffix) }) { return pattern }
            } else {
                let name = pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern
                if components.contains(where: { $0 == name || $0.hasPrefix(name + ".") }) { return pattern }
            }
        }
        return nil
    }

    public static func parse(_ data: Data) throws -> Allowlist {
        try JSONDecoder().decode(Allowlist.self, from: data)
    }

    /// No file: the defaults. A broken file: nothing approvable (fail closed), plus the error to report.
    public static func load(from url: URL) -> (Allowlist, String?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (.defaults, nil) }
        do {
            return (try parse(try Data(contentsOf: url)), nil)
        } catch {
            return (Allowlist(tools: [], bash: [], protectedPaths: []),
                    "\(url.path) is not valid (\(error)); nothing can be approved from the notch until it is fixed")
        }
    }

    public func rendered() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self)
    }
}
