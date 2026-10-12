import Darwin
import Foundation
import ServiceManagement

/// Whether Perch.app opens at login: `SMAppService.mainApp`'s status, as Perch reads it.
public enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case notRegistered
    /// Registered, but switched off under System Settings → General → Login Items: only the user can allow it there.
    case requiresApproval
    /// Never registered (or the system lost track of the bundle).
    case notFound
}

/// The app's login item. `mainApp` is `SMAppService.mainApp` (it works for the ad-hoc-signed, unnotarized app:
/// checked 2026-10-12, register → enabled, unregister → notRegistered); tests pass their own.
public struct LoginItem: Sendable {
    public let status: @Sendable () -> LoginItemStatus
    public let register: @Sendable () throws -> Void
    public let unregister: @Sendable () throws -> Void
    /// Opens System Settings → General → Login Items.
    public let openSettings: @Sendable () -> Void

    public init(status: @escaping @Sendable () -> LoginItemStatus, register: @escaping @Sendable () throws -> Void,
                unregister: @escaping @Sendable () throws -> Void, openSettings: @escaping @Sendable () -> Void) {
        self.status = status
        self.register = register
        self.unregister = unregister
        self.openSettings = openSettings
    }

    public static let mainApp = LoginItem(
        status: {
            switch SMAppService.mainApp.status {
            case .enabled: return .enabled
            case .requiresApproval: return .requiresApproval
            case .notRegistered: return .notRegistered
            default: return .notFound
            }
        },
        register: {
            // A test runner or a bare `swift run` binary is no bundle to open at login.
            guard Bundle.main.bundleURL.pathExtension == "app" else { throw LoginItemError() }
            try SMAppService.mainApp.register()
        },
        unregister: {
            guard Bundle.main.bundleURL.pathExtension == "app" else { throw LoginItemError() }
            try SMAppService.mainApp.unregister()
        },
        openSettings: { SMAppService.openSystemSettingsLoginItems() }
    )

    /// `mainApp` when setup runs for the user logged in; nil under another `$HOME` (an isolated run): the login item
    /// belongs to the real user whatever `$HOME` says, so an isolated app must not register, unregister or show it.
    public static func mainApp(forHome home: URL) -> LoginItem? {
        guard let entry = getpwuid(getuid()), let real = entry.pointee.pw_dir.map({ String(cString: $0) }) else { return nil }
        return home.standardizedFileURL.path == URL(fileURLWithPath: real).standardizedFileURL.path ? .mainApp : nil
    }

    /// Turns it on or off; nothing to do when it already is (unregistering what was never registered fails).
    func set(_ on: Bool) throws {
        let current = status()
        if on {
            guard current != .enabled else { return }
            try register()
        } else {
            guard current == .enabled || current == .requiresApproval else { return }
            try unregister()
        }
    }
}

struct LoginItemError: Error, LocalizedError {
    var errorDescription: String? { "only Perch.app can open at login" }
}
