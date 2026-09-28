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
                            if item.kind == .request {
                                RequestRow(item: item, now: queue.now, isHead: item.id == queue.headRequest?.id) { value in
                                    queue.respond(item, value)
                                }
                            } else {
                                ItemRow(item: item, now: queue.now) { option in
                                    Click.on(item, option: option) == .jump ? Jumper.jump(item.link) : queue.click(item, option: option)
                                }
                            }
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
            VStack(alignment: .leading, spacing: 3) {
                title
                if let hint = RowFormat.answerHint(item) {
                    // Not approvable here: say where, and why.
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(Signal.waiting.color.opacity(0.85))
                        .lineLimit(2)
                }
            }
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
            // Permission prompts always show their full command: never act on something you cannot read.
            .lineLimit(showsEverything ? nil : 1)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: showsEverything)
        if Click.on(item, option: false) == .none {
            text.help(item.title)
        } else {
            Button { onClick(NSEvent.modifierFlags.contains(.option)) } label: {
                text.strikethrough(hovering && item.kind == .task, color: .white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(help)
        }
    }

    private var showsEverything: Bool { item.meta?["tool"] != nil }

    private var help: String {
        switch Click.on(item, option: false) {
        case .keep: return "Click to keep as a task"
        case .jump: return "Waiting in the terminal: click to go there\(item.meta?["terminal_reason"].map { " (\($0))" } ?? "")"
        default: return "Click: done · ⌥-click: snooze 30 min"
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

/// A request an agent is blocked on: the full text, what it is for, and its answers.
/// Only requests that passed the allowlist get here with Allow; everything else is a "go to terminal" row.
struct RequestRow: View {
    var item: Item
    var now: Date
    /// First in the queue: ⌥⇧A / ⌥⇧D answer this one.
    var isHead: Bool
    var answer: (String) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: RowFormat.symbol(source: item.source))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Signal.waiting.color)
                .frame(width: 16)
                .help(item.source)
            VStack(alignment: .leading, spacing: 6) {
                // Full text, never truncated or summarised: never approve something you cannot read.
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let context {
                    Text(context).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                }
                HStack(spacing: 8) {
                    ForEach(item.options ?? [], id: \.self) { option in
                        Button { answer(option) } label: {
                            Text(label(option)).font(.system(size: 11.5, weight: .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6).fill(fill(option)))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                    if item.link != nil {
                        Button { Jumper.jump(item.link) } label: {
                            Label("Terminal", systemImage: "terminal").font(.system(size: 11.5))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    if isHead {
                        Text("⌥⇧A · ⌥⇧D").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(RowFormat.time(item, now: now))
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize()
        }
        .padding(.vertical, 9)
    }

    private var context: String? {
        let parts = [item.meta?["tool"].flatMap { $0 == "Bash" ? nil : $0 }, item.meta?["description"], item.meta?["project"]]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func label(_ option: String) -> String {
        option.prefix(1).uppercased() + option.dropFirst()
    }

    private func fill(_ option: String) -> Color {
        switch option {
        case "allow": return Color(red: 0.2, green: 0.55, blue: 0.3)
        case "deny": return Color(red: 0.55, green: 0.2, blue: 0.2)
        default: return .white.opacity(0.15)
        }
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
