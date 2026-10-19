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
    /// The pointer nearby (#63); a change redraws once, even when the mood stands still.
    var gaze: Gaze?
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
                    mood, time: timeline.date.timeIntervalSinceReferenceDate, since: since?.timeIntervalSinceReferenceDate, gaze: gaze,
                    reaction: playing?.reaction, answer: answering, quirk: quirking
                )
                for ink in Mascot.Ink.allCases {
                    var path = Path()
                    for cell in cells where cell.ink == ink {
                        path.addRect(CGRect(x: CGFloat(cell.x) + margin, y: CGFloat(cell.y) + margin, width: 1, height: 1))
                    }
                    context.fill(path, with: .color(Self.color(ink, status: playing?.status ?? signal, online: online)),
                                 style: FillStyle(antialiased: false))
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

    static func color(_ ink: Mascot.Ink, status: SessionStatus?, online: Bool) -> Color {
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

/// The mascot on its Done run (#64), drawn over the whole folded band: along `DoneRun`'s path, hidden while the notch
/// covers it. In Done's colour, except dashing home in the signal's.
struct FlightView: View {
    var flight: DoneRun
    var signal: SessionStatus?
    var online: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard let position = flight.position(at: timeline.date.timeIntervalSinceReferenceDate), !position.hidden else { return }
                let cells = Mascot.frame(flying: position, mood: Mascot.Mood(signal: signal, online: online))
                let status = position.move == .dash ? signal : .done
                // Where the bar draws it at home: `collapsedInset` in, centred in the band.
                let x = CGFloat(position.x.rounded()), y = (size.height - CGFloat(Mascot.height)) / 2
                for ink in Mascot.Ink.allCases {
                    var path = Path()
                    for cell in cells where cell.ink == ink {
                        path.addRect(CGRect(x: x + CGFloat(cell.x), y: y + CGFloat(cell.y), width: 1, height: 1))
                    }
                    context.fill(path, with: .color(MascotView.color(ink, status: status, online: online)),
                                 style: FillStyle(antialiased: false))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The right wing's content as the Done run pulls the banner open and rolls it up (#64): shown from the wing's inner
/// edge to the mascot.
struct FlightReveal: View {
    var flight: DoneRun

    var body: some View {
        TimelineView(.animation) { timeline in
            let reveal = flight.position(at: timeline.date.timeIntervalSinceReferenceDate)?.reveal
            Rectangle().frame(width: reveal.map { CGFloat($0) })
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
