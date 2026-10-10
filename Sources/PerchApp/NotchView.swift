import PerchAppCore
import PerchCore
import SwiftUI

/// Right-click menu on the notch (a row has its own).
struct NotchMenu {
    var quit: () -> Void
}

struct NotchView: View {
    @ObservedObject var notch: NotchModel
    @ObservedObject var queue: QueueModel
    @ObservedObject var setup: SetupModel
    var menu: NotchMenu

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(hasNotch: notch.geometry?.hasNotch ?? true, expanded: notch.expanded)
                .fill(Color.black)
            VStack(spacing: 0) {
                CollapsedBar(queue: queue, notchWidth: notch.geometry?.notch?.width ?? 0)
                    .frame(height: notch.geometry?.bandHeight ?? NotchGeometry.capsuleHeight)
                if notch.expanded {
                    ExpandedPanel(queue: queue, setup: setup)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contextMenu {
            // Only an app that maintains the install (in an Applications folder, no PERCH_HOME) edits agent configs.
            if !setup.state.menu.isEmpty {
                Menu("Agents") {
                    ForEach(setup.state.menu, id: \.agent) { toggle in
                        Toggle(toggle.title, isOn: Binding(
                            get: { toggle.on },
                            set: { $0 ? setup.connect(toggle.agent) : setup.disconnect(toggle.agent) }
                        ))
                        .disabled(!toggle.available)
                    }
                }
                Divider()
            }
            Button("Quit Perch", action: menu.quit)
        }
    }
}

/// The band beside the notch, all on the left wing: the mascot (acting out the most urgent session's state) and
/// right next to it the number of running sessions (hidden at 0), or the offline icon.
struct CollapsedBar: View {
    @ObservedObject var queue: QueueModel
    var notchWidth: CGFloat

    var body: some View {
        let panel = queue.panel
        HStack(spacing: 0) {
            HStack(spacing: NotchGeometry.collapsedGap) {
                MascotView(signal: panel.signal, online: queue.online, pulse: queue.pulse, pulseStatus: queue.pulseStatus)
                Group {
                    if !queue.online {
                        Image(systemName: "bolt.horizontal.circle").help(queue.offlineReason ?? "perchd is not running")
                    } else if panel.runningCount > 0 {
                        Text("\(panel.runningCount)").monospacedDigit().help("\(panel.runningCount) running")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.leading, NotchGeometry.collapsedInset)
            Spacer(minLength: notchWidth)
        }
    }
}

/// A session state's colour; Running breathes.
struct StatusDot: View {
    var status: SessionStatus?
    var size: CGFloat = 7
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(SessionStatus.color(status))
            .frame(width: size, height: size)
            .opacity(status == .running ? (breathing ? 0.35 : 1) : 1)
            .animation(status == .running ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true) : .default, value: breathing)
            .onAppear { breathing = status == .running }
            .onChange(of: status) { breathing = status == .running }
    }
}

extension SessionStatus {
    /// Needs you orange, Failed red, Running green, Done blue, Idle grey; no sessions a darker grey.
    static func color(_ status: SessionStatus?) -> Color {
        switch status {
        case .waiting: return Color(red: 1, green: 0.58, blue: 0.1)
        case .failed: return Color(red: 1, green: 0.27, blue: 0.23)
        case .running: return Color(red: 0.2, green: 0.82, blue: 0.4)
        case .done: return Color(red: 0.25, green: 0.55, blue: 1)
        case .idle: return Color(white: 0.55)
        case nil: return Color(white: 0.35)
        }
    }
}

/// Flush with the top edge and rounded below when it hangs from the notch; a capsule otherwise.
struct NotchShape: Shape {
    var hasNotch: Bool
    var expanded: Bool

    func path(in rect: CGRect) -> Path {
        if !hasNotch && !expanded { return Capsule().path(in: rect) }
        let radius: CGFloat = expanded ? 18 : 10
        if !hasNotch { return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect) }
        return UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
            .path(in: rect)
    }
}
