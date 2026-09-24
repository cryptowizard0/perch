import Foundation

/// "2 agents · 4m": how many agent sessions are running and how long the oldest has been going.
/// Where sessions come from is decided in M3 (SessionStart / Stop hooks); until then there are none
/// and the collapsed notch hides this.
public struct LiveActivity: Equatable, Sendable {
    public var sessionStarts: [Date]

    public init(sessionStarts: [Date]) {
        self.sessionStarts = sessionStarts
    }

    /// nil when nothing is running.
    public func text(now: Date) -> String? {
        guard let oldest = sessionStarts.min() else { return nil }
        let n = sessionStarts.count
        return "\(n) agent\(n == 1 ? "" : "s") · \(RelativeTime.duration(now.timeIntervalSince(oldest)))"
    }
}
