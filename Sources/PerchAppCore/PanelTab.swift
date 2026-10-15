import Foundation
import PerchCore

/// What the expanded notch shows (#41): agent sessions or the human's todos. Picked from the icons in the strip
/// beside the notch.
public enum PanelTab: String, CaseIterable, Sendable {
    case agents, todo

    /// The tab the panel opens on: Agents whenever a session needs you or failed (todos never hide a waiting agent),
    /// otherwise the last tab picked by hand. An open panel keeps its tab; the Agents icon's dot is the signal.
    public static func opening(picked: PanelTab, panel: Panel) -> PanelTab {
        panel.attention == nil ? picked : .agents
    }
}

extension Panel {
    /// The dot on the Agents icon: Needs you (orange) while any session needs you, otherwise Failed (red) while any
    /// failed; nil otherwise.
    public var attention: SessionStatus? {
        if sessions.contains(where: { $0.status == .waiting }) { return .waiting }
        if sessions.contains(where: { $0.status == .failed }) { return .failed }
        return nil
    }
}
