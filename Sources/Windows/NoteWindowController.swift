import AppKit
import SwiftUI

/// Controls one note: keeps its window, view and saved `Note` in sync.
final class NoteWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private(set) var note: Note
    weak var manager: NoteManager?
    private let noteView: NoteContentView

    private var textView: NoteTextView { noteView.textView }

    /// A snapshot of the note's current text, for saving.
    var currentText: NSAttributedString {
        NSAttributedString(attributedString: textView.textStorage ?? NSTextStorage())
    }

    init(note: Note, text: NSAttributedString) {
        self.note = note
        let window = NoteWindow(frame: note.frame)
        noteView = NoteContentView(frame: CGRect(origin: .zero, size: note.frame.size))
        super.init(window: window)

        window.contentView = noteView
        window.delegate = self
        textView.delegate = self
        textView.textStorage?.setAttributedString(text)

        noteView.header.onDoubleClick = { [weak self] in self?.setCollapsed(!(self?.note.isCollapsed ?? false)) }
        noteView.header.closeDot.onPress = { [weak self] in self?.requestDelete() }
        noteView.header.styleButton.target = self
        noteView.header.listButton.target = self
        noteView.header.listButton.action = #selector(toggleBulletList(_:))
        noteView.header.styleButton.action = #selector(showStyleEditor(_:))
        noteView.header.menuProvider = { [weak self] in self?.makeNoteMenu() }

        applyStyle(previous: nil)
        applyFloatsOnTop()
        if note.isCollapsed {
            window.minSize = CGSize(width: NoteWindow.minimumSize.width, height: NoteContentView.headerHeight)
            window.styleMask.remove(.resizable)
            noteView.setCollapsed(true, title: collapsedTitle)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Bring this note forward and put the cursor in it.
    func focus() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        if !note.isCollapsed {
            window?.makeFirstResponder(textView)
        }
    }

    // MARK: - Style

    func setStyle(_ style: NoteStyle) {
        guard style != note.style else { return }
        let previous = note.style
        note.style = style
        applyStyle(previous: previous)
        manager?.contentDidChange(self)   // text colours may have changed too
    }

    private var stylePopover: NSPopover?

    @objc func showStyleEditor(_ sender: Any?) {
        guard let window else { return }
        if let stylePopover, stylePopover.isShown {
            stylePopover.performClose(nil)
            return
        }

        let model = StyleEditorModel(style: note.style)
        model.onChange = { [weak self] style in self?.setStyle(style) }

        // Highlighted text? Then the Text tab's font controls change only that text.
        let highlighted = textView.selectedRange()
        if highlighted.length > 0 {
            model.selection = highlighted
            model.selectionFont = textView.fontChoice(at: highlighted.location)
        }
        model.onSelectionFontChange = { [weak self] old, new, range in
            self?.textView.applyFont(from: old, to: new, in: range)
        }
        model.onUseAsDefault = { [weak self] in
            guard let self else { return }
            self.manager?.setDefaultStyle(self.note.style)
        }

        let host = NSHostingController(rootView: StyleEditorView(model: model))
        host.sizingOptions = .preferredContentSize
        let popover = NSPopover()
        popover.contentViewController = host
        // Stays open while using the Colors panel; closes on clicks in the note.
        popover.behavior = .semitransient
        popover.delegate = self

        // Register the panel first so the note is raised *before* the panel appears.
        stylePopover = popover
        applyLevel()

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Take the cursor out of the text so the Colors panel can't recolour text by accident.
        window.makeFirstResponder(nil)
        let anchor = noteView.header.styleButton
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        keepStylePanelAboveNote()
        closeStylePanelOnDesktopSwitch()
    }

    /// The style panel is its own small window. Keep it one layer above the note, so the
    /// note can never cover it — even if the note's layer changes while the panel is open
    /// (e.g. macOS finishes activating Stickys a moment later and raises the note).
    /// Only adjusts the layer, and only while the panel is fully open — never brings a
    /// closing panel back on screen (that left a frozen copy behind).
    private func keepStylePanelAboveNote() {
        guard let window, let popover = stylePopover, popover.isShown,
              let panelWindow = popover.contentViewController?.view.window, panelWindow.isVisible else { return }
        let level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        if panelWindow.level != level { panelWindow.level = level }
    }

    private var spaceChangeObserver: (any NSObjectProtocol)?

    /// Notes are on every desktop but the panel isn't, so close it when you switch desktops
    /// rather than leave it behind on the old one.
    private func closeStylePanelOnDesktopSwitch() {
        guard spaceChangeObserver == nil else { return }
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stylePopover?.close() }
        }
    }

    private func applyStyle(previous: NoteStyle?) {
        let style = note.style
        let textColor = style.resolvedTextColor

        noteView.applyStyle(style)
        if let previous, previous.font != style.font {
            textView.bulletStyle = style.bullets
            textView.lineSpacing = style.lineSpacing
            textView.applyNoteFont(from: previous.font, to: style.font)
        } else if previous == nil, textView.string.isEmpty {
            textView.typingAttributes[.font] = FontLibrary.font(for: style.font)
        }
        if previous?.bullets != style.bullets || previous?.lineSpacing != style.lineSpacing {
            textView.bulletStyle = style.bullets
            textView.lineSpacing = style.lineSpacing
            textView.applyLayout()
        }
        window?.appearance = NSAppearance(named: style.isDark ? .darkAqua : .aqua)
        window?.invalidateShadow()

        // Automatic text colour: when the background flips between light and dark,
        // recolour text that was using the old automatic colour. Text you coloured
        // yourself is left alone.
        if let previous, previous.textColor == nil, !previous.resolvedTextColor.isClose(to: textColor),
           let storage = textView.textStorage {
            let old = previous.resolvedTextColor
            storage.beginEditing()
            storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                let current = (value as? NSColor).map(RGBAColor.init)
                if current == nil || current!.isClose(to: old) {
                    storage.addAttribute(.foregroundColor, value: textColor.nsColor, range: range)
                }
            }
            storage.endEditing()
        }

        var typing = textView.typingAttributes
        if typing[.font] == nil { typing[.font] = NoteContentView.defaultFont }
        let typingColor = (typing[.foregroundColor] as? NSColor).map(RGBAColor.init)
        if previous == nil || typingColor == nil
            || (previous!.textColor == nil && typingColor!.isClose(to: previous!.resolvedTextColor)) {
            typing[.foregroundColor] = textColor.nsColor
        }
        textView.typingAttributes = typing
        textView.insertionPointColor = textColor.nsColor
    }

    // MARK: - Float on top

    func setFloatsOnTop(_ floats: Bool) {
        note.floatsOnTop = floats
        applyFloatsOnTop()
        manager?.noteDidChange(self)
    }

    private func applyFloatsOnTop() {
        applyLevel()
    }

    /// Set by "Show All Notes": the note stays in front until you switch to another app.
    var isRaised = false { didSet { applyLevel() } }

    /// Where the note sits in the stack of windows:
    /// - Float on Top: above everything.
    /// - While you're using it (typing, style panel open) or after Show All Notes: in front.
    /// - Otherwise: behind all other windows, on the desktop.
    func applyLevel() {
        guard let window else { return }
        let inUse = window.isKeyWindow || stylePopover != nil || isRaised
        let level: NSWindow.Level = note.floatsOnTop ? .floating : (inUse ? .normal : NoteWindow.desktopLevel)
        if window.level != level { window.level = level }
        keepStylePanelAboveNote()
    }

    // MARK: - Collapse

    func setCollapsed(_ collapsed: Bool) {
        guard let window, collapsed != note.isCollapsed else { return }
        var frame = window.frame
        let headerHeight = NoteContentView.headerHeight

        if collapsed {
            note.expandedHeight = frame.height
            frame.origin.y += frame.height - headerHeight
            frame.size.height = headerHeight
            window.makeFirstResponder(nil)
            window.minSize = CGSize(width: NoteWindow.minimumSize.width, height: headerHeight)
            window.styleMask.remove(.resizable)
        } else {
            let height = max(note.expandedHeight ?? NoteManager.defaultSize.height, NoteWindow.minimumSize.height)
            frame.origin.y -= height - frame.height
            frame.size.height = height
            window.styleMask.insert(.resizable)
        }

        note.isCollapsed = collapsed
        noteView.setCollapsed(collapsed, title: collapsedTitle)
        window.setFrame(frame, display: true, animate: true)
        if !collapsed {
            window.minSize = NoteWindow.minimumSize
            window.makeFirstResponder(textView)
        }
        note.frame = window.frame
        manager?.noteDidChange(self)
    }

    /// Like Stickies: a collapsed note shows its first line.
    private var collapsedTitle: String {
        let firstLine = textView.string
            .split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return firstLine.map { $0.trimmingCharacters(in: .whitespaces) } ?? "Empty Note"
    }

    // MARK: - Delete

    func requestDelete() {
        let isEmpty = textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(textView.textStorage?.containsAttachments ?? false)
        if isEmpty {
            manager?.delete(self)
            return
        }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "The note is moved to the Trash, so you can still recover it from there."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            manager?.delete(self)
        }
    }

    // MARK: - Menus

    @objc func toggleBulletList(_ sender: Any?) {
        guard !note.isCollapsed, let window else { return }
        if window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
        textView.toggleBulletList(sender)
    }

    private func makeNoteMenuItems() -> [NSMenuItem] {
        let style = NSMenuItem(title: "Note Style…", action: #selector(showStyleEditor(_:)), keyEquivalent: "")
        style.target = self

        let float = NSMenuItem(title: "Float on Top", action: #selector(toggleFloatOnTop(_:)), keyEquivalent: "")
        float.target = self
        float.state = note.floatsOnTop ? .on : .off

        let collapse = NSMenuItem(title: note.isCollapsed ? "Expand" : "Collapse",
                                  action: #selector(toggleCollapsed(_:)), keyEquivalent: "")
        collapse.target = self

        let delete = NSMenuItem(title: "Delete Note…", action: #selector(deleteNote(_:)), keyEquivalent: "")
        delete.target = self

        return [style, float, collapse, .separator(), delete]
    }

    private func makeNoteMenu() -> NSMenu {
        let menu = NSMenu()
        makeNoteMenuItems().forEach(menu.addItem)
        return menu
    }

    @objc func toggleFloatOnTop(_ sender: Any?) { setFloatsOnTop(!note.floatsOnTop) }
    @objc func toggleCollapsed(_ sender: Any?) { setCollapsed(!note.isCollapsed) }
    @objc func deleteNote(_ sender: Any?) { requestDelete() }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        note.modified = Date()
        manager?.contentDidChange(self)
    }

    /// Adds the note options to the top of the text's right-click menu.
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        let bullets = NSMenuItem(title: "Bulleted List", action: #selector(toggleBulletList(_:)), keyEquivalent: "")
        bullets.target = self
        bullets.state = textView.isInBulletList() ? .on : .off
        let items = [bullets, .separator()] + makeNoteMenuItems()
        for (index, item) in items.enumerated() {
            menu.insertItem(item, at: index)
        }
        menu.insertItem(.separator(), at: items.count)
        return menu
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) { frameChanged() }
    func windowDidResize(_ notification: Notification) { frameChanged() }

    private func frameChanged() {
        guard let window else { return }
        note.frame = window.frame
        manager?.noteDidChange(self)
    }

    /// ⌘W behaves like Stickies: closing a note deletes it (with confirmation).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestDelete()
        return false
    }

    /// Close the style popover when you move on to another app or note
    /// (but not when you click into the popover itself or the Colors panel).
    func windowDidBecomeKey(_ notification: Notification) {
        applyLevel()
    }

    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let popover = self.stylePopover, popover.isShown {
                let key = NSApp.keyWindow
                let popoverWindow = popover.contentViewController?.view.window
                if key === self.window || key === popoverWindow || key is NSColorPanel { return }
                popover.performClose(nil)
            }
            self.applyLevel()   // drop back behind other windows
        }
    }
}

extension NoteWindowController: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) {
        keepStylePanelAboveNote()
    }

    func popoverDidClose(_ notification: Notification) {
        // Make sure the panel's window is really gone, then forget it.
        (notification.object as? NSPopover)?.contentViewController?.view.window?.orderOut(nil)
        stylePopover = nil
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
            self.spaceChangeObserver = nil
        }
        defer { applyLevel() }
        // The Colors panel was being used for the background; close it so it
        // doesn't start colouring text once the cursor is back in the note.
        if NSColorPanel.sharedColorPanelExists, NSColorPanel.shared.isVisible {
            NSColorPanel.shared.orderOut(nil)
        }
        if !note.isCollapsed {
            window?.makeFirstResponder(textView)
        }
    }
}

extension NoteWindowController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleFloatOnTop(_:)):
            item.state = note.floatsOnTop ? .on : .off
        case #selector(toggleCollapsed(_:)):
            item.title = note.isCollapsed ? "Expand" : "Collapse"
        default:
            break
        }
        return true
    }
}
