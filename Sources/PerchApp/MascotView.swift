import PerchAppCore
import PerchCore
import SwiftUI

/// The collapsed notch's mascot (#22): `Mascot`'s cells drawn one point each, no antialiasing. Redraws only while
/// something moves (Running, Needs you, Idle, a reaction); with Reduce Motion it shows each mood's still frame.
struct MascotView: View {
    var signal: SessionStatus?
    var online = true
    /// Bumped on entering Needs you / Failed / Done; `pulseStatus` is the state that caused it.
    var pulse = 0
    var pulseStatus: SessionStatus?
    @State private var reaction: (status: SessionStatus, start: Date)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let mood = Mascot.Mood(signal: signal, online: online)
        let fps = reaction == nil ? mood.fps : Mascot.reactionFPS
        TimelineView(.animation(minimumInterval: 1 / max(fps, 1), paused: reduceMotion || fps == 0)) { timeline in
            Canvas { context, _ in
                // While a reaction plays, the mascot takes the look and colour of the state that caused it.
                let playing = reaction.flatMap { reaction -> (status: SessionStatus, reaction: Mascot.Reaction)? in
                    let played = Mascot.Reaction(mood: Mascot.Mood(signal: reaction.status), age: timeline.date.timeIntervalSince(reaction.start))
                    return reduceMotion || played.isOver ? nil : (reaction.status, played)
                }
                let cells = reduceMotion ? Mascot.still(mood) : Mascot.frame(
                    mood, time: timeline.date.timeIntervalSinceReferenceDate, reaction: playing?.reaction
                )
                for ink in [Mascot.Ink.body, .white, .dark, .faint] {
                    var path = Path()
                    for cell in cells where cell.ink == ink {
                        path.addRect(CGRect(x: cell.x, y: cell.y, width: 1, height: 1))
                    }
                    context.fill(path, with: .color(color(ink, status: playing?.status ?? signal)), style: FillStyle(antialiased: false))
                }
            }
        }
        // Idle's "z" drifts past the right edge, over where the running count would be (there is none then).
        .frame(width: CGFloat(Mascot.overflowWidth), height: CGFloat(Mascot.height))
        .padding(.trailing, CGFloat(Mascot.width - Mascot.overflowWidth))
        .accessibilityLabel(signal.map { "\($0)" } ?? "No sessions")
        .onChange(of: pulse) {
            guard !reduceMotion, let status = pulseStatus, let duration = Mascot.Mood(signal: status).reactionDuration else { return }
            let start = Date()
            reaction = (status, start)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                if reaction?.start == start { reaction = nil }
            }
        }
    }

    private func color(_ ink: Mascot.Ink, status: SessionStatus?) -> Color {
        switch ink {
        case .body: return online ? SessionStatus.color(status) : Color.gray.opacity(0.5)
        case .white: return .white
        case .dark: return Color(white: 0.04)
        case .faint: return .white.opacity(0.6)
        }
    }
}
