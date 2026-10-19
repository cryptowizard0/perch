import Darwin
import Foundation
import PerchSetup
import Testing

@Suite struct InstallerTests {
    let root = URL(fileURLWithPath: "/tmp/perch-installer-\(UUID().uuidString.prefix(8))")
    var installer: Installer {
        Installer(environment: SetupEnvironment(variables: ["HOME": root.path, "PERCH_HOME": root.appendingPathComponent(".perch").path]),
                  launchctl: Launchctl(path: "/usr/bin/false"))
    }

    func quarantined(_ path: String) -> Bool {
        getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    @Test func syncCopiesRealFilesWithoutTheQuarantineFlag() throws {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: root) }
        let download = root.appendingPathComponent("Downloads/perch-0.4.0")
        try fm.createDirectory(at: download, withIntermediateDirectories: true)
        for name in ["perch", "perchd"] {
            let path = download.appendingPathComponent(name).path
            try "#!/bin/sh\necho \(name)\n".write(toFile: path, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            let flag = "0081;00000000;Safari;"
            #expect(setxattr(path, "com.apple.quarantine", flag, flag.utf8.count, 0, XATTR_NOFOLLOW) == 0)
        }

        #expect(try installer.syncBinaries(from: download))
        let bin = installer.environment.binDirectory
        for name in ["perch", "perchd"] {
            let path = bin.appendingPathComponent(name).path
            #expect(try fm.attributesOfItem(atPath: path)[.type] as? FileAttributeType == .typeRegular)
            #expect(fm.isExecutableFile(atPath: path))
            #expect(!quarantined(path), "\(name)")
            #expect(try String(contentsOfFile: path, encoding: .utf8) == "#!/bin/sh\necho \(name)\n")
        }
        #expect(try fm.contentsOfDirectory(atPath: bin.path).sorted() == ["perch", "perchd"])  // no temporary files left
        // Running setup from the installed copy itself copies nothing.
        #expect(try !installer.syncBinaries(from: bin))
    }

    /// dsh's row names a plugin next to the installed perch: writing the row writes the plugin first, and every sync
    /// rewrites it while dsh is connected (#76).
    @Test func dshPluginFollowsTheRowAndTheBinaries() throws {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: root) }
        let plugin = installer.environment.binDirectory.appendingPathComponent("perch-dsh.mjs")
        let layer = root.appendingPathComponent(".dsh/cordis.patch.yml").path
        try fm.createDirectory(at: root.appendingPathComponent(".dsh"), withIntermediateDirectories: true)

        var agents = AgentsFile()
        let row = try DshPatch().installing(nil, path: layer, perch: installer.environment.perchBinary.path, wait: 20)
        let snapshot = installer.snapshot(agents: agents, runner: .cli, bundledVersion: "0.5.0", installedVersion: nil)
        let plan = Setup.evaluate(snapshot, request: .setup(agents: ["dsh"])).plan
        #expect(plan.changes.map(\.agent) == ["dsh"])
        #expect(installer.perform(plan, recordingIn: &agents).isEmpty)
        try installer.saveAgents(agents)
        #expect(try String(contentsOf: plugin, encoding: .utf8) == DshPlugin.source)
        #expect(try String(contentsOfFile: layer, encoding: .utf8) == row)

        // A sync puts back the plugin that matches the binaries.
        try "stale".write(to: plugin, atomically: true, encoding: .utf8)
        let build = root.appendingPathComponent("build")
        try fm.createDirectory(at: build, withIntermediateDirectories: true)
        for name in ["perch", "perchd"] {
            try "#!/bin/sh\n".write(to: build.appendingPathComponent(name), atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: build.appendingPathComponent(name).path)
        }
        try installer.syncBinaries(from: build)
        #expect(try String(contentsOf: plugin, encoding: .utf8) == DshPlugin.source)

        // Not connected: a sync writes no plugin.
        try fm.removeItem(at: plugin)
        agents.turnOff("dsh", config: layer)
        try installer.saveAgents(agents)
        try installer.syncBinaries(from: build)
        #expect(!fm.fileExists(atPath: plugin.path))
    }

    @Test func syncNeedsBothBinaries() throws {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: root) }
        let build = root.appendingPathComponent("build")
        try fm.createDirectory(at: build, withIntermediateDirectories: true)
        try "x".write(to: build.appendingPathComponent("perch"), atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: build.appendingPathComponent("perch").path)
        #expect(throws: SetupError.self) { try installer.syncBinaries(from: build) }
        #expect(!fm.fileExists(atPath: installer.environment.perchBinary.path))
    }

    @Test func oldPerchBinariesInLocalBinBecomeLinks() throws {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: root) }
        let localBin = installer.environment.localBin
        try fm.createDirectory(at: localBin, withIntermediateDirectories: true)
        // What a v0.3 release build carries; "perchd.sock" alone is not in it as bytes.
        let old = Data("\u{7f}ELF…<!-- Generated by perchd. Read-only: rewritten on every change. -->…".utf8)
        try old.write(to: localBin.appendingPathComponent("perch"))
        try Data("someone else's perchd".utf8).write(to: localBin.appendingPathComponent("perchd"))

        #expect(try installer.linkOldBinaries() == [localBin.appendingPathComponent("perch").path])
        #expect(try fm.destinationOfSymbolicLink(atPath: localBin.appendingPathComponent("perch").path)
                == installer.environment.perchBinary.path)
        #expect(try Data(contentsOf: localBin.appendingPathComponent("perchd")) == Data("someone else's perchd".utf8))
        #expect(try installer.linkOldBinaries().isEmpty)  // a link is left as it is
    }
}
