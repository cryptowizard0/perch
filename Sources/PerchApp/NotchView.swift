import PerchAppCore
import PerchCore
import SwiftUI

/// Right-click menu on the notch.
struct NotchMenu {
    var quickEntryShortcut: String
    var quickEntry: () -> Void
    var quit: () -> Void
}

struct NotchView: View {
    @ObservedObject var notch: NotchModel
    @ObservedObject var queue: QueueModel
    var menu: NotchMenu

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(hasNotch: notch.geometry?.hasNotch ?? true, expanded: notch.expanded)
                .fill(Color.black)
            VStack(spacing: 0) {
                CollapsedBar(queue: queue, notchWidth: notch.geometry?.notch?.width ?? 0)
                    .frame(height: notch.geometry?.bandHeight ?? NotchGeometry.capsuleHeight)
                if notch.expanded {
                    ExpandedList(queue: queue)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contextMenu {
            Button("New Task…  \(menu.quickEntryShortcut)", action: menu.quickEntry)
            Divider()
            Button("Quit Perch", action: menu.quit)
        }
    }
}

/// The band beside the notch: dot (+ Live Activity) on the left, the count on the right.
struct CollapsedBar: View {
    @ObservedObject var queue: QueueModel
    var notchWidth: CGFloat

    var body: some View {
        let summary = queue.summary
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                SignalDot(signal: summary.signal, online: queue.online, pulse: queue.pulse)
                if let text = queue.liveActivity?.text(now: queue.now) {
                    Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1).fixedSize()
                }
            }
            .padding(.leading, 14)
            Spacer(minLength: notchWidth)
            Group {
                if !queue.online {
                    Image(systemName: "bolt.horizontal.circle").help(queue.offlineReason ?? "perchd is not running")
                } else if summary.count > 0 {
                    Text("\(summary.count)").monospacedDigit()
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.trailing, 14)
        }
    }
}

struct SignalDot: View {
    var signal: Signal
    var online: Bool
    var pulse: Int
    @State private var ring = false

    var body: some View {
        Circle()
            .fill(online ? signal.color : Color.gray.opacity(0.5))
            .frame(width: 8, height: 8)
            .overlay(
                Circle().stroke(signal.color, lineWidth: 2)
                    .scaleEffect(ring ? 3 : 1)
                    .opacity(ring ? 0 : 0.9)
                    .animation(ring ? .easeOut(duration: 0.9).repeatCount(2, autoreverses: false) : nil, value: ring)
            )
            .onChange(of: pulse) {
                ring = false
                DispatchQueue.main.async { ring = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { ring = false }
            }
    }
}

extension Signal {
    var color: Color {
        switch self {
        case .idle: return Color(white: 0.55)
        case .todo: return Color(red: 0.25, green: 0.55, blue: 1)
        case .waiting: return Color(red: 1, green: 0.58, blue: 0.1)
        case .overdue: return Color(red: 1, green: 0.27, blue: 0.23)
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
