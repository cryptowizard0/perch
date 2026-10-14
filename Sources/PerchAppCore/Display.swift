import Foundation

/// One connected display, in `NSScreen.screens` order (the first is the main, menu-bar display).
public struct DisplayScreen: Equatable, Sendable {
    /// The display's UUID: stable across reboots and re-plugging, unlike `CGDirectDisplayID`.
    public var id: String
    /// `NSScreen.localizedName`, e.g. "Built-in Retina Display".
    public var name: String
    public var hasNotch: Bool

    public init(id: String, name: String, hasNotch: Bool) {
        self.id = id
        self.name = name
        self.hasNotch = hasNotch
    }
}

/// Which display the notch panel goes on: right-click the notch → Display (#37).
public enum DisplayChoice: Equatable, Sendable {
    /// The built-in display if it has a notch (wherever it is in the arrangement), else the main display.
    case automatic
    /// The display with the menu bar, whichever that is.
    case main
    /// Pinned to one display; `name` is remembered for the menu while it isn't connected.
    case display(id: String, name: String)

    static let key = "Display"
    static let nameKey = "DisplayName"

    /// Missing or unreadable = Automatic.
    public init(defaults: UserDefaults) {
        switch defaults.object(forKey: Self.key) as? String {
        case "main": self = .main
        case "automatic", "", nil: self = .automatic
        case let id?: self = .display(id: id, name: defaults.string(forKey: Self.nameKey) ?? "Display")
        }
    }

    public func save(to defaults: UserDefaults) {
        switch self {
        case .automatic:
            defaults.set("automatic", forKey: Self.key)
            defaults.removeObject(forKey: Self.nameKey)
        case .main:
            defaults.set("main", forKey: Self.key)
            defaults.removeObject(forKey: Self.nameKey)
        case let .display(id, name):
            defaults.set(id, forKey: Self.key)
            defaults.set(name, forKey: Self.nameKey)
        }
    }

    /// Index of the screen to use; a pinned display that isn't connected falls back to Automatic.
    public func screen(in screens: [DisplayScreen]) -> Int? {
        switch self {
        case .automatic:
            return screens.firstIndex(where: \.hasNotch) ?? screens.indices.first
        case .main:
            return screens.indices.first
        case let .display(id, _):
            return screens.firstIndex { $0.id == id } ?? Self.automatic.screen(in: screens)
        }
    }
}

public struct DisplayMenuItem: Equatable, Sendable {
    public var title: String
    public var choice: DisplayChoice
    public var checked: Bool
    public var enabled: Bool

    public init(title: String, choice: DisplayChoice, checked: Bool, enabled: Bool) {
        self.title = title
        self.choice = choice
        self.checked = checked
        self.enabled = enabled
    }
}

/// The per-display part of the Display menu, under Automatic and Main Display.
public enum DisplayMenu {
    /// One item per connected display (same names numbered " (2)"…); a pinned display that isn't connected
    /// stays, checked and disabled, so the menu shows where the panel goes back to.
    public static func displays(choice: DisplayChoice, screens: [DisplayScreen]) -> [DisplayMenuItem] {
        let pinned: String? = if case let .display(id, _) = choice { id } else { nil }
        var seen: [String: Int] = [:]
        var items = screens.map { screen in
            seen[screen.name, default: 0] += 1
            let n = seen[screen.name]!
            return DisplayMenuItem(title: n == 1 ? screen.name : "\(screen.name) (\(n))",
                                   choice: .display(id: screen.id, name: screen.name),
                                   checked: screen.id == pinned, enabled: true)
        }
        if case let .display(id, name) = choice, !screens.contains(where: { $0.id == id }) {
            items.append(DisplayMenuItem(title: "\(name) (not connected)", choice: choice, checked: true, enabled: false))
        }
        return items
    }
}
