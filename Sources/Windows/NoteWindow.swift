import AppKit

/// A note's window: a normal resizable window with the title bar made invisible,
/// so it keeps native edge-resizing, rounded corners and shadow.
final class NoteWindow: NSWindow {
    static let minimumSize = CGSize(width: 160, height: 90)

    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        isRestorable = false          // Stickys restores notes itself
        tabbingMode = .disallowed
        minSize = Self.minimumSize

        // Visible on every desktop/Space and alongside full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
