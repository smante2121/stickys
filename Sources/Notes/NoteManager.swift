import AppKit

/// Owns every open note: creates, restores, deletes and saves them.
final class NoteManager {
    static let shared = NoteManager()

    private let store = NoteStore()
    private var controllers: [NoteWindowController] = []
    private var indexSaveTask: Task<Void, Never>?
    private var contentSaveTasks: [UUID: Task<Void, Never>] = [:]

    static let defaultSize = CGSize(width: 280, height: 260)

    /// Style for new notes ("Use as Default for New Notes"). Kept in UserDefaults.
    private(set) var defaultStyle: NoteStyle = {
        guard let data = UserDefaults.standard.data(forKey: NoteManager.defaultStyleKey),
              let style = try? JSONDecoder().decode(NoteStyle.self, from: data) else { return .default }
        return style
    }()
    private static let defaultStyleKey = "defaultStyle"

    func setDefaultStyle(_ style: NoteStyle) {
        defaultStyle = style
        if let data = try? JSONEncoder().encode(style) {
            UserDefaults.standard.set(data, forKey: Self.defaultStyleKey)
        }
    }

    // MARK: - Lifecycle

    func restoreNotes() {
        let notes = store.loadNotes()
        guard !notes.isEmpty else {
            createNote(text: Self.welcomeText(), focus: false)
            return
        }
        for var note in notes {
            note.frame = Self.ensureOnScreen(note.frame)
            let text = store.loadContent(for: note.id) ?? NSAttributedString()
            open(note, text: text).window?.orderFront(nil)
        }
    }

    @discardableResult
    func createNote(text: NSAttributedString? = nil, focus: Bool = true) -> NoteWindowController {
        let note = Note(frame: nextNoteFrame(), style: defaultStyle)
        let controller = open(note, text: text ?? NSAttributedString())
        store.saveContent(controller.currentText, for: note.id)
        saveIndexNow()
        if focus {
            controller.focus()
        } else {
            controller.window?.orderFront(nil)
        }
        return controller
    }

    /// Brings every note in front of other windows until you switch to another app.
    func showAllNotes() {
        NSApp.activate()
        for controller in controllers {
            controller.isRaised = true
            controller.window?.orderFrontRegardless()
        }
        controllers.last?.window?.makeKey()
        observeDeactivation()
    }

    private var deactivationObserver: (any NSObjectProtocol)?

    /// When you click into another app, raised notes go back behind everything.
    private func observeDeactivation() {
        guard deactivationObserver == nil else { return }
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controllers.forEach { $0.isRaised = false }
            }
        }
    }

    func delete(_ controller: NoteWindowController) {
        let id = controller.note.id
        contentSaveTasks.removeValue(forKey: id)?.cancel()
        controllers.removeAll { $0 === controller }
        controller.close()
        store.trashContent(for: id)
        saveIndexNow()
    }

    /// Called on quit: flush anything still waiting to be written.
    func saveEverything() {
        indexSaveTask?.cancel()
        for (id, task) in contentSaveTasks {
            task.cancel()
            if let controller = controllers.first(where: { $0.note.id == id }) {
                store.saveContent(controller.currentText, for: id)
            }
        }
        contentSaveTasks.removeAll()
        saveIndexNow()
    }

    // MARK: - Change notifications from notes (debounced saving)

    func noteDidChange(_ controller: NoteWindowController) {
        indexSaveTask?.cancel()
        indexSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveIndexNow()
        }
    }

    func contentDidChange(_ controller: NoteWindowController) {
        let id = controller.note.id
        contentSaveTasks[id]?.cancel()
        contentSaveTasks[id] = Task { [weak self, weak controller] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, let controller else { return }
            self.contentSaveTasks[id] = nil
            self.store.saveContent(controller.currentText, for: id)
        }
        noteDidChange(controller)
    }

    // MARK: - Private

    @discardableResult
    private func open(_ note: Note, text: NSAttributedString) -> NoteWindowController {
        let controller = NoteWindowController(note: note, text: text)
        controller.manager = self
        controllers.append(controller)
        return controller
    }

    private func saveIndexNow() {
        indexSaveTask?.cancel()
        store.saveNotes(controllers.map(\.note))
    }

    /// New notes cascade from the note you're in, or appear near the centre of the screen.
    private func nextNoteFrame() -> CGRect {
        let size = Self.defaultSize
        if let key = NSApp.keyWindow as? NoteWindow {
            var frame = CGRect(origin: key.frame.origin, size: size)
            frame.origin.x += 28
            frame.origin.y = key.frame.maxY - size.height - 28
            return Self.ensureOnScreen(frame)
        }
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let step = CGFloat(controllers.count % 8) * 28
        return CGRect(
            x: screen.midX - size.width / 2 + step,
            y: screen.midY - size.height / 2 + 120 - step,
            width: size.width,
            height: size.height
        )
    }

    /// If a note's saved position is on a display that's no longer connected,
    /// move it back onto the main screen.
    static func ensureOnScreen(_ frame: CGRect) -> CGRect {
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame.insetBy(dx: 40, dy: 10)) }
        guard !visible, let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return frame }
        var moved = frame
        moved.size.width = min(frame.width, screen.width)
        moved.size.height = min(frame.height, screen.height)
        moved.origin.x = screen.midX - moved.width / 2
        moved.origin.y = screen.midY - moved.height / 2
        return moved
    }

    private static func welcomeText() -> NSAttributedString {
        let color = NoteStyle.default.resolvedTextColor.nsColor
        let text = NSMutableAttributedString(
            string: "Welcome to Stickys\n",
            attributes: [.font: NSFont.systemFont(ofSize: 20, weight: .bold), .foregroundColor: color]
        )
        let body = """

        • Drag the top edge to move a note, any edge to resize.
        • Double-click the top edge to collapse it.
        • Right-click for colors and Float on Top.
        • ⌘T for fonts, ⇧⌘C for colors.
        • New notes from the menu bar icon.
        """
        text.append(NSAttributedString(
            string: body,
            attributes: [.font: NoteContentView.defaultFont, .foregroundColor: color]
        ))
        return text
    }
}
