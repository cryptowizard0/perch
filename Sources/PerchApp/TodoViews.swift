import AppKit
import PerchAppCore
import PerchCore
import SwiftUI

/// The expanded band (#83): the two columns' headings, kept clear of the notch. "Agents" at the far left, "Todo" and its
/// summary ("6 open · 2 high", "All clear") at the far right; no summary while the list can't be read.
struct ExpandedBand: View {
    @ObservedObject var queue: QueueModel

    var body: some View {
        let ready = queue.online && (queue.reminders ?? .ready(iCloud: true)).isReady
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                MascotIcon(color: .white)
                Text("Agents")
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "checklist").font(.system(size: 12, weight: .semibold))
                Text("Todo")
                if ready {
                    Text(queue.todos.summary).fontWeight(.regular).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(.white.opacity(0.95))
        .padding(.horizontal, 14)
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

/// The Todo column, right of the notch (#83): the open todos grouped by Reminders list (#69), one line each: "Perch" and
/// the other checked lists, in the selection's order, empty ones with a gray "All clear". Without the "Perch" list
/// (#51), a line and one button. The summary line is in the band.
struct TodoColumn: View {
    @ObservedObject var queue: QueueModel

    var body: some View {
        let todos = queue.todos
        let reminders = queue.reminders ?? .ready(iCloud: true)
        VStack(alignment: .leading, spacing: 0) {
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
                // No taller than the groups, so "+ Add a todo" sits right under them while the Agents column is the
                // taller one (#83); past the cap it scrolls and the row stays put.
                .frame(maxHeight: PanelLayout.todoHeight(todos) - PanelLayout.addRowHeight)
                AddTodoRow { queue.openAdd(fromPanel: true) }
            }
        }
    }
}

/// The Todo column without the list: why, and the one thing to do about it.
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

/// One todo: `○ title … date ▶ capsule ✎` (#53, #71). Clicking the circle or the title crosses it out with an Undo for a
/// few seconds (clicking again undoes); double-clicking does nothing more. The date is gray, white once overdue; hovering
/// the row shows the full title and date. ▶ toggles Doing: gray and only while the pointer is on the row, or white and
/// filled on a Doing row, which also gets a light background, a bold title and a soft light sweeping across it every few
/// seconds (`DoingShimmer`, #86; still under Reduce Motion) so it stands out. The capsule is the
/// priority; clicking it pops up High / Normal / Low (#85). ✎ opens the reminder in Reminders.
/// Right-click: Edit… · Priority ▸ · Delete.
/// A todo just added while the panel is open is lit for a second.
struct TodoRowView: View {
    var item: Item
    var completing: Bool
    var highlighted = false
    var due: TodoList.DueLabel?
    var queue: QueueModel
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let doing = item.doing && !completing
        let title = item.title.replacingOccurrences(of: "\n", with: " ")
        let tooltip = due.map { "\(title)\n\($0.full)" } ?? title
        HStack(spacing: 8) {
            Button { queue.toggleCompletion(item) } label: {
                HStack(spacing: 8) {
                    Image(systemName: completing ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(completing ? 0.6 : 0.55))
                    Text(title)
                        .font(.system(size: 13, weight: doing ? .semibold : .regular))
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
            let showsDoing = !completing && (item.doing || hovering)
            Button { queue.toggleDoing(item) } label: {
                Image(systemName: item.doing ? "play.fill" : "play")
                    .font(.system(size: doing ? 11 : 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(item.doing ? 0.95 : 0.45))
                    .frame(width: 14, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(showsDoing ? 1 : 0)
            .allowsHitTesting(showsDoing)
            .help(item.doing ? "Doing — click to clear" : "Mark as Doing")
            PriorityCapsule(priority: item.priority)
                .overlay {
                    if !completing {
                        PriorityMenuArea(current: item.priority) { queue.setPriority(item, $0) }
                            .help("Priority")
                    }
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
            RoundedRectangle(cornerRadius: 6).fill(.white.opacity(highlighted ? 0.14 : doing ? 0.08 : 0))
                .overlay { if doing && !reduceMotion { DoingShimmerView() } }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, -4)
                .animation(.easeOut(duration: 0.4), value: highlighted)
        )
        .contentShape(Rectangle())
        .background(HoverTracker { hovering = $0 })
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

/// The light sweeping across a Doing row (#86), left to right on the shared clock (`DoingShimmer`), so several Doing rows sweep
/// together. Only exists while the panel is open, so it costs nothing collapsed.
struct DoingShimmerView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
            GeometryReader { geometry in
                let width = geometry.size.width
                let center = DoingShimmer.center(at: timeline.date.timeIntervalSinceReferenceDate)
                LinearGradient(colors: [.clear, .white.opacity(DoingShimmer.peak), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: width * DoingShimmer.band)
                    .offset(x: width * (center - DoingShimmer.band / 2))
            }
        }
        .allowsHitTesting(false)
    }
}

/// A todo's priority (#71): its name on a translucent capsule of the same colour. High orange, Normal gray (the faintest,
/// so the many Normal rows recede), Low green. A click on it pops up the choice (`PriorityMenuArea`, #85).
struct PriorityCapsule: View {
    var priority: ItemPriority

    var body: some View {
        Text(priority.label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color.opacity(priority == .normal ? 0.5 : 0.95))
            .padding(.horizontal, 6)
            .frame(height: 15)
            .background(Capsule().fill(color.opacity(priority == .normal ? 0.1 : 0.2)))
            .fixedSize()
    }

    /// Needs you's orange and Running's green: accepted (#66) because capsules only appear in the Todo tab.
    private var color: Color {
        switch priority {
        case .high: return SessionStatus.color(.waiting)
        case .normal: return .white
        case .low: return SessionStatus.color(.running)
        }
    }
}

/// Clicking the priority capsule (#85): High / Normal / Low pop up over it like a pop-up button, the current one checked
/// and drawn where the capsule is; choosing one writes it, anything else leaves it alone. An AppKit menu, like the row's
/// right-click menu, because the notch panel is never key.
struct PriorityMenuArea: NSViewRepresentable {
    var current: ItemPriority
    var pick: (ItemPriority) -> Void

    func makeNSView(context: Context) -> MenuView {
        MenuView()
    }

    func updateNSView(_ view: MenuView, context: Context) {
        view.current = current
        view.pick = pick
    }

    final class MenuView: NSView {
        var current: ItemPriority = .normal
        var pick: ((ItemPriority) -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for priority in ItemPriority.allCases {
                let item = NSMenuItem(title: priority.label, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = priority.rawValue
                item.state = priority == current ? .on : .off
                menu.addItem(item)
            }
            let checked = menu.items.first { $0.state == .on }
            menu.popUp(positioning: checked, at: NSPoint(x: 0, y: isFlipped ? 0 : bounds.height), in: self)
        }

        @objc private func choose(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let priority = ItemPriority(rawValue: raw) else { return }
            pick?(priority)
        }
    }
}

/// Reports the pointer entering and leaving its frame even though the notch panel is never key (SwiftUI's own hover
/// follows the key window), like `NotchHostingView` does for the whole panel. A row that appears (or moves) under the
/// pointer gets no entered event, so it also looks where the pointer is whenever its area is set up. Never takes a click.
struct HoverTracker: NSViewRepresentable {
    var changed: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        TrackingView()
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.changed = changed
    }

    final class TrackingView: NSView {
        var changed: ((Bool) -> Void)?
        private var tracking: NSTrackingArea?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
            // After this layout pass: SwiftUI state mustn't change while it updates views.
            if let window {
                let inside = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
                DispatchQueue.main.async { [weak self] in self?.changed?(inside) }
            }
        }

        override func mouseEntered(with event: NSEvent) { changed?(true) }
        override func mouseExited(with event: NSEvent) { changed?(false) }
    }
}
