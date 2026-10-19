import AppKit
import PerchAppCore
import PerchCore
import SwiftUI

/// The event banner on the right wing: the project in the state's colour, then one line. A line wider than
/// `Banner.maxContentWidth` waits `Banner.scrollDelay`, scrolls once to its end and stays there (never loops);
/// with Reduce Motion it is cut with an ellipsis instead.
struct BannerView: View {
    var banner: Banner
    /// How long before a too-long line scrolls: longer while the Done run is still pulling it open (#64).
    var delay = Banner.scrollDelay
    @State private var scrolled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size: CGFloat = 12

    var body: some View {
        let width = Self.contentWidth(banner)
        let overflow = CGFloat(Banner.overflow(contentWidth: width))
        let visible = min(width, CGFloat(Banner.maxContentWidth))
        Group {
            if reduceMotion || overflow == 0 {
                label.lineLimit(1).truncationMode(.tail).frame(width: visible, alignment: .leading)
            } else {
                label.fixedSize()
                    .offset(x: scrolled ? -overflow : 0)
                    .frame(width: visible, alignment: .leading)
                    .clipped()
                    .mask(LinearGradient(stops: [
                        .init(color: .black.opacity(scrolled ? 0 : 1), location: 0),
                        .init(color: .black, location: 0.06),
                        .init(color: .black, location: 0.94),
                        .init(color: .black.opacity(scrolled ? 1 : 0), location: 1),
                    ], startPoint: .leading, endPoint: .trailing))
                    .task {
                        // Not an animation delay: started while the banner fades in, that one lands at its end at once.
                        try? await Task.sleep(for: .seconds(delay))
                        withAnimation(.linear(duration: Double(overflow) / Banner.scrollSpeed)) { scrolled = true }
                    }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var label: some View {
        (Text(banner.title).foregroundColor(SessionStatus.color(banner.status)).fontWeight(.semibold)
            + Text("  " + banner.text).foregroundColor(.white.opacity(0.85)))
            .font(.system(size: Self.size))
    }

    /// The title and text laid out on one line, as `label` draws them.
    static func contentWidth(_ banner: Banner) -> Double {
        let text = NSMutableAttributedString(string: banner.title, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold)])
        text.append(NSAttributedString(string: "  " + banner.text, attributes: [.font: NSFont.systemFont(ofSize: size)]))
        return Double(text.size().width.rounded(.up)) + 1
    }
}
