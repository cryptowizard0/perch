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
    /// Drawn open: the black shape at the panel's size, the panel's content in it. Lags `expanded` by the open and close
    /// animations (`NotchMotion`); the controller sets it.
    @Published var isOpen = false
    /// The open shape's height, band included; animates as rows come and go.
    @Published var openHeight: CGFloat = 0
    /// Where the band starts in the window: 0 while the window is the band, more while it is the expanded frame.
    @Published var bandX: CGFloat = 0
    /// Kept expanded while the todo popup opened from the panel is up (#43); hover-collapse resumes when it closes.
    var held = false {
        didSet {
            guard held != oldValue, !held, !pointerInside else { return }
            hover(false)
        }
    }
    /// Where the pointer was at the last hover change.
    private var pointerInside = false
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

    /// Collapses now (✎ left for the Reminders app). Hovering again expands it as usual.
    func close() {
        pendingHover?.cancel()
        guard !pinned else { return }
        expanded = false
    }

    /// Hover expands after a beat (so brushing past on the way to the menu bar does nothing)
    /// and collapses a little later (so a wobble at the edge does not flicker).
    func hover(_ inside: Bool) {
        guard !pinned else { return }
        pointerInside = inside
        pendingHover?.cancel()
        guard inside != expanded, inside || !held else { return }
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
    private let host: NotchHostingView<NotchView>
    let notch: NotchModel
    let queue: QueueModel
    let setup: SetupModel
    /// Where the folded mascot looks (#63). No pointer monitor at all under Reduce Motion.
    let gaze = GazeTracker(monitor: AppKitPointerMonitor(), reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    /// While the right wing shrinks, the window keeps its old width until the shape has finished.
    private var shrinkingFrom: CGFloat?
    private var shrinkDone: DispatchWorkItem?
    static let wingAnimation = 0.3
    /// Opening and closing: the shape grows out of the band and shrinks back onto it.
    private var motion = NotchMotion()
    private var motionDone: DispatchWorkItem?
    static let openAnimation = Animation.spring(response: NotchMotion.openDuration, dampingFraction: 0.9)
    static let closeAnimation = Animation.timingCurve(0.4, 0, 0.2, 1, duration: NotchMotion.closeDuration)
    static let resizeAnimation = Animation.easeInOut(duration: NotchMotion.resizeDuration)
    /// Agents and Todo side by side (#83), split under the notch.
    static let expandedWidth: CGFloat = 760

    init(notch: NotchModel, queue: QueueModel, setup: SetupModel, menu: NotchMenu) {
        self.notch = notch
        self.queue = queue
        self.setup = setup
        host = NotchHostingView(rootView: NotchView(notch: notch, queue: queue, setup: setup, gaze: gaze, menu: menu))
        host.sizingOptions = []
        host.onHover = { [weak notch] inside in notch?.hover(inside) }
        panel.contentView = host
        // The local pointer monitor sees moves over the panel itself.
        panel.acceptsMouseMovedEvents = true
        gaze.locate = { [weak self] in self?.mascotSpot() }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self?.gaze.reduceMotion = reduceMotion
                self?.queue.reduceMotion = reduceMotion
            }
        })
        queue.expanded = notch.expanded
        queue.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
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
            self?.queue.expanded = expanded
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

    /// Where a popup of `size` goes (the todo popup, the Lists… window): just below the expanded panel when
    /// `belowPanel`, else just below the folded notch. Nil before the notch has a place.
    func popupFrame(size: CGSize, belowPanel: Bool, gap: CGFloat) -> CGRect? {
        if belowPanel {
            let notch = panel.frame
            // The window may still be taller than the panel drawn in it (`NotchMotion`).
            let bottom = motion.phase == .collapsed ? notch.minY : notch.maxY - motion.height
            return CGRect(x: notch.midX - size.width / 2, y: bottom - gap - size.height, width: size.width, height: size.height).integral
        }
        guard let geometry = notch.geometry else { return nil }
        var frame = geometry.expandedFrame(size: size)
        frame.origin.y -= geometry.bandHeight + gap
        return frame.integral
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
        let left = NotchGeometry.collapsedWing(runningCount: queue.panel.runningCount, online: queue.online,
                                               todoCount: queue.collapsedTodoCount)
        let right = queue.banner.map {
            CGFloat(Banner.wing(contentWidth: BannerView.contentWidth($0), carried: queue.carriesBanner))
        } ?? left
        queue.notchWidth = Double(geometry.notch?.width ?? 0)
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
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let step = motion.update(expanded: notch.expanded,
                                 height: notch.expanded ? expandedHeight(band: geometry.bandHeight) : 0, reduceMotion: reduceMotion)
        let band = geometry.collapsedFrame(leftWing: left, rightWing: max(right, shrinkingFrom ?? 0))
        let frame = motion.windowHeight.map {
            geometry.expandedFrame(size: CGSize(width: Self.expandedWidth, height: $0))
        } ?? band
        if notch.bandX != band.minX - frame.minX { notch.bandX = band.minX - frame.minX }
        // Growing out of the band: the window takes the expanded frame (the band drawn where it was) before it starts.
        var growFromBand = false
        switch step {
        case .none:
            break
        case .open(let fromBand):
            if fromBand && !reduceMotion {
                notch.openHeight = motion.height
                growFromBand = true
            } else {
                withAnimation(reduceMotion ? nil : Self.openAnimation) {
                    notch.isOpen = true
                    notch.openHeight = motion.height
                }
            }
        case .close:
            withAnimation(reduceMotion ? nil : Self.closeAnimation) { notch.isOpen = false }
        case .resize:
            withAnimation(reduceMotion ? nil : Self.resizeAnimation) { notch.openHeight = motion.height }
        }
        if step != .none { scheduleSettle(after: step.duration) }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
        let bandInWindow = CGRect(x: notch.bandX, y: 0, width: band.width, height: band.height)
        host.setHoverZone(motion.hoverZone(band: bandInWindow, windowWidth: frame.width))
        if growFromBand {
            panel.contentView?.layoutSubtreeIfNeeded()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.motion.phase == .open, !self.notch.isOpen else { return }
                withAnimation(Self.openAnimation) { self.notch.isOpen = true }
            }
        }
        // The mascot may have moved, appeared (folded) or gone (expanded).
        gaze.refresh()
    }

    /// The folded mascot's centre on screen, and that screen; nil while expanded or not shown.
    private func mascotSpot() -> (center: CGPoint, screen: CGRect)? {
        guard !notch.expanded, panel.isVisible, let geometry = notch.geometry else { return nil }
        let frame = panel.frame
        let center = CGPoint(x: frame.minX + notch.bandX + NotchGeometry.collapsedInset + CGFloat(Mascot.width) / 2, y: frame.midY)
        return (center, geometry.screenFrame)
    }

    /// Once the step's animation is over, the window may shrink to what is drawn.
    private func scheduleSettle(after duration: Double) {
        motionDone?.cancel()
        motionDone = nil
        guard motion.settling else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.motion.settle()
                self?.layout()
            }
        }
        motionDone = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05, execute: work)
    }

    private func endShrink() {
        shrinkDone?.cancel()
        shrinkDone = nil
        shrinkingFrom = nil
    }

    /// Band + the taller column's estimated height (see `PanelLayout`; each scrolls past the cap) + padding.
    private func expandedHeight(band: CGFloat) -> CGFloat {
        band + PanelLayout.expandedHeight(panel: queue.panel(setup: setup.state), todos: queue.todos,
                                          reminders: queue.reminders, online: queue.online) + 16
    }
}

/// Hosting view that reports hover even though the panel is never key, and takes the first click
/// (otherwise the first click on a non-key window only focuses it).
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    /// Where hovering counts, from the window's top-left (`NotchMotion.hoverZone`); nil for the whole view.
    private var zone: CGRect?
    private var inside = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setHoverZone(_ zone: CGRect) {
        if zone != self.zone {
            self.zone = zone
            updateTrackingAreas()
        }
        // A zone that grew or shrank under a still pointer sends no enter or exit.
        guard let window else { return }
        report(zoneRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
    }

    private var zoneRect: CGRect {
        guard let zone else { return bounds }
        return isFlipped ? zone : CGRect(x: zone.minX, y: bounds.height - zone.maxY, width: zone.width, height: zone.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: zoneRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        report(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        report(false)
    }

    private func report(_ now: Bool) {
        guard now != inside else { return }
        inside = now
        onHover?(now)
    }
}
