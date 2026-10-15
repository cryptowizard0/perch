import PerchAppCore
import PerchCore
import SwiftUI

/// The expanded band, left of the notch (#41): the Agents icon (the mascot) and the Todo icon (a checklist). The
/// current tab is white, the other gray. Agents carries an orange dot while a session needs you, else a red one while
/// one failed; Todo carries the open count, gray, hidden at 0. Clicking switches tabs.
struct TabStrip: View {
    @ObservedObject var queue: QueueModel

    var body: some View {
        let count = queue.todos.openCount
        HStack(spacing: 14) {
            tabButton(.agents, help: "Agents") {
                MascotIcon(color: color(.agents))
                    .overlay(alignment: .topTrailing) {
                        if let attention = queue.panel.attention {
                            Circle().fill(SessionStatus.color(attention))
                                .frame(width: 6, height: 6)
                                .offset(x: 3, y: 1)
                        }
                    }
            }
            tabButton(.todo, help: "Todo") {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color(.todo))
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
    }

    private func color(_ tab: PanelTab) -> Color {
        queue.tab == tab ? .white : .white.opacity(0.4)
    }

    private func tabButton(_ tab: PanelTab, help: String, @ViewBuilder label: () -> some View) -> some View {
        Button { queue.pick(tab) } label: {
            label().frame(minHeight: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The mascot's still frame in one colour, its eye and mouth cut out: the Agents tab's icon.
struct MascotIcon: View {
    var color: Color
    private static let cells = Mascot.still(.running)

    var body: some View {
        Canvas { context, _ in
            var lit = Path(), cut = Path()
            for cell in Self.cells {
                let rect = CGRect(x: CGFloat(cell.x), y: CGFloat(cell.y), width: 1, height: 1)
                switch cell.ink {
                case .body, .white: lit.addRect(rect)
                case .dark: cut.addRect(rect)
                case .faint, .confetti0, .confetti1, .confetti2: break
                }
            }
            context.fill(lit, with: .color(color), style: FillStyle(antialiased: false))
            context.fill(cut, with: .color(.black), style: FillStyle(antialiased: false))
        }
        .frame(width: CGFloat(Mascot.width), height: CGFloat(Mascot.height))
        .accessibilityLabel("Agents")
    }
}

/// The Todo tab: a big title over the summary line, then the open todos grouped High / Normal / Low, one line each.
struct TodoTab: View {
    @ObservedObject var queue: QueueModel

    var body: some View {
        let todos = queue.todos
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Todo").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                Text(queue.online ? todos.summary : " ").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.leading, 2)
            .frame(maxWidth: .infinity, minHeight: PanelLayout.titleHeight, alignment: .bottomLeading)
            if !queue.online {
                Text("perchd is not running — start it with `perchd` or `perchd install`")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, minHeight: PanelLayout.messageHeight)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(todos.groups) { group in
                            TodoGroupHeader(group: group)
                            ForEach(group.items) { item in
                                TodoRowView(item: item, completing: queue.completing.contains(item.id), queue: queue)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Like the Agents group header; High is white, the rest gray (priority never uses colour).
struct TodoGroupHeader: View {
    var group: TodoList.Group

    var body: some View {
        HStack(spacing: 6) {
            Text(group.title)
            Text("\(group.items.count)").monospacedDigit()
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white.opacity(group.priority == .high ? 0.95 : 0.5))
        .frame(height: PanelLayout.headerHeight, alignment: .bottom)
        .padding(.leading, 2)
    }
}

/// One todo: the circle and the title (tail-truncated, the full title in a tooltip). Clicking the circle crosses it
/// out with an Undo for a few seconds; clicking the title does nothing. Right-click: Priority.
struct TodoRowView: View {
    var item: Item
    var completing: Bool
    var queue: QueueModel

    var body: some View {
        let title = item.title.replacingOccurrences(of: "\n", with: " ")
        HStack(spacing: 8) {
            Button { queue.toggleCompletion(item) } label: {
                Image(systemName: completing ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(completing ? 0.6 : 0.55))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(completing ? "Undo" : "Complete")
            Text(title)
                .font(.system(size: 13))
                .strikethrough(completing)
                .foregroundStyle(.white.opacity(completing ? 0.4 : 0.95))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(title)
            Spacer(minLength: 4)
            if completing {
                Button("Undo") { queue.undoCompletion(item.id) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(height: PanelLayout.todoRowHeight)
        .padding(.leading, 1)
        .contentShape(Rectangle())
        .contextMenu {
            Menu("Priority") {
                ForEach(ItemPriority.allCases, id: \.self) { priority in
                    Toggle(priority.label, isOn: Binding(
                        get: { item.priority == priority },
                        set: { _ in queue.setPriority(item, priority) }
                    ))
                }
            }
        }
    }
}
