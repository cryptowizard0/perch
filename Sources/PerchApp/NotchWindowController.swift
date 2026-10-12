import AppKit
import Combine
import PerchAppCore
import SwiftUI

/// UI state of the notch that is not queue data: which screen, collapsed or expanded.
@MainActor
final class NotchModel: ObservableObject {
    @Published var geometry: NotchGeometry?
    @Published private(set) var expanded = false
    private var pendingHover: DispatchWorkItem?
    /// Dev aid: `PERCH_PIN_EXPANDED=1` keeps the notch open (screenshots, layout work without a mouse).
    private let pinned = ProcessInfo.processInfo.environment["PERCH_PIN_EXPANDED"] == "1"

    init() {
        expanded = pinned
    }

    /// Opens without a hover (the first-run card). It stays open until the pointer has been in and left.
    func open() {
        pendingHover?.cancel()
        expanded = true
    }

    /// Hover expands after a beat (so brushing past on the way to the menu bar does nothing)
    /// and collapses a little later (so a wobble at the edge does not flicker).
    func hover(_ inside: Bool) {
        guard !pinned else { return }
        pendingHover?.cancel()
        guard inside != expanded else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.expanded = inside }
        }
        pendingHover = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.12 : 0.3), execute: work)
    }
}

/// Owns the panel: keeps it on the right screen and sized for the current state.
@MainActor
final class NotchWindowController {
    let panel = NotchPanel()
    let notch: NotchModel
    let queue: QueueModel
    let setup: SetupModel
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []

    static let expandedWidth: CGFloat = 460

    init(notch: NotchModel, queue: QueueModel, setup: SetupModel, menu: NotchMenu) {
        self.notch = notch
        self.queue = queue
        self.setup = setup
        let host = NotchHostingView(rootView: NotchView(notch: notch, queue: queue, setup: setup, menu: menu))
        host.sizingOptions = []
        host.onHover = { [weak notch] inside in notch?.hover(inside) }
        panel.contentView = host
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        })
        // Resize when the state flips, and when rows come and go while expanded.
        notch.$expanded.removeDuplicates().dropFirst().sink { [weak self] expanded in
            DispatchQueue.main.async {
                self?.layout()
                // agents.json or a hook file may have changed from the CLI since the last look.
                if expanded { self?.setup.refresh() }
            }
        }.store(in: &cancellables)
        queue.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }.store(in: &cancellables)
        setup.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }.store(in: &cancellables)
    }

    func show() {
        layout()
        panel.orderFrontRegardless()
    }

    /// Re-reads the screens (plugged in, unplugged, resolution or arrangement changed) and resizes.
    func layout() {
        guard let screen = NotchGeometry.preferredScreen() else { return panel.orderOut(nil) }
        let geometry = NotchGeometry(screen: screen)
        if notch.geometry != geometry { notch.geometry = geometry }
        let wing = NotchGeometry.collapsedWing(runningCount: queue.panel.runningCount, online: queue.online)
        let frame = notch.expanded
            ? geometry.expandedFrame(size: CGSize(width: Self.expandedWidth, height: expandedHeight(band: geometry.bandHeight)))
            : geometry.collapsedFrame(leftWing: wing, rightWing: wing)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Band + the list's estimated height (see `PanelLayout`; it scrolls past the cap) + padding.
    private func expandedHeight(band: CGFloat) -> CGFloat {
        band + PanelLayout.listHeight(queue.panel(setup: setup.state), online: queue.online) + 16
    }
}

/// Hosting view that reports hover even though the panel is never key, and takes the first click
/// (otherwise the first click on a non-key window only focuses it).
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}
