import Foundation
import PerchCore

/// The collapsed notch's event banner: when a panel session starts needing you, fails or finishes (the pulse,
/// `Panel.pulses`), the right wing grows for a few seconds with the project and one line of what happened, then
/// shrinks back. Never a persistent ticker: it shows only at the moments the notch already pulses and chimes.
public struct Banner: Equatable, Sendable {
    /// Distinguishes banners, so a timer for an old one never ends a new one (even for the same session).
    public var id: Int
    public var sessionID: String
    public var status: SessionStatus
    /// The project, in the state's colour.
    public var title: String
    /// One line: the command or question (Needs you), the error (Failed), the reply (Done).
    public var text: String

    public init(id: Int, session: Session) {
        self.id = id
        sessionID = session.id
        status = session.status
        title = session.title
        text = Self.text(for: session)
    }

    /// The first non-empty line of the row's detail, or the state's label.
    static func text(for s: Session) -> String {
        let detail: String?
        switch s.status {
        case .waiting: detail = SessionRow.needsYou(s, request: nil).text
        case .failed: detail = s.error
        case .done: detail = s.lastMessage
        case .running, .idle: detail = nil
        }
        let line = detail?.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        return line ?? s.status.label
    }

    // Layout and timing, shared by the view (which scrolls) and the model (which times it out).

    /// The widest the title and text get before the text scrolls.
    public static let maxContentWidth: Double = 220
    /// Space between the notch and the content, and after it.
    public static let inset: Double = 10
    /// Time to read before a too-long line starts scrolling, its speed, and the pause at its end.
    public static let scrollDelay: TimeInterval = 1.2
    public static let scrollSpeed: Double = 40
    public static let endHold: TimeInterval = 1.5
    /// A line that fits stays this long; nothing stays longer than `maxDuration`.
    public static let minDuration: TimeInterval = 4
    public static let maxDuration: TimeInterval = 12

    /// The right wing while the banner shows, for content `contentWidth` points wide.
    public static func wing(contentWidth: Double) -> Double {
        (inset + min(contentWidth, maxContentWidth) + inset).rounded(.up)
    }

    /// How far a line `contentWidth` points wide scrolls (0 if it fits).
    public static func overflow(contentWidth: Double) -> Double {
        max(0, contentWidth - maxContentWidth)
    }

    /// How long it shows: long enough to read, and to scroll a too-long line once to its end.
    public static func duration(contentWidth: Double) -> TimeInterval {
        let overflow = overflow(contentWidth: contentWidth)
        guard overflow > 0 else { return minDuration }
        return min(max(scrollDelay + overflow / scrollSpeed + endHold, minDuration), maxDuration)
    }
}

/// Which banner shows, decided per session change. The model times it out; the notch expanding clears it.
public struct BannerState: Equatable, Sendable {
    public private(set) var current: Banner?
    private var lastID = 0

    public init() {}

    /// Applies one session change (`after` nil: removed). Returns whether `current` changed.
    ///
    /// A pulse shows a banner unless one that is more urgent is up (a session finishing while another's command
    /// waits does not cover the command); the same or more urgent replaces it. The banner goes away early when its
    /// session leaves that state or is removed: what it says is no longer true.
    @discardableResult
    public mutating func update(id: String, from before: Session?, to after: Session?) -> Bool {
        if Panel.pulses(from: before, to: after), let after {
            if let current, current.sessionID != after.id, current.status.priority < after.status.priority { return false }
            lastID += 1
            current = Banner(id: lastID, session: after)
            return true
        }
        guard let current, current.sessionID == id, after?.status != current.status else { return false }
        self.current = nil
        return true
    }

    /// Ends banner `id` if it is still the one up (its timer fired). Returns whether it was.
    @discardableResult
    public mutating func dismiss(_ id: Int) -> Bool {
        guard current?.id == id else { return false }
        current = nil
        return true
    }

    public mutating func clear() {
        current = nil
    }
}
