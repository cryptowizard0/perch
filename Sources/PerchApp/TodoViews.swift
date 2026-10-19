import AppKit
import PerchAppCore
import PerchCore
import SwiftUI

/// The expanded band, left of the notch (#41): the Agents icon (the mascot) and the Todo icon (a checklist). The
/// current tab is white, the other gray. Agents carries an orange dot while a session needs you, else a red one while
/// one failed; Todo carries the open count, gray, hidden at 0 (and while the Reminders list can't be read). Clicking
/// switches tabs.
struct TabStrip: View {
    @ObservedObject var queue: QueueModel

    var body: some View {
        let count = queue.showsTodos ? queue.todos.openCount : 0
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

/// The Todo tab: a big title over the summary line, then the open todos grouped by Reminders list (#69), one line each:
/// "Perch" and the other checked lists, in the selection's order, empty ones with a gray "All clear". Without the
/// "Perch" list (#51), the tab is a line and one button.
struct TodoTab: View {
    @ObservedObject var queue: QueueModel

    var body: some View {
        let todos = queue.todos
        let reminders = queue.reminders ?? .ready(iCloud: true)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Todo").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                Text(queue.online && reminders.isReady ? todos.summary : " ")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.leading, 2)
            .frame(maxWidth: .infinity, minHeight: PanelLayout.titleHeight, alignment: .bottomLeading)
            if !reminders.isReady {
                RemindersPrompt(state: reminders, listName: queue.remindersListName, queue: queue)
            } else if !queue.online {
                Text("perchd is not running — start it with `perchd` or `perchd install`")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, minHeight: PanelLayout.messageHeight)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(todos.groups) { group in
                            TodoGroupHeader(group: group)
                            if group.items.isEmpty {
                                Text("All clear")
                                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.4))
                                    .frame(height: PanelLayout.todoRowHeight)
                                    .padding(.leading, 2)
                            }
                            ForEach(group.items) { item in
                                TodoRowView(item: item, completing: queue.completing.contains(item.id),
                                            highlighted: queue.highlighted.contains(item.id),
                                            due: TodoList.dueLabel(item, now: queue.now), queue: queue)
                            }
                        }
                    }
                }
                AddTodoRow { queue.openAdd(fromPanel: true) }
            }
        }
    }
}

/// The Todo tab without the list: why, and the one thing to do about it.
struct RemindersPrompt: View {
    var state: RemindersState
    var listName: String
    var queue: QueueModel

    var body: some View {
        VStack(spacing: 10) {
            if let message = state.message(listName: listName) {
                Text(message).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            }
            if let button = state.button(listName: listName) {
                Button(button, action: act)
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.9)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: PanelLayout.remindersHeight)
    }

    private func act() {
        switch state {
        case .connect:
            Task { @MainActor in await queue.connectReminders() }
        case .openSettings:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
        case .createList:
            queue.createRemindersList()
        case .ready:
            break
        }
    }
}

/// Like the Agents group header, all gray: the list's name and open count, never the list's colour (#69). A list that
/// isn't in iCloud says "Not syncing".
struct TodoGroupHeader: View {
    var group: TodoList.Group

    var body: some View {
        HStack(spacing: 6) {
            Text(group.title).lineLimit(1)
            Text("\(group.openCount)").monospacedDigit()
            if group.notSyncing { Text("· Not syncing").fontWeight(.regular) }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white.opacity(0.5))
        .frame(height: PanelLayout.headerHeight, alignment: .bottom)
        .padding(.leading, 2)
    }
}

/// "+ Add a todo", fixed under the list: opens the popup just below the panel.
struct AddTodoRow: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 15)
                Text("Add a todo").font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(0.5))
            .frame(height: PanelLayout.addRowHeight)
            .padding(.leading, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One todo: `○ title … date ✎` (#53). Clicking the circle or the title crosses it out with an Undo for a few seconds
/// (clicking again undoes); double-clicking does nothing more. The date is gray, white once overdue; hovering the row
/// shows the full title and date. ✎ opens the reminder in Reminders. Right-click: Edit… · Priority ▸ · Delete.
/// A todo just added while the panel is open is lit for a second.
struct TodoRowView: View {
    var item: Item
    var completing: Bool
    var highlighted = false
    var due: TodoList.DueLabel?
    var queue: QueueModel

    var body: some View {
        let title = item.title.replacingOccurrences(of: "\n", with: " ")
        let tooltip = due.map { "\(title)\n\($0.full)" } ?? title
        HStack(spacing: 8) {
            Button { queue.toggleCompletion(item) } label: {
                HStack(spacing: 8) {
                    Image(systemName: completing ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(completing ? 0.6 : 0.55))
                    Text(title)
                        .font(.system(size: 13))
                        .strikethrough(completing)
                        .foregroundStyle(.white.opacity(completing ? 0.4 : 0.95))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(completing ? "Undo" : tooltip)
            Spacer(minLength: 4)
            if completing {
                Button("Undo") { queue.undoCompletion(item.id) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            } else if let due {
                Text(due.text)
                    .font(.system(size: 11.5)).monospacedDigit()
                    .foregroundStyle(.white.opacity(due.overdue ? 0.95 : 0.45))
                    .lineLimit(1)
                    .fixedSize()
                    .help(tooltip)
            }
            Button { queue.openInReminders(item) } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in Reminders")
        }
        .frame(height: PanelLayout.todoRowHeight)
        .padding(.leading, 1)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(.white.opacity(highlighted ? 0.14 : 0)).padding(.horizontal, -4)
                .animation(.easeOut(duration: 0.4), value: highlighted)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit…") { queue.openEdit(item) }
            Menu("Priority") {
                ForEach(ItemPriority.allCases, id: \.self) { priority in
                    Toggle(priority.label, isOn: Binding(
                        get: { item.priority == priority },
                        set: { _ in queue.setPriority(item, priority) }
                    ))
                }
            }
            Divider()
            Button("Delete") { queue.delete(item) }
        }
    }
}
