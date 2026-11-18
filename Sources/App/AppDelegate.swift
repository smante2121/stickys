import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces: LSUIElement in Info.plist already hides the Dock icon.
        NSApp.setActivationPolicy(.accessory)

        // Agent apps never show their menu bar, but the (hidden) main menu still
        // powers keyboard shortcuts like ⌘C, ⌘B, ⌘T and ⌘F.
        NSApp.mainMenu = MainMenu.build()

        setUpStatusItem()
        NoteManager.shared.restoreNotes()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoteManager.shared.saveEverything()
    }

    /// Launching Stickys again (Spotlight, Finder) while it's running brings the notes forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NoteManager.shared.showAllNotes()
        return false
    }

    // MARK: - Menu bar icon

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Stickys")
        image?.isTemplate = true
        item.button?.image = image

        let menu = NSMenu()
        menu.addItem(withTitle: "New Note", action: #selector(newNote(_:)), keyEquivalent: "n").target = self
        menu.addItem(withTitle: "Show All Notes", action: #selector(showAllNotes(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Stickys", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }

    // MARK: - Actions (also reachable from the hidden main menu via the responder chain)

    @objc func newNote(_ sender: Any?) {
        NoteManager.shared.createNote()
    }

    @objc func showAllNotes(_ sender: Any?) {
        NoteManager.shared.showAllNotes()
    }
}
