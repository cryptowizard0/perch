import Foundation
import PerchSetup
import Testing

/// Antigravity's ~/.gemini/config/hooks.json: top-level named hooks (`"perch": { ... }`), where simple events
/// (`PreInvocation`, `Stop`, …) are flat handler arrays and tool events (`PreToolUse`, `PostToolUse`) are grouped.
@Suite struct AntigravityHooksFileTests {
    let file = AntigravityHooks()
    let perch = "/Users/me/.perch/bin/perch"
    /// Other user-configured named hooks (both grouped tool hooks and flat lifecycle hooks).
    let other = """
    {
      "lint-checker": {
        "PostToolUse": [
          {
            "matcher": "run_command",
            "hooks": [
              { "type": "command", "command": "./scripts/lint.sh", "timeout": 10 }
            ]
          }
        ]
      },
      "reminder": {
        "PreInvocation": [
          { "type": "command", "command": "./scripts/reminder.sh" }
        ]
      }
    }
    """

    func root(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test func installsNextToOtherNamedHooks() throws {
        let text = try file.installing(other, path: "/x", perch: perch, wait: 20)
        let json = try root(text)
        #expect(Set(json.keys) == ["lint-checker", "reminder", "perch"])

        let perchSpec = try #require(json["perch"] as? [String: [[String: Any]]])
        #expect(Set(perchSpec.keys) == ["PreInvocation", "Stop"])
        for event in ["PreInvocation", "Stop"] {
            let handlers = try #require(perchSpec[event])
            #expect(handlers.count == 1)
            #expect(handlers[0]["type"] as? String == "command")
            #expect(handlers[0]["command"] as? String == "\(perch) hook antigravity")
            #expect(handlers[0]["timeout"] as? Int == 5)
            #expect(handlers[0]["async"] == nil)
        }

        // Idempotent reinstall and canonical perchHooks comparison.
        #expect(try file.installing(text, path: "/x", perch: perch, wait: 20) == text)
        #expect(try file.perchHooks(in: text, path: "/x") == (try file.perchHooks(in: file.installing(nil, path: "/x", perch: perch, wait: 20), path: "/x")))
        #expect(file.wait(in: text) == nil)
    }

    @Test func createsNewFileAndRemovesCleanly() throws {
        let created = try file.installing(nil, path: "/x", perch: perch, wait: 20)
        #expect(Set(try root(created).keys) == ["perch"])
        let (empty, removed) = try file.removing(created, path: "/x")
        #expect(removed == 2)
        #expect(try root(empty).isEmpty)
        #expect(try file.perchHooks(in: empty, path: "/x") == "")
    }

    @Test func removingLeavesOtherNamedHooksAlone() throws {
        let installed = try file.installing(other, path: "/x", perch: perch, wait: 20)
        let (kept, removed) = try file.removing(installed, path: "/x")
        #expect(removed == 2)
        let json = try root(kept)
        #expect(Set(json.keys) == ["lint-checker", "reminder"])
        #expect(try file.perchHooks(in: kept, path: "/x") == "")
    }

    @Test func mixedNamedHookAndDisabledFlagAreHandledSafely() throws {
        let mixed = """
        {
          "perch": {
            "enabled": true,
            "PreInvocation": [
              { "type": "command", "command": "./mine.sh" },
              { "type": "command", "command": "/old/perch hook antigravity", "timeout": 5 }
            ],
            "Stop": [
              { "type": "command", "command": "/old/perch hook antigravity", "timeout": 5 }
            ]
          },
          "custom": {
            "PreToolUse": [
              { "matcher": "*", "hooks": [{ "type": "command", "command": "/old/perch hook antigravity" }] }
            ]
          }
        }
        """
        let (kept, removed) = try file.removing(mixed, path: "/x")
        #expect(removed == 3)
        let json = try root(kept)
        #expect(Set(json.keys) == ["perch"])
        let perchSpec = try #require(json["perch"] as? [String: Any])
        #expect(Set(perchSpec.keys) == ["enabled", "PreInvocation"])
        let pre = try #require(perchSpec["PreInvocation"] as? [[String: Any]])
        #expect(pre.count == 1 && pre[0]["command"] as? String == "./mine.sh")
    }

    @Test func refusesInvalidJSON() {
        #expect(throws: SetupError.self) {
            _ = try file.installing("{ broken", path: "/x/hooks.json", perch: perch, wait: 20)
        }
    }

    @Test func detectedByTheGeminiDirectory() {
        let location = file.location
        #expect(location.candidates(recorded: nil, environment: [:], userHome: "/Users/me") == ["/Users/me/.gemini/config/hooks.json"])
        #expect(location.agentDirectory(of: "/Users/me/.gemini/config/hooks.json") == "/Users/me/.gemini")
    }
}
