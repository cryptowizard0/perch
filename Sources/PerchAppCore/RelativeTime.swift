import Foundation

/// Compact times for the notch: "now", "4m", "2h", "3d".
public enum RelativeTime {
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 {
            let m = (s % 3600) / 60
            return m == 0 || s >= 10 * 3600 ? "\(s / 3600)h" : "\(s / 3600)h\(m)m"
        }
        return "\(s / 86_400)d"
    }
}
