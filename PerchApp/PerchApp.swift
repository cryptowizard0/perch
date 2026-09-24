import AppKit
import SwiftUI
import PerchCore

// The notch app. Milestone 2 replaces this placeholder with the notch panel
// (NSPanel positioned over the notch; collapsed / expanded states — see docs/PRD.md → 刘海 UI).
// Until then a menu bar item proves the app target builds and links PerchCore.

@main
struct PerchApp: App {
    var body: some Scene {
        MenuBarExtra("Perch", systemImage: "bird") {
            Text("Perch \(PerchVersion.string) — notch UI arrives in milestone 2")
            Divider()
            Button("Quit Perch") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
