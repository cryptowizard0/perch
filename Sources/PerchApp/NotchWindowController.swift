import AppKit
import Combine
import PerchAppCore
import SwiftUI

/// UI state of the notch that is not queue data: which screen, collapsed or expanded.
@MainActor
final class NotchModel: ObservableObject {
    @Published var geometry: NotchGeometry?
    /// Right-click → Display (#37); the app delegate loads and saves it.
    @Published var display: DisplayChoice = .automatic
    /// The connected displays, for that menu; refreshed on every layout.
    @Published var screens: [DisplayScreen] = []
    @Published private(set) var expanded = false
    /// The collapsed band's wings as drawn. The right one grows while a banner shows; the controller animates it,
    /// keeping the window wide enough for the black shape to grow and shrink inside it.
    @Published var leftWing: CGFloat = 26
    @Published var rightWing: CGFloat = 26
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
    /// While the right wing shrinks, the window keeps its old width until the shape has finished.
    private var shrinkingFrom: CGFloat?
    private var shrinkDone: DispatchWorkItem?
    static let wingAnimation = 0.3

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
        notch.$display.removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }.store(in: &cancellables)
        // Resize when the state flips, and when rows come and go while expanded.
        notch.$expanded.removeDuplicates().dropFirst().sink { [weak self] expanded in
            // The list says it all: no banner while it is open, none saved for after.
            self?.queue.showsBanners = !expanded
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

    /// Re-reads the screens (plugged in, unplugged, resolution or arrangement changed), picks the chosen one and resizes.
    func layout() {
        let screens = NSScreen.screens
        let displays = screens.map(DisplayScreen.init(screen:))
        if notch.screens != displays { notch.screens = displays }
        guard let index = notch.display.screen(in: displays) else { return panel.orderOut(nil) }
        let geometry = NotchGeometry(screen: screens[index])
        if notch.geometry != geometry { notch.geometry = geometry }
        let left = NotchGeometry.collapsedWing(runningCount: queue.panel.runningCount, online: queue.online)
        let right = queue.banner.map { CGFloat(Banner.wing(contentWidth: BannerView.contentWidth($0))) } ?? left
        if notch.leftWing != left { notch.leftWing = left }
        if notch.expanded {
            endShrink()
            if notch.rightWing != right { notch.rightWing = right }
        } else if notch.rightWing != right {
            let old = notch.rightWing
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            withAnimation(reduceMotion ? nil : .easeInOut(duration: Self.wingAnimation)) { notch.rightWing = right }
            if right < old && !reduceMotion {
                // Narrow the window once the shape is in; a banner coming back meanwhile cancels that.
                shrinkingFrom = max(shrinkingFrom ?? 0, old)
                shrinkDone?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        self?.shrinkingFrom = nil
                        self?.layout()
                    }
                }
                shrinkDone = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.wingAnimation + 0.05, execute: work)
            } else {
                endShrink()
            }
        }
        let frame = notch.expanded
            ? geometry.expandedFrame(size: CGSize(width: Self.expandedWidth, height: expandedHeight(band: geometry.bandHeight)))
            : geometry.collapsedFrame(leftWing: left, rightWing: max(right, shrinkingFrom ?? 0))
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func endShrink() {
        shrinkDone?.cancel()
        shrinkDone = nil
        shrinkingFrom = nil
    }

    /// Band + the current tab's estimated height (see `PanelLayout`; it scrolls past the cap) + padding.
    private func expandedHeight(band: CGFloat) -> CGFloat {
        band + PanelLayout.listHeight(.agents, panel: queue.panel(setup: setup.state), online: queue.online) + 16
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
