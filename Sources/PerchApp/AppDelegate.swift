import AppKit
import PerchCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Perch \(PerchVersion.string) started")
    }
}
