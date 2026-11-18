import AppKit

/// The app's main menu. Stickys is an agent app, so this menu is never displayed —
/// it exists so standard keyboard shortcuts keep working inside notes.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        main.addItem(submenu("Stickys", [
            item("About Stickys", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Quit Stickys", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        main.addItem(submenu("File", [
            item("New Note", #selector(AppDelegate.newNote(_:)), "n"),
            item("Close Note", #selector(NSWindow.performClose(_:)), "w"),
        ]))

        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]),
            item("Delete", #selector(NSText.delete(_:))),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            submenu("Find", [
                findItem("Find…", .showFindPanel, "f"),
                findItem("Find Next", .next, "g"),
                findItem("Find Previous", .previous, "g", [.command, .shift]),
                findItem("Use Selection for Find", .setFindString, "e"),
            ]),
        ]))

        let fonts = NSFontManager.shared
        main.addItem(submenu("Format", [
            item("Show Fonts", #selector(NSFontManager.orderFrontFontPanel(_:)), "t", target: fonts),
            item("Bold", #selector(NSFontManager.addFontTrait(_:)), "b", target: fonts,
                 tag: Int(NSFontTraitMask.boldFontMask.rawValue)),
            item("Italic", #selector(NSFontManager.addFontTrait(_:)), "i", target: fonts,
                 tag: Int(NSFontTraitMask.italicFontMask.rawValue)),
            item("Underline", #selector(NSText.underline(_:)), "u"),
            .separator(),
            item("Bigger", #selector(NSFontManager.modifyFont(_:)), "+", target: fonts,
                 tag: Int(NSFontAction.sizeUpFontAction.rawValue)),
            item("Smaller", #selector(NSFontManager.modifyFont(_:)), "-", target: fonts,
                 tag: Int(NSFontAction.sizeDownFontAction.rawValue)),
            .separator(),
            item("Show Colors", #selector(NSApplication.orderFrontColorPanel(_:)), "c", [.command, .shift]),
            .separator(),
            item("Copy Style", #selector(NSTextView.copyFont(_:)), "c", [.command, .option]),
            item("Paste Style", #selector(NSTextView.pasteFont(_:)), "v", [.command, .option]),
            .separator(),
            item("Bulleted List", #selector(NoteTextView.toggleBulletList(_:)), "7", [.command, .shift]),
            .separator(),
            item("Align Left", #selector(NSText.alignLeft(_:)), "{"),
            item("Center", #selector(NSText.alignCenter(_:)), "|"),
            item("Align Right", #selector(NSText.alignRight(_:)), "}"),
        ]))

        main.addItem(submenu("Note", [
            item("Float on Top", #selector(NoteWindowController.toggleFloatOnTop(_:)), "f", [.command, .option]),
            item("Collapse", #selector(NoteWindowController.toggleCollapsed(_:)), "m"),
        ]))

        return main
    }

    // MARK: - Helpers

    private static func item(
        _ title: String,
        _ action: Selector?,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil,
        tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        item.tag = tag
        return item
    }

    private static func findItem(
        _ title: String,
        _ action: NSFindPanelAction,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        item(title, #selector(NSTextView.performFindPanelAction(_:)), key, modifiers, tag: Int(action.rawValue))
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = menu
        return parent
    }
}
