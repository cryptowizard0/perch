import PerchAppCore
import SwiftUI

struct NotchView: View {
    @ObservedObject var notch: NotchModel

    var body: some View {
        NotchShape(hasNotch: notch.geometry?.hasNotch ?? true, expanded: notch.expanded)
            .fill(Color.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
