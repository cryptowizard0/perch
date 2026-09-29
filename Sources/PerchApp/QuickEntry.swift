import AppKit
import PerchAppCore
import PerchCore
import SwiftUI

/// Spotlight-style field under the notch. A non-activating panel that still becomes key, so you can type
/// without Perch taking focus from the app you were in; Return adds, Esc or clicking away closes.
final class QuickEntryPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        appearance = NSAppearance(named: .darkAqua)  // always black, whatever the system theme
    }

    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func resignKey() {
        super.resignKey()
        onCancel?()
    }
}

@MainActor
final class QuickEntryController {
    private let panel = QuickEntryPanel()
    private let field = QuickEntryField.Model()
    private let queue: QueueModel
    static let size = CGSize(width: 460, height: 64)

    init(queue: QueueModel) {
        self.queue = queue
        let host = NSHostingView(rootView: QuickEntryField(model: field))
        host.sizingOptions = []
        panel.contentView = host
        panel.onCancel = { [weak self] in self?.close() }
        field.submit = { [weak self] text in
            guard let self else { return }
            if self.queue.quickAdd(text) { self.close() }
        }
    }

    func toggle() {
        panel.isVisible ? close() : open()
    }

    func open() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        var frame = geometry.expandedFrame(size: Self.size)
        frame.origin.y -= geometry.bandHeight + 6  // just below the notch / menu bar
        panel.setFrame(frame, display: true)
        field.text = ""
        panel.makeKeyAndOrderFront(nil)
        field.focus += 1
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }
}

struct QuickEntryField: View {
    final class Model: ObservableObject {
        @Published var text = ""
        @Published var focus = 0
        var submit: (String) -> Void = { _ in }
    }

    @ObservedObject var model: Model
    @FocusState private var focused: Bool

    var body: some View {
        let parsed = QuickEntry.parse(model.text)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(SessionStatus.color(.done))
                TextField("New task — @15:00 or +30m sets a due time", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit { model.submit(model.text) }
            }
            Text(parsed.due.map { "due \(RowFormat.time(Item(title: parsed.title, dueAt: $0), now: Date()))" }
                 ?? "Return to add · Esc to cancel")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.leading, 26)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black))
        .onChange(of: model.focus) { focused = true }
    }
}
