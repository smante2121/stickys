import AppKit

/// Controls one note: keeps its window, view and saved `Note` in sync.
final class NoteWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private(set) var note: Note
    weak var manager: NoteManager?
    private let noteView: NoteContentView

    private var textView: NSTextView { noteView.textView }

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
        noteView.header.collapseDot.onPress = { [weak self] in self?.setCollapsed(!(self?.note.isCollapsed ?? false)) }
        noteView.header.pinDot.onPress = { [weak self] in self?.setFloatsOnTop(!(self?.note.floatsOnTop ?? false)) }
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

    func setBackground(_ color: RGBAColor) {
        let previous = note.style
        note.style.background = color
        applyStyle(previous: previous)
        manager?.contentDidChange(self)   // text colours may have changed too
    }

    private func applyStyle(previous: NoteStyle?) {
        let style = note.style
        let textColor = style.resolvedTextColor

        noteView.applyStyle(style)
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
        if typingColor == nil || previous.map({ typingColor!.isClose(to: $0.resolvedTextColor) }) == true {
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
        window?.level = note.floatsOnTop ? .floating : .normal
        noteView.header.pinDot.isOn = note.floatsOnTop
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

    private func makeNoteMenuItems() -> [NSMenuItem] {
        let colorMenu = NSMenu()
        for swatch in NotePalette.allCases {
            let item = NSMenuItem(title: swatch.name, action: #selector(chooseColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = swatch.rawValue
            item.image = Self.swatchImage(swatch.color)
            item.state = note.style.background.isClose(to: swatch.color) ? .on : .off
            colorMenu.addItem(item)
        }
        let color = NSMenuItem(title: "Note Color", action: nil, keyEquivalent: "")
        color.submenu = colorMenu

        let float = NSMenuItem(title: "Float on Top", action: #selector(toggleFloatOnTop(_:)), keyEquivalent: "")
        float.target = self
        float.state = note.floatsOnTop ? .on : .off

        let collapse = NSMenuItem(title: note.isCollapsed ? "Expand" : "Collapse",
                                  action: #selector(toggleCollapsed(_:)), keyEquivalent: "")
        collapse.target = self

        let delete = NSMenuItem(title: "Delete Note…", action: #selector(deleteNote(_:)), keyEquivalent: "")
        delete.target = self

        return [color, float, collapse, .separator(), delete]
    }

    private func makeNoteMenu() -> NSMenu {
        let menu = NSMenu()
        makeNoteMenuItems().forEach(menu.addItem)
        return menu
    }

    private static func swatchImage(_ color: RGBAColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            color.nsColor.setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }

    @objc func chooseColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let swatch = NotePalette(rawValue: raw) else { return }
        setBackground(swatch.color)
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
        let items = makeNoteMenuItems()
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
