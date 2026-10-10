import PerchAppCore
import PerchCore
import SwiftUI

/// The first-run card: the agents Perch found, each with a checkbox; Connect / Not now; then the result.
/// Nothing in an agent's config changes before Connect.
struct SetupCardView: View {
    var card: SetupCard
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set up Perch")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
            switch card.phase {
            case .choosing, .connecting:
                choosing
            case .finished(let lines):
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    CardLine(line: line)
                }
                buttons { SetupButton(title: "Done", prominent: true) { setup.closeCard() } }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
        .padding(.top, 6)
    }

    @ViewBuilder private var choosing: some View {
        if card.choices.isEmpty {
            Text("No Claude Code or Codex found on this Mac yet. Once one is set up, Perch offers to connect it here.")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            buttons { SetupButton(title: "OK", prominent: true) { setup.closeCard() } }
        } else {
            Text("Show these agents' sessions in the notch:")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.6))
            ForEach(card.choices, id: \.agent) { choice in
                Button { setup.toggleCardChoice(choice.agent) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: choice.checked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 13))
                            .foregroundStyle(choice.checked ? SessionStatus.color(.done) : .white.opacity(0.5))
                        Text(choice.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                        Text(setup.state.tilde(choice.config)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .frame(height: PanelLayout.cardLineHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(card.phase != .choosing)
            }
            buttons {
                if card.phase == .connecting { ProgressView().controlSize(.small).scaleEffect(0.6) }
                SetupButton(title: "Not now") { setup.closeCard() }
                    .disabled(card.phase != .choosing)
                SetupButton(title: "Connect", prominent: true) { setup.connectCard() }
                    .disabled(!card.canConnect)
                    .opacity(card.canConnect ? 1 : 0.4)
            }
        }
    }

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 8) {
            Spacer()
            content()
        }
        .padding(.top, 2)
    }
}

/// A result line under the card after Connect.
private struct CardLine: View {
    var line: SetupCard.Line

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                if let detail = line.detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(minHeight: PanelLayout.cardLineHeight, alignment: .leading)
    }

    private var icon: String {
        switch line.style {
        case .done: return "checkmark.circle.fill"
        case .next: return "arrow.right.circle.fill"
        case .problem: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch line.style {
        case .done: return SessionStatus.color(.running)
        case .next: return SessionStatus.color(.waiting)
        case .problem: return SessionStatus.color(.failed)
        }
    }
}

/// Setup rows above the session groups. Right-click dismisses one for this launch.
struct SetupRows: View {
    var rows: [SetupRow]
    @ObservedObject var setup: SetupModel

    var body: some View {
        Text("Setup")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
            .frame(height: PanelLayout.headerHeight, alignment: .bottom)
            .padding(.leading, 2)
        ForEach(rows) { row in
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon(row.kind)).font(.system(size: 12)).foregroundStyle(color(row.kind))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1).truncationMode(.middle)
                    if let detail = row.detail {
                        Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            .help(detail)
                    }
                }
                Spacer(minLength: 4)
                if let agent = row.connects {
                    SetupButton(title: "Connect", prominent: true) { setup.connect(agent) }
                }
            }
            .frame(minHeight: PanelLayout.setupRowHeight)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Dismiss") { setup.dismiss(row) }
            }
        }
    }

    private func icon(_ kind: SetupRow.Kind) -> String {
        switch kind {
        case .problem: return "exclamationmark.triangle.fill"
        case .trust: return "lock.shield"
        case .connect: return "plus.circle"
        case .updated: return "arrow.triangle.2.circlepath"
        }
    }

    private func color(_ kind: SetupRow.Kind) -> Color {
        switch kind {
        case .problem: return SessionStatus.color(.failed)
        case .trust: return SessionStatus.color(.waiting)
        case .connect: return SessionStatus.color(.done)
        case .updated: return .white.opacity(0.55)
        }
    }
}

/// A small pill button, like Allow / Deny.
struct SetupButton: View {
    var title: String
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(prominent ? Color(red: 0.2, green: 0.42, blue: 0.85) : .white.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}
