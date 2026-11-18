import AppKit

/// The strip along the top of a note: drag to move, double-click to collapse.
/// On hover it shows a close dot (left) and a style button (right).
final class NoteHeaderView: NSView {
    var onDoubleClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    let closeDot = CloseDot()
    let listButton: NSButton
    let styleButton: NSButton

    private let titleLabel = NSTextField(labelWithString: "")
    private var hoverArea: NSTrackingArea?

    init() {
        listButton = Self.makeButton(symbol: "list.bullet", label: "Bulleted List (⇧⌘7)")
        styleButton = Self.makeButton(symbol: "paintpalette", label: "Note Style")
        super.init(frame: .zero)

        closeDot.alphaValue = 0

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isHidden = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for view in [closeDot, listButton, styleButton, titleLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            closeDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            closeDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeDot.widthAnchor.constraint(equalToConstant: CloseDot.diameter),
            closeDot.heightAnchor.constraint(equalToConstant: CloseDot.diameter),

            styleButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            styleButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            listButton.trailingAnchor.constraint(equalTo: styleButton.leadingAnchor, constant: -6),
            listButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: closeDot.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: listButton.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func makeButton(symbol: String, label: String) -> NSButton {
        let button = FirstMouseButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!,
            target: nil,
            action: nil
        )
        button.isBordered = false
        button.refusesFirstResponder = true
        button.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        button.toolTip = label
        button.alphaValue = 0
        return button
    }

    func applyStyle(_ style: NoteStyle) {
        let dark = style.isDark
        closeDot.dotColor = dark ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.14)
        closeDot.glyphColor = dark ? NSColor.white.withAlphaComponent(0.85) : NSColor.black.withAlphaComponent(0.6)
        let tint = dark ? NSColor.white.withAlphaComponent(0.7) : NSColor.black.withAlphaComponent(0.5)
        listButton.contentTintColor = tint
        styleButton.contentTintColor = tint
        titleLabel.textColor = style.resolvedTextColor.nsColor.withAlphaComponent(0.75)
    }

    /// nil hides the title (expanded note); a string shows it (collapsed note).
    func setTitle(_ title: String?) {
        titleLabel.stringValue = title ?? ""
        titleLabel.isHidden = title == nil
    }

    func setControlsVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            closeDot.animator().alphaValue = visible ? 1 : 0
            listButton.animator().alphaValue = visible ? 1 : 0
            styleButton.animator().alphaValue = visible ? 1 : 0
        }
    }

    // MARK: - Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            window?.performDrag(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    // Show the × inside the close dot while hovering the header (like traffic lights).
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { closeDot.showsGlyph = true }
    override func mouseExited(with event: NSEvent) { closeDot.showsGlyph = false }
}

/// Clicks work on the first click, even when the note isn't the active window.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The round close button. The × is drawn as two strokes so it sits exactly centred.
final class CloseDot: NSView {
    static let diameter: CGFloat = 12

    var onPress: (() -> Void)?
    var dotColor = NSColor.black.withAlphaComponent(0.14) { didSet { needsDisplay = true } }
    var glyphColor = NSColor.black.withAlphaComponent(0.6) { didSet { needsDisplay = true } }
    var showsGlyph = false { didSet { needsDisplay = true } }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        toolTip = "Delete Note"
        setAccessibilityRole(.button)
        setAccessibilityLabel("Delete Note")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        dotColor.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()

        guard showsGlyph else { return }
        let arm: CGFloat = 2.5   // half the length of each stroke
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: bounds.midX - arm, y: bounds.midY - arm))
        cross.line(to: NSPoint(x: bounds.midX + arm, y: bounds.midY + arm))
        cross.move(to: NSPoint(x: bounds.midX - arm, y: bounds.midY + arm))
        cross.line(to: NSPoint(x: bounds.midX + arm, y: bounds.midY - arm))
        cross.lineWidth = 1.4
        cross.lineCapStyle = .round
        glyphColor.setStroke()
        cross.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Swallow the press so it doesn't start a window drag; act on release inside.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onPress?()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
