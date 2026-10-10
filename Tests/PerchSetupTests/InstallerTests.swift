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
}
