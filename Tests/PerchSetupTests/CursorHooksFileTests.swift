import Foundation
import PerchSetup
import Testing

/// Cursor's ~/.cursor/hooks.json (#98): flat (`hooks → event → [handler]`) with a `version`, and shared with other
/// tools; Perch only ever adds and removes its own entries.
@Suite struct CursorHooksFileTests {
    let file = HookSettings.cursor
    let perch = "/Users/me/.perch/bin/perch"
    /// Another tool's hooks, as Superset writes them.
    let other = """
    {
      "version": 1,
      "hooks": {
        "beforeSubmitPrompt": [{ "command": "/Users/me/.superset/hooks/cursor-hook.sh Start" }],
        "beforeShellExecution": [{ "command": "/Users/me/.superset/hooks/cursor-hook.sh PermissionRequest" }]
      }
    }
    """

    func root(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func commands(_ text: String) throws -> [String: [String]] {
        let hooks = try root(text)["hooks"] as? [String: [[String: Any]]] ?? [:]
        return hooks.mapValues { $0.compactMap { $0["command"] as? String } }
    }

    @Test func installsNextToOtherTools() throws {
        let text = try file.installing(other, path: "/x", perch: perch, wait: 20)
        #expect(try root(text)["version"] as? Int == 1)
        #expect(try commands(text) == [
            "beforeSubmitPrompt": ["/Users/me/.superset/hooks/cursor-hook.sh Start", "\(perch) hook cursor"],
            "beforeShellExecution": ["/Users/me/.superset/hooks/cursor-hook.sh PermissionRequest"],
            "afterAgentResponse": ["\(perch) hook cursor"],
            "stop": ["\(perch) hook cursor"],
            "sessionEnd": ["\(perch) hook cursor"],
        ])
        // Flat handlers with a short cap; no permission hook of Perch's.
        let stop = try #require((try root(text)["hooks"] as? [String: [[String: Any]]])?["stop"]?.first)
        #expect(stop["timeout"] as? Int == 5 && stop["hooks"] == nil && stop["type"] == nil)

        // Installing again replaces Perch's entries, never duplicates them.
        #expect(try file.installing(text, path: "/x", perch: perch, wait: 20) == text)
        #expect(try file.perchHooks(in: text, path: "/x") == (try file.perchHooks(in: file.installing(nil, path: "/x", perch: perch, wait: 20), path: "/x")))
        #expect(file.wait(in: text) == nil)
    }

    @Test func aNewFileGetsAVersion() throws {
        let text = try file.installing(nil, path: "/x", perch: perch, wait: 20)
        #expect(try root(text)["version"] as? Int == 1)
        #expect(try commands(text).keys.sorted() == ["afterAgentResponse", "beforeSubmitPrompt", "sessionEnd", "stop"])
    }

    @Test func removingLeavesOtherToolsAlone() throws {
        let installed = try file.installing(other, path: "/x", perch: perch, wait: 20)
        let (kept, removed) = try file.removing(installed, path: "/x")
        #expect(removed == 4)
        #expect(try commands(kept) == [
            "beforeSubmitPrompt": ["/Users/me/.superset/hooks/cursor-hook.sh Start"],
            "beforeShellExecution": ["/Users/me/.superset/hooks/cursor-hook.sh PermissionRequest"],
        ])
        #expect(try root(kept)["version"] as? Int == 1)
        #expect(try file.perchHooks(in: kept, path: "/x") == "")
    }

    @Test func othersHooksAreNotPerchs() throws {
        // Grok's adapter is not Cursor's, and neither is a claude-code hook someone copied over.
        let text = #"{"version":1,"hooks":{"stop":[{"command":"/b/perch hook grok"},{"command":"/b/perch hook claude-code"}]}}"#
        #expect(try file.perchHooks(in: text, path: "/x") == "")
        #expect(try file.removing(text, path: "/x").removed == 0)
    }

    @Test func detectedByTheCursorDirectory() {
        let location = file.location
        #expect(location.candidates(recorded: nil, environment: [:], userHome: "/Users/me") == ["/Users/me/.cursor/hooks.json"])
        #expect(location.agentDirectory(of: "/Users/me/.cursor/hooks.json") == "/Users/me/.cursor")
    }
}
