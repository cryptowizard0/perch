import AppKit

// Perch.app — the notch UI. A client of perchd like the CLI: it never touches the database.
// Runs as an accessory app (no Dock icon, no menu bar of its own); LSUIElement in the bundle says the same.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
