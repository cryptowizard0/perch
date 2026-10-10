import AppKit
import PerchAppCore
import PerchCore
import SwiftUI

/// What the expanded notch can show. Only agents for now; todo comes back as a second tab later,
/// which is when a tab bar appears.
enum PanelTab {
    case agents
}

/// The expanded notch: the current tab's content, then a failed action's message if any.
struct ExpandedPanel: View {
    @ObservedObject var queue: QueueModel
    @ObservedObject var setup: SetupModel
    var tab: PanelTab = .agents

    var body: some View {
        VStack(spacing: 0) {
            switch tab {
            case .agents: SessionList(queue: queue, setup: setup)
            }
            if let flash = queue.flash {
                Text(flash)
                    .font(.system(size: 11))
                    .foregroundStyle(SessionStatus.color(.failed))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

/// Setup (the first-run card or setup rows) on top, then sessions grouped by state, most urgent group first, with the
/// count in each header.
struct SessionList: View {
    @ObservedObject var queue: QueueModel
    @ObservedObject var setup: SetupModel

    var body: some View {
        let panel = queue.panel(setup: setup.state)
        let sections = panel.sections
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    switch section {
                    case .card(let card):
                        SetupCardView(card: card, setup: setup)
                    case .setup(let rows):
                        SetupRows(rows: rows, setup: setup)
                    case .group(let group):
                        if queue.online { groupView(group, panel: panel) }
                    }
                }
                if !queue.online {
                    message("perchd is not running — start it with `perchd` or `perchd install`")
                } else if panel.sessions.isEmpty {
                    message("No agent sessions.")
                }
            }
        }
    }

    @ViewBuilder private func groupView(_ group: Panel.Group, panel: Panel) -> some View {
        GroupHeader(group: group)
        ForEach(group.sessions) { session in
            SessionRowView(session: session, request: panel.request(for: session), now: queue.now) { request, answer in
                queue.respond(request, answer)
            }
            .contentShape(Rectangle())
            .onTapGesture { queue.open(session) }
            .contextMenu {
                Button("Remove from Panel") { queue.remove(session) }
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, minHeight: PanelLayout.messageHeight)
    }
}

struct GroupHeader: View {
    var group: Panel.Group

    var body: some View {
        HStack(spacing: 6) {
            Text(group.title).font(.system(size: 11, weight: .semibold))
            Text("\(group.sessions.count)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(SessionStatus.color(group.status))
        }
        .foregroundStyle(.white.opacity(0.5))
        .frame(height: PanelLayout.headerHeight, alignment: .bottom)
        .padding(.leading, 2)
    }
}

/// One session: dot, agent icon, project, time, where a click goes; the second line depends on the state.
/// Clicking anywhere on the row (but Allow / Deny) jumps there. Needs you shows the full text, never truncated
/// (never approve something you cannot read), with Allow / Deny only when the request passed the allowlist.
struct SessionRowView: View {
    var session: Session
    var request: Item?
    var now: Date
    var answer: (Item, String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StatusDot(status: session.status)
                .frame(height: 16)
            PixelIconView(icon: .for(agent: session.source))
                .frame(height: 16)
                .help(session.source)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(SessionRow.time(session, now: now))
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize()
                    JumpIcon(link: session.link)
                }
                secondLine
            }
        }
        .padding(.vertical, 6)
        .opacity(session.status == .idle ? 0.45 : 1)
    }

    @ViewBuilder private var secondLine: some View {
        if session.status == .waiting {
            // With a request, its own text: Allow / Deny answer exactly what is shown here.
            let parts = SessionRow.needsYou(session, request: request)
            Text(parts.text)
                .font(.system(size: 12, weight: parts.isCommand ? .medium : .regular, design: parts.isCommand ? .monospaced : .default))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            if let hint = parts.hint {
                Text(hint).font(.system(size: 11)).foregroundStyle(SessionStatus.color(.waiting).opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let request {
                HStack(spacing: 8) {
                    ForEach(request.options ?? [], id: \.self) { option in
                        Button { answer(request, option) } label: {
                            Text(option.prefix(1).uppercased() + option.dropFirst())
                                .font(.system(size: 11.5, weight: .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6).fill(fill(option)))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                }
                .padding(.top, 3)
            }
        } else if let line = SessionRow.detail(session)?.split(separator: "\n").first {
            Text(String(line))
                .font(.system(size: 11.5))
                .foregroundStyle(session.status == .failed ? SessionStatus.color(.failed) : .white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func fill(_ option: String) -> Color {
        switch option {
        case "allow": return Color(red: 0.2, green: 0.55, blue: 0.3)
        case "deny": return Color(red: 0.55, green: 0.2, blue: 0.2)
        default: return .white.opacity(0.15)
        }
    }
}

/// A `PixelIcon`, 12 pt square, `cellSize` per cell, no antialiasing.
struct PixelIconView: View {
    var icon: PixelIcon
    var color: Color = .white.opacity(0.85)

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            let side = icon.cellSize
            for cell in icon.cells {
                path.addRect(CGRect(x: Double(cell.x) * side, y: Double(cell.y) * side, width: side, height: side))
            }
            context.fill(path, with: .color(color))
        }
        .frame(width: CGFloat(PixelIcon.size), height: CGFloat(PixelIcon.size))
        .drawingGroup(opaque: false, colorMode: .nonLinear)
    }
}

/// Where clicking the row goes: the agent's terminal (Ghostty: the exact tab), a URL or a path.
struct JumpIcon: View {
    var link: String?
    /// Same with or without a link, so times line up.
    static let width: CGFloat = 18

    var body: some View {
        if let target = JumpTarget(link: link) {
            Image(systemName: target.isTerminal ? "terminal" : "arrow.up.forward.square").font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: Self.width)
                .help(target.help)
        } else {
            Color.clear.frame(width: Self.width, height: 1)
        }
    }
}

extension JumpTarget {
    var isTerminal: Bool {
        if case .terminal = self { return true }
        return false
    }

    var help: String {
        switch self {
        case .terminal(let t): return "Back to \(t.app == "ghostty" ? "Ghostty" : t.app)" + (t.cwd.map { " · \($0)" } ?? "")
        case .open(let url): return url.isFileURL ? url.path : url.absoluteString
        }
    }
}
