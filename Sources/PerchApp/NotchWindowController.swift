import AppKit
import Combine
import PerchAppCore
import SwiftUI

/// UI state of the notch that is not queue data: which screen, collapsed or expanded.
@MainActor
final class NotchModel: ObservableObject {
    @Published var geometry: NotchGeometry?
    @Published var expanded = false
}

/// Owns the panel: keeps it on the right screen and sized for the current state.
@MainActor
final class NotchWindowController {
    let panel = NotchPanel()
    let notch: NotchModel
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []

    static let collapsedWing: CGFloat = 40
    static let expandedSize = CGSize(width: 440, height: 320)

    init(notch: NotchModel) {
        self.notch = notch
        let host = NSHostingView(rootView: NotchView(notch: notch))
        host.sizingOptions = []
        panel.contentView = host
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        })
        notch.$expanded.removeDuplicates().dropFirst().sink { [weak self] _ in
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
        let frame = notch.expanded
            ? geometry.expandedFrame(size: Self.expandedSize)
            : geometry.collapsedFrame(leftWing: Self.collapsedWing, rightWing: Self.collapsedWing)
        panel.setFrame(frame, display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}
