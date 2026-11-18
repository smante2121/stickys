import AppKit

// Plain AppKit entry point (no SwiftUI App lifecycle) so we fully control
// windows, menus and the "no Dock icon" behaviour.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
