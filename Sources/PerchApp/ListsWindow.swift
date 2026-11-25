import AppKit
import Combine
import PerchAppCore
import PerchCore
import SwiftUI

/// The Lists… window (#70): every Reminders list as a row of drag handle, checkbox and name, in the selection's order.
/// Checking and dragging apply at once (`QueueModel.setListChecked` / `reorderLists`, which send a snapshot); "Perch"'s
/// checkbox is locked on, but it drags like the others. Dragging is a plain mouse drag (`ListDrag`), not drag and drop. The same non-activating panel as the todo popup, so it opens
/// without taking focus from the app you were in; Esc or clicking elsewhere closes it. Always dark.
@MainActor
final class ListsWindowController {
    private let panel = TodoPopupPanel()
    private let queue: QueueModel
    private let notchWindow: NotchWindowController
    private var cancellables: Set<AnyCancellable> = []
    static let width: CGFloat = 300
    static let rowHeight: CGFloat = 28
    /// The title, the line under it and the hint at the bottom, with the padding.
    static let chrome: CGFloat = 92
    static let maxRows = 12

    init(queue: QueueModel, notchWindow: NotchWindowController) {
        self.queue = queue
        self.notchWindow = notchWindow
        let host = NSHostingView(rootView: ListsView(queue: queue))
        host.sizingOptions = []
        panel.contentView = host
        panel.onCancel = { [weak self] in self?.close() }
        // Lists come and go (in Reminders, or access goes): the window grows and shrinks with them.
        queue.$listChoices
            .map(\.count)
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { _ = self?.place() } }
            }
            .store(in: &cancellables)
    }

    /// From the notch's right-click menu, so it waits for the next pass: a window made key while the menu is still
    /// tracking loses key when the menu closes (it goes back to the app you were in), and then Esc never reaches it.
    /// The todo popup's Edit… gets this for free by going through `QueueModel.editor`.
    func show() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.queue.refreshLists()
                guard self.place() else { return }
                self.panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    func close() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    /// Just below the folded notch, or below the panel while it is expanded (like the todo popup). False when the
    /// notch has no place yet.
    @discardableResult
    private func place() -> Bool {
        let rows = min(max(queue.listChoices.count, 1), Self.maxRows)
        let size = CGSize(width: Self.width, height: Self.chrome + CGFloat(rows) * Self.rowHeight)
        guard let frame = notchWindow.popupFrame(size: size, belowPanel: notchWindow.notch.expanded, gap: TodoPopupController.gap)
        else { return false }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        return true
    }
}

struct ListsView: View {
    @ObservedObject var queue: QueueModel
    /// The row being dragged, while it is.
    @State private var drag: ListDrag?
    private static let rowHeight = ListsWindowController.rowHeight

    var body: some View {
        let choices = queue.listChoices
        VStack(alignment: .leading, spacing: 4) {
            Text("Lists")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text("Checked lists show in the Todo tab and to agents.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            // Not a List with .onMove: its drag and drop left the window without the keyboard (`ListDrag`).
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(choices.enumerated()), id: \.element.list.id) { index, choice in
                        ListChoiceRow(choice: choice, last: index == choices.count - 1, lifted: drag?.from == index, queue: queue)
                            .offset(y: offset(of: index, count: choices.count))
                            .zIndex(drag?.from == index ? 1 : 0)
                            .animation(drag?.from == index ? nil : .easeOut(duration: 0.15), value: drag?.shift(of: index))
                            .gesture(reorder(from: index, count: choices.count))
                    }
                }
                .padding(.top, 2)
                .coordinateSpace(name: Self.space)
            }
            Text("drag to reorder · esc close")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    private static let space = "lists"

    /// The dragged row follows the pointer (kept within the list); the rows it passes step aside.
    private func offset(of index: Int, count: Int) -> CGFloat {
        guard let drag else { return 0 }
        guard index == drag.from else { return CGFloat(drag.shift(of: index)) * Self.rowHeight }
        let lowest = -CGFloat(drag.from) * Self.rowHeight
        let highest = CGFloat(count - 1 - drag.from) * Self.rowHeight
        return min(max(drag.offset, lowest), highest)
    }

    /// Drag anywhere on a row (the checkbox keeps its click). Translation in the list's space, since the row moves.
    private func reorder(from index: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                drag = ListDrag(from: index, offset: value.translation.height, rowHeight: Self.rowHeight, count: count)
            }
            .onEnded { value in
                let done = ListDrag(from: index, offset: value.translation.height, rowHeight: Self.rowHeight, count: count)
                drag = nil
                let ids = queue.listChoices.map(\.list.id)
                let next = done.reordered(ids)
                if next != ids { queue.reorderLists(next) }
            }
    }
}

/// One list: drag handle, checkbox, name, and a hairline under the name like the table it replaced.
private struct ListChoiceRow: View {
    var choice: ListChoice
    var last: Bool
    var lifted: Bool
    var queue: QueueModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(lifted ? 0.7 : 0.35))
            Toggle("", isOn: Binding(
                get: { choice.isChecked },
                set: { queue.setListChecked(choice.list.id, $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(choice.isLocked)
            Text(choice.list.title)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(choice.isChecked ? 0.9 : 0.55))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    if !last && !lifted { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
                }
        }
        .padding(.leading, 9)
        .frame(height: ListsWindowController.rowHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(lifted ? 0.1 : 0)))
        .contentShape(Rectangle())
        .help(choice.isLocked ? "\(choice.list.title) is always shown" : choice.list.title)
    }
}
