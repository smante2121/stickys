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

        // Like part of the desktop: shown in the same place on every desktop (Space),
        // and left where it is by Mission Control / Show Desktop.
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        level = Self.desktopLevel

        setFrame(frame, display: false)
    }

    /// Just above the desktop icons and below every app window, so notes sit behind
    /// everything and can't jump in front when you switch desktops.
    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
