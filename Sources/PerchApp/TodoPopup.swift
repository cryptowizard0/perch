import AppKit
import Combine
import PerchAppCore
import PerchCore
import SwiftUI

/// The todo popup's window (#43): a non-activating panel that still becomes key, so you type into it while the app
/// you were in stays frontmost (the M2 quick-entry technique). Tab / Shift-Tab cycle the priority instead of moving
/// focus; Esc or clicking elsewhere closes it. Always dark.
final class TodoPopupPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onTab: ((_ forward: Bool) -> Void)?

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
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func resignKey() {
        super.resignKey()
        onCancel?()
    }

    override func sendEvent(_ event: NSEvent) {
        // Before the text field sees them; an input method composing text keeps its keys.
        let composing = (firstResponder as? NSTextView)?.hasMarkedText() ?? false
        if event.type == .keyDown && !composing {
            switch Int(event.keyCode) {
            case 48:  // kVK_Tab
                onTab?(!event.modifierFlags.contains(.shift))
                return
            case 53:  // kVK_Escape
                onCancel?()
                return
            default: break
            }
        }
        super.sendEvent(event)
    }
}

/// Shows the popup while `QueueModel.editor` is set, where it was opened from: just below the folded notch (⌥⇧Space),
/// or just below the expanded panel, which stays open until the popup closes.
@MainActor
final class TodoPopupController {
    private let panel = TodoPopupPanel()
    private let queue: QueueModel
    private let notchWindow: NotchWindowController
    private let focus = PopupFocus()
    private var cancellables: Set<AnyCancellable> = []
    static let size = CGSize(width: 420, height: 88)
    static let gap: CGFloat = 8

    init(queue: QueueModel, notchWindow: NotchWindowController) {
        self.queue = queue
        self.notchWindow = notchWindow
        let host = NSHostingView(rootView: TodoPopupView(queue: queue, focus: focus))
        host.sizingOptions = []
        panel.contentView = host
        panel.onCancel = { [weak queue] in queue?.closeEditor() }
        panel.onTab = { [weak queue] forward in queue?.cycleEditorPriority(forward: forward) }
        queue.$editor
            .map { editor in editor.map { Opened(mode: $0.mode, fromPanel: $0.fromPanel) } }
            .removeDuplicates()
            .sink { [weak self] opened in
                // @Published sends before the change lands; act on the next pass.
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.show(opened) } }
            }
            .store(in: &cancellables)
        // The panel grows and shrinks as todos come and go; the popup stays just below it.
        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: notchWindow.panel)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.place() } }
            .store(in: &cancellables)
    }

    /// What decides where the popup goes and whether it starts over (a new todo, or editing another one).
    private struct Opened: Equatable {
        var mode: TodoEditor.Mode
        var fromPanel: Bool
    }

    /// ⌥⇧Space: opens it (below the panel if that happens to be expanded), or closes it.
    func toggle() {
        if queue.editor != nil {
            queue.closeEditor()
        } else {
            queue.openAdd(fromPanel: notchWindow.notch.expanded)
        }
    }

    private func show(_ opened: Opened?) {
        notchWindow.notch.held = opened?.fromPanel == true
        guard opened != nil else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        place()
        panel.makeKeyAndOrderFront(nil)
        focus.tick += 1
    }

    private func place() {
        guard let editor = queue.editor else { return }
        let size = Self.size
        var frame: CGRect
        if editor.fromPanel {
            let notch = notchWindow.panel.frame
            frame = CGRect(x: notch.midX - size.width / 2, y: notch.minY - Self.gap - size.height, width: size.width, height: size.height)
        } else {
            guard let geometry = notchWindow.notch.geometry else { return }
            frame = geometry.expandedFrame(size: size)
            frame.origin.y -= geometry.bandHeight + Self.gap
        }
        if panel.frame != frame { panel.setFrame(frame.integral, display: true) }
    }
}

final class PopupFocus: ObservableObject {
    @Published var tick = 0
}

/// The title field over the High / Normal / Low buttons. Everything it shows comes from `QueueModel.editor`.
struct TodoPopupView: View {
    @ObservedObject var queue: QueueModel
    @ObservedObject var focus: PopupFocus
    @FocusState private var focused: Bool

    var body: some View {
        let editor = queue.editor
        let editing = editor.map { $0.mode != .add } ?? false
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: editing ? "pencil.circle" : "plus.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
                TextField(editing ? "Todo" : "New todo", text: Binding(
                    get: { queue.editor?.title ?? "" },
                    set: { queue.editor?.title = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .focused($focused)
                .onSubmit { queue.submitEditor() }
            }
            HStack(spacing: 6) {
                ForEach(ItemPriority.allCases, id: \.self) { priority in
                    let selected = editor?.priority == priority
                    Button {
                        queue.editor?.priority = priority
                        focused = true
                    } label: {
                        Text(priority.label)
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(selected ? 0.22 : 0.06)))
                            .foregroundStyle(.white.opacity(selected ? 1 : 0.55))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 8)
                Text("⇥ priority · ↩ \(editing ? "save" : "add") · esc close")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            .padding(.leading, 23)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .onAppear { focused = true }
        .onChange(of: focus.tick) { focused = true }
    }
}
