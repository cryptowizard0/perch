import AppKit
import Combine
import PerchAppCore
import PerchCore
import SwiftUI

/// The todo popup's window (#43): a non-activating panel that still becomes key, so you type into it while the app
/// you were in stays frontmost (the M2 quick-entry technique). Adding: Tab / Shift-Tab cycle the priority instead of
/// moving focus. Editing (#53, the larger editor): Tab moves between fields, and Return saves from any of them
/// (Shift- or Option-Return starts a new line in the notes). Esc or clicking elsewhere closes it. Always dark.
final class TodoPopupPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onTab: ((_ forward: Bool) -> Void)?
    /// Set while the larger editor shows: Return saves, Tab is left alone.
    var onReturn: (() -> Void)?

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
            case 48:  // kVK_Tab: adding cycles the priority; the larger editor moves between fields (notes included)
                if onReturn == nil {
                    onTab?(!event.modifierFlags.contains(.shift))
                } else if event.modifierFlags.contains(.shift) {
                    selectPreviousKeyView(nil)
                } else {
                    selectNextKeyView(nil)
                }
                return
            case 36, 76:  // Return, Enter: the larger editor saves (Shift / Option: a new line in the notes)
                guard let onReturn, event.modifierFlags.isDisjoint(with: [.shift, .option]) else { break }
                onReturn()
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
    /// The larger editor (#53), with its List row (#70).
    static let editorSize = CGSize(width: 440, height: 348)
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
        guard let opened else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        panel.onReturn = opened.mode == .add ? nil : { [weak queue] in queue?.submitEditor() }
        place()
        panel.makeKeyAndOrderFront(nil)
        focus.tick += 1
    }

    private func place() {
        guard let editor = queue.editor else { return }
        let size = editor.isLarge ? Self.editorSize : Self.size
        // Below the panel whenever it is expanded, even for a ⌥⇧Space popup the notch expanded under afterwards.
        guard let frame = notchWindow.popupFrame(size: size, belowPanel: editor.fromPanel || notchWindow.notch.expanded, gap: Self.gap)
        else { return }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
}

final class PopupFocus: ObservableObject {
    @Published var tick = 0
}

/// Adding: the small popup. Editing: the larger editor.
struct TodoPopupView: View {
    @ObservedObject var queue: QueueModel
    @ObservedObject var focus: PopupFocus

    var body: some View {
        Group {
            if queue.editor?.isLarge == true {
                TodoEditorView(queue: queue, focus: focus)
            } else {
                TodoAddView(queue: queue, focus: focus)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

/// The add popup (#43): the title field, and the list it goes in when more than one is checked (#70), over the High /
/// Normal / Low buttons. Everything it shows comes from `QueueModel.editor`.
struct TodoAddView: View {
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
                    .foregroundStyle(.white.opacity(editor?.canSubmit == true ? 0.85 : 0.35))
                TextField(editing ? "Todo" : "New todo", text: Binding(
                    get: { queue.editor?.title ?? "" },
                    set: { queue.editor?.title = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .focused($focused)
                .onSubmit { queue.submitEditor() }
                if queue.editorLists.count > 1 {
                    ListPicker(queue: queue, onPick: { focused = true })
                        .frame(maxWidth: 130)
                }
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
        .onAppear { focused = true }
        .onChange(of: focus.tick) { focused = true }
    }
}

/// The larger editor (#53), modeled on Reminders' detail view: title, notes, a date switch with an optional time,
/// High / Normal / Low, a URL and the list (#70; another one moves the todo). Repeat rules, alarms, subtasks, flags and
/// the rest stay as they are (✎ opens Reminders for those).
struct TodoEditorView: View {
    @ObservedObject var queue: QueueModel
    @ObservedObject var focus: PopupFocus
    @FocusState private var titleFocused: Bool

    private func binding<T>(_ keyPath: WritableKeyPath<TodoEditor, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { queue.editor?[keyPath: keyPath] ?? fallback }, set: { queue.editor?[keyPath: keyPath] = $0 })
    }

    var body: some View {
        let editor = queue.editor
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: binding(\.title, ""))
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .focused($titleFocused)
            ZStack(alignment: .topLeading) {
                if editor?.notes.isEmpty ?? true {
                    Text("Notes").font(.system(size: 13)).foregroundStyle(.white.opacity(0.3)).padding(.leading, 5)
                }
                TextEditor(text: binding(\.notes, ""))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .scrollContentBackground(.hidden)
            }
            .frame(height: 54)
            Divider().overlay(.white.opacity(0.1))
            row("calendar", "Date", isOn: Binding(
                get: { queue.editor?.hasDate ?? false },
                set: { on in queue.editor?.setHasDate(on, now: Date()) }
            )) {
                if editor?.hasDate == true {
                    DatePicker("", selection: binding(\.date, Date()), displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.field)
                }
            }
            row("clock", "Time", isOn: Binding(
                get: { queue.editor?.hasTime ?? false },
                set: { on in queue.editor?.setHasTime(on, now: Date()) }
            )) {
                if editor?.hasTime == true {
                    DatePicker("", selection: binding(\.date, Date()), displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.field)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark").frame(width: 18).foregroundStyle(.white.opacity(0.5))
                ForEach(ItemPriority.allCases, id: \.self) { priority in
                    let selected = editor?.priority == priority
                    Button { queue.editor?.priority = priority } label: {
                        Text(priority.label)
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(selected ? 0.22 : 0.06)))
                            .foregroundStyle(.white.opacity(selected ? 1 : 0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "list.bullet").frame(width: 18).foregroundStyle(.white.opacity(0.5))
                ListPicker(queue: queue)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .frame(height: 22)
            HStack(spacing: 6) {
                Image(systemName: "link").frame(width: 18).foregroundStyle(.white.opacity(0.5))
                TextField("URL", text: binding(\.url, ""))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            Text("↩ save · ⇧↩ new line in notes · esc cancel")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .onAppear { titleFocused = true }
        .onChange(of: focus.tick) { titleFocused = true }
    }

    private func row(_ icon: String, _ label: String, isOn: Binding<Bool>, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.white.opacity(0.5))
            Toggle(label, isOn: isOn)
                .toggleStyle(.switch).controlSize(.mini)
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 8)
            trailing()
        }
        .frame(height: 22)
    }
}

/// The popup's list picker (#70): `QueueModel.editorLists` (the checked lists; for a todo being edited, those it can
/// move to). Adding starts on "Perch".
struct ListPicker: View {
    @ObservedObject var queue: QueueModel
    var onPick: () -> Void = {}

    var body: some View {
        let lists = queue.editorLists
        Picker("List", selection: Binding(
            get: { queue.editorList?.id ?? "" },
            set: { id in
                queue.editor?.list = lists.first { $0.id == id }
                onPick()
            }
        )) {
            ForEach(lists, id: \.id) { list in
                Text(list.title).tag(list.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
    }
}
