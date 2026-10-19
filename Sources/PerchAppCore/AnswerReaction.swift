import Foundation

/// When the mascot reacts to an answer (#62). Answered with the notch folded (⌥⇧A / ⌥⇧D), it plays now. Answered in
/// the expanded panel, it waits for the notch to fold, so you get to see it, but only if that happens within `window`:
/// a bow minutes later would come out of nowhere. Only the latest answer counts.
public struct AnswerReactions: Equatable, Sendable {
    public static let window: TimeInterval = 5

    private var pending: (answer: Mascot.Answer, at: Date)?

    public init() {}

    /// `value` was just sent. Returns the reaction to play now, if the notch is folded.
    public mutating func answered(_ value: String, at time: Date, expanded: Bool) -> Mascot.Answer? {
        let answer = Mascot.Answer(response: value)
        guard expanded else {
            pending = nil
            return answer
        }
        pending = (answer, time)
        return nil
    }

    /// The notch folded: the waiting reaction, if it was answered within `window`. It plays once either way.
    public mutating func folded(at time: Date) -> Mascot.Answer? {
        defer { pending = nil }
        guard let pending, time.timeIntervalSince(pending.at) <= Self.window else { return nil }
        return pending.answer
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.pending?.answer == b.pending?.answer && a.pending?.at == b.pending?.at
    }
}

/// A reaction to an answer that is playing, from `start`.
public struct AnswerReaction: Equatable, Sendable {
    public let answer: Mascot.Answer
    public let start: Date

    public init(_ answer: Mascot.Answer, start: Date) {
        self.answer = answer
        self.start = start
    }
}
