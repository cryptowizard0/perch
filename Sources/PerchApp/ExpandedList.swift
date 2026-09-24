import AppKit
import PerchAppCore
import PerchCore
import SwiftUI

/// The queue, in the fixed order: request → waiting → overdue → today → other open → notice.
struct ExpandedList: View {
    @ObservedObject var queue: QueueModel

    static let rowHeight: CGFloat = 34
    static let messageHeight: CGFloat = 44

    var body: some View {
        let items = queue.ordered
        Group {
            if !queue.online {
                message("perchd is not running — start it with `perchd` or `perchd install`")
            } else if items.isEmpty {
                message("Nothing waiting.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            ItemRow(item: item, now: queue.now) { option in queue.click(item, option: option) }
                        }
                    }
                }
            }
            if let flash = queue.flash {
                Text(flash)
                    .font(.system(size: 11))
                    .foregroundStyle(Signal.overdue.color)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, minHeight: Self.messageHeight)
    }
}

struct ItemRow: View {
    var item: Item
    var now: Date
    /// Title clicked; the argument says whether ⌥ was held.
    var onClick: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: RowFormat.symbol(source: item.source))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 16)
                .help(item.source)
            title
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(RowFormat.time(item, now: now))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(timeColor)
                .fixedSize()
            JumpButton(link: item.link)
        }
        .padding(.vertical, 9)
        .frame(minHeight: ExpandedList.rowHeight)
    }

    @ViewBuilder private var title: some View {
        let text = Text(item.title)
            .font(.system(size: 13, weight: item.kind == .notice ? .regular : .medium))
            .foregroundStyle(.white.opacity(item.kind == .notice ? 0.6 : 0.95))
            // Requests always show their full text: never approve something you cannot read.
            .lineLimit(item.kind == .request ? nil : 1)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: item.kind == .request)
        if Click.on(item, option: false) == .none {
            text.help(item.title)
        } else {
            Button { onClick(NSEvent.modifierFlags.contains(.option)) } label: {
                text.strikethrough(hovering && item.kind == .task, color: .white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(item.kind == .notice ? "Click to keep as a task" : "Click: done · ⌥-click: snooze 30 min")
        }
    }

    private var isOverdue: Bool { item.isActionable && (item.dueAt.map { $0 <= now } ?? false) }

    private var accent: Color {
        if item.kind == .request || item.status == .waiting { return Signal.waiting.color }
        if isOverdue { return Signal.overdue.color }
        return .white.opacity(0.6)
    }

    private var timeColor: Color {
        isOverdue ? Signal.overdue.color : .white.opacity(0.45)
    }
}

/// Jumps to the item's link: the agent's terminal (Ghostty: the exact tab), a URL or a path.
struct JumpButton: View {
    var link: String?

    var body: some View {
        if let target = JumpTarget(link: link) {
            Button { Jumper.jump(link) } label: {
                Image(systemName: target.isTerminal ? "terminal" : "arrow.up.forward.square").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))
            .help(target.help)
        } else {
            Color.clear.frame(width: 12, height: 1)
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
