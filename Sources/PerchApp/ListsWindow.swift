import AppKit
import Combine
import PerchAppCore
import PerchCore
import SwiftUI

/// The Lists… window (#70): every Reminders list as a row of drag handle, checkbox and name, in the selection's order.
/// Checking and dragging apply at once (`QueueModel.setListChecked` / `reorderLists`, which send a snapshot); "Perch"'s
/// checkbox is locked on, but it drags like the others. The same non-activating panel as the todo popup, so it opens
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

    func show() {
        queue.refreshLists()
        guard place() else { return }
        panel.makeKeyAndOrderFront(nil)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lists")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text("Checked lists show in the Todo tab and to agents.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            List {
                ForEach(queue.listChoices, id: \.list.id) { choice in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
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
                        Spacer(minLength: 0)
                    }
                    .frame(height: ListsWindowController.rowHeight - 6)
                    .help(choice.isLocked ? "\(choice.list.title) is always shown" : choice.list.title)
                }
                .onMove { from, to in
                    var ids = queue.listChoices.map(\.list.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    queue.reorderLists(ids)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, ListsWindowController.rowHeight)
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
}
