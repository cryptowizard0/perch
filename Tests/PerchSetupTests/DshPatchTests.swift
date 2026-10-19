import Foundation
import PerchSetup
import Testing

/// dsh's home patch layer (`$DSH_HOME/cordis.patch.yml`): Perch edits one marked row as text (#76).
@Suite struct DshPatchTests {
    let patch = DshPatch()
    let perch = "/Users/me/.perch/bin/perch"
    let path = "/Users/me/.dsh/cordis.patch.yml"

    var row: String {
        """
        # >>> perch: added by `perch hooks install dsh`, removed by `perch hooks uninstall dsh` >>>
        - insert:
            - id: perch
              name: '/Users/me/.perch/bin/perch-dsh.mjs'
              config:
                perch: '/Users/me/.perch/bin/perch'
        # <<< perch <<<

        """
    }

    func install(_ text: String?, perch: String? = nil) throws -> String {
        try patch.installing(text, path: path, perch: perch ?? self.perch, wait: 20)
    }

    @Test func aMissingOrBlankFileGetsJustTheRow() throws {
        #expect(try install(nil) == row)
        #expect(try install("") == row)
        #expect(try install("\n\n") == row)
        #expect(patch.isBlank("\n  \n"))
    }

    @Test func commentsAndAnEmptyListMakeRoomForTheRow() throws {
        #expect(try install("# my notes\n") == "# my notes\n" + row)
        #expect(try install("# my notes\n[]\n") == "# my notes\n" + row)
        #expect(try install("[]  # nothing yet") == row)
        #expect(patch.isBlank("# my notes\n"))
    }

    /// Someone else's rows stay exactly as they were, around install and uninstall.
    @Test func theRowIsAddedToAListAndRemovedAgain() throws {
        let mine = """
        # my overrides
        - id: tui
          config:
            theme:
              leftPrompt: '${cwd}${model}'
        - insert:
            - id: working-activity
              name: dsh-working-activity
        """
        let installed = try install(mine)
        #expect(installed == mine + "\n" + row)
        #expect(try patch.perchHooks(in: installed, path: path) == row)
        #expect(try patch.perchHooks(in: mine, path: path) == "")
        let (kept, removed) = try patch.removing(installed, path: path)
        #expect(removed == 1)
        #expect(kept == mine + "\n")
        #expect(!patch.isBlank(kept))
        #expect(try patch.removing(kept, path: path).removed == 0)
    }

    @Test func reinstallingReplacesTheRow() throws {
        let old = try install("- id: mine\n  name: x\n", perch: "/old/bin/perch")
        let new = try install(old)
        #expect(new == "- id: mine\n  name: x\n" + row)
        #expect(new.components(separatedBy: "# >>> perch").count == 2)
        #expect(try patch.perchHooks(in: old, path: path) != patch.perchHooks(in: new, path: path))
    }

    /// The row and the plugin follow the binary; quotes survive both the shell and YAML.
    @Test func pathsAreQuotedForYAML() throws {
        let odd = "/Users/me/it's here/perch"
        let text = try install(nil, perch: "'/Users/me/it'\\''s here/perch'")  // as HookFiles.shellQuote passes it
        #expect(text.contains("name: '/Users/me/it''s here/perch-dsh.mjs'\n"))
        #expect(text.contains("perch: '/Users/me/it''s here/perch'\n"))
        #expect(HookFiles.shellUnquote(HookFiles.shellQuote(odd)) == odd)
        #expect(HookFiles.shellUnquote(perch) == perch)
    }

    @Test func shapesPerchCannotEditAsTextAreRefused() {
        for text in ["[{id: mine, name: x}]\n", "- id: a\nother: 1\n", "insert:\n  - id: a\n", "  - id: indented first\n"] {
            #expect(throws: SetupError.self, "\(text)") { try install(text) }
        }
    }

    @Test func thePluginIsWrittenNextToThePerchBinary() {
        #expect(patch.supportFiles(perch: perch) == ["/Users/me/.perch/bin/perch-dsh.mjs": DshPlugin.source])
        #expect(patch.supportFiles(perch: "'/a b/perch'").keys.first == "/a b/perch-dsh.mjs")
        #expect(patch.wait(in: row) == nil)
    }

    /// `DshPlugin.source` is generated from packaging/dsh/perch.mjs (scripts/dsh/embed-plugin.sh).
    @Test func theEmbeddedPluginIsPackagingsFile() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("packaging/dsh/perch.mjs")
        let packaged = try String(contentsOf: file, encoding: .utf8)
        #expect(DshPlugin.source == packaged, "run scripts/dsh/embed-plugin.sh and commit the result")
        #expect(DshPlugin.source.contains("export function apply(ctx, config)"))
    }
}
