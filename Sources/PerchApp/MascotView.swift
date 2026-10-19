import PerchAppCore
import PerchCore
import SwiftUI

/// The collapsed notch's mascot (#22): `Mascot`'s cells drawn one point each, no antialiasing. Redraws only while
/// something moves (Running, Needs you, Idle, a reaction, a bow or scratch, a quirk: Failed and Done stand still between
/// theirs); with
/// Reduce Motion it shows each mood's still frame and plays no quirks. Reactions and quirks may draw `Mascot.margin`
/// points around its frame.
struct MascotView: View {
    var signal: SessionStatus?
    /// When the signal's state began (`Panel.signalSince`): a long run sweats.
    var since: Date?
    var online = true
    /// Bumped on entering Needs you / Failed / Done; `pulseStatus` is the state that caused it.
    var pulse = 0
    var pulseStatus: SessionStatus?
    /// A bow or scratch after an answer, while the model says it plays (#62).
    var answer: AnswerReaction?
    @State private var reaction: (status: SessionStatus, start: Date)?
    @State private var quirk: (quirk: Mascot.Quirk, start: Date)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let mood = Mascot.Mood(signal: signal, online: online)
        let fps = Mascot.fps(mood, reacting: reaction != nil || answer != nil, quirking: quirk != nil)
        let quirks = Mascot.quirks(mood, online: online, reduceMotion: reduceMotion)
        let margin = CGFloat(Mascot.margin)
        TimelineView(.animation(minimumInterval: 1 / max(fps, 1), paused: reduceMotion || fps == 0)) { timeline in
            Canvas { context, _ in
                // While a reaction plays, the mascot takes the look and colour of the state that caused it.
                let playing = reaction.flatMap { reaction -> (status: SessionStatus, reaction: Mascot.Reaction)? in
                    let played = Mascot.Reaction(mood: Mascot.Mood(signal: reaction.status), age: timeline.date.timeIntervalSince(reaction.start))
                    return reduceMotion || played.isOver ? nil : (reaction.status, played)
                }
                let quirking = quirk.map { Mascot.QuirkPlay($0.quirk, age: timeline.date.timeIntervalSince($0.start)) }
                let answering = answer.map { Mascot.AnswerPlay($0.answer, age: timeline.date.timeIntervalSince($0.start)) }
                let cells = reduceMotion ? Mascot.still(mood) : Mascot.frame(
                    mood, time: timeline.date.timeIntervalSinceReferenceDate, since: since?.timeIntervalSinceReferenceDate,
                    reaction: playing?.reaction, answer: answering, quirk: quirking
                )
                for ink in Mascot.Ink.allCases {
                    var path = Path()
                    for cell in cells where cell.ink == ink {
                        path.addRect(CGRect(x: CGFloat(cell.x) + margin, y: CGFloat(cell.y) + margin, width: 1, height: 1))
                    }
                    context.fill(path, with: .color(color(ink, status: playing?.status ?? signal)), style: FillStyle(antialiased: false))
                }
            }
        }
        // Idle's "z" and Done's ♪ drift past the right edge, over where the running count would be (there is none then:
        // running outranks done); reactions and quirks use the margin all round. Neither takes room in the layout.
        .frame(width: CGFloat(Mascot.overflowWidth) + 2 * margin, height: CGFloat(Mascot.height) + 2 * margin)
        .padding(EdgeInsets(top: -margin, leading: -margin, bottom: -margin,
                            trailing: CGFloat(Mascot.width - Mascot.overflowWidth) - margin))
        .accessibilityLabel(signal.map { "\($0)" } ?? "No sessions")
        .onChange(of: pulse) {
            guard !reduceMotion, let status = pulseStatus, let duration = Mascot.Mood(signal: status).reactionDuration else { return }
            let start = Date()
            reaction = (status, start)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                if reaction?.start == start { reaction = nil }
            }
        }
        // Asleep, idle, failed or done (and perchd up): wait for the next quirk of the mood's set, play it, repeat.
        // Keyed by the set, so asleep ↔ idle keeps a quirk going and failed ↔ done starts over.
        .task(id: quirks) {
            quirk = nil
            guard !quirks.isEmpty else { return }
            while !Task.isCancelled {
                let now = Date()
                guard let next = Mascot.nextQuirk(after: now.timeIntervalSinceReferenceDate, in: mood) else { return }
                let start = Date(timeIntervalSinceReferenceDate: next.start)
                do {
                    try await Task.sleep(for: .seconds(start.timeIntervalSince(now)))
                    quirk = (next.quirk, start)
                    try await Task.sleep(for: .seconds(next.quirk.duration))
                } catch {
                    break
                }
                quirk = nil
            }
        }
    }

    private func color(_ ink: Mascot.Ink, status: SessionStatus?) -> Color {
        switch ink {
        case .body: return online ? SessionStatus.color(status) : Color.gray.opacity(0.5)
        case .white: return .white
        case .dark: return Color(white: 0.04)
        case .faint: return .white.opacity(0.6)
        case .confetti0: return SessionStatus.color(.waiting)
        case .confetti1: return Color(red: 1, green: 0.4, blue: 0.7)
        case .confetti2: return Color(red: 0.3, green: 0.85, blue: 1)
        }
    }
}
