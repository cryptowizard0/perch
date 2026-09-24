import Foundation

/// "2 agents · 4m": how many agent sessions are running and how long the oldest has been going.
/// Fed by perchd's sessions (hooks: UserPromptSubmit starts a turn, Stop ends it); hidden when none run.
/// Minute resolution, like the notch's tick: under a minute reads "<1m".
public struct LiveActivity: Equatable, Sendable {
    public var sessionStarts: [Date]

    public init(sessionStarts: [Date]) {
        self.sessionStarts = sessionStarts
    }

    /// nil when nothing is running.
    public func text(now: Date) -> String? {
        guard let oldest = sessionStarts.min() else { return nil }
        let n = sessionStarts.count
        let elapsed = now.timeIntervalSince(oldest)
        return "\(n) agent\(n == 1 ? "" : "s") · \(elapsed < 60 ? "<1m" : RelativeTime.duration(elapsed))"
    }
}
