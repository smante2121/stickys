import AppKit

/// The strip along the top of a note: drag to move, double-click to collapse,
/// three dots (delete, collapse, float on top) that fade in on hover.
final class NoteHeaderView: NSView {
    var onDoubleClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    let closeDot = DotButton(symbol: "xmark", label: "Delete Note")
    let collapseDot = DotButton(symbol: "minus", label: "Collapse")
    let pinDot = DotButton(symbol: "pin.fill", label: "Float on Top")

    private let dots: NSStackView
    private let titleLabel = NSTextField(labelWithString: "")
    private var hoverArea: NSTrackingArea?

    init() {
        dots = NSStackView(views: [closeDot, collapseDot, pinDot])
        super.init(frame: .zero)

        dots.orientation = .horizontal
        dots.spacing = 7
        dots.alphaValue = 0

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isHidden = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for view in [dots, titleLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            dots.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dots.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: dots.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func applyStyle(_ style: NoteStyle) {
        let dark = style.isDark
        let dotColor = dark ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.14)
        let glyphColor = dark ? NSColor.white.withAlphaComponent(0.8) : NSColor.black.withAlphaComponent(0.6)
        for dot in [closeDot, collapseDot, pinDot] {
            dot.dotColor = dotColor
            dot.glyphColor = glyphColor
        }
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
            dots.animator().alphaValue = visible ? 1 : 0
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

    // Show the symbols inside the dots while hovering the header (like traffic lights).
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

    override func mouseEntered(with event: NSEvent) { setGlyphsVisible(true) }
    override func mouseExited(with event: NSEvent) { setGlyphsVisible(false) }

    private func setGlyphsVisible(_ visible: Bool) {
        for dot in [closeDot, collapseDot, pinDot] { dot.showsGlyph = visible }
    }
}

/// A small round button drawn as a dot, showing its symbol on hover.
final class DotButton: NSView {
    static let diameter: CGFloat = 12

    var onPress: (() -> Void)?
    var dotColor = NSColor.black.withAlphaComponent(0.14) { didSet { needsDisplay = true } }
    var glyphColor = NSColor.black.withAlphaComponent(0.6) { didSet { needsDisplay = true } }
    var showsGlyph = false { didSet { needsDisplay = true } }
    /// For toggles (Float on Top): an "on" dot is darker and always shows its symbol.
    var isOn = false { didSet { needsDisplay = true } }

    private let symbol: String

    init(symbol: String, label: String) {
        self.symbol = symbol
        super.init(frame: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        toolTip = label
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.diameter, height: Self.diameter) }

    override func draw(_ dirtyRect: NSRect) {
        let fill = isOn ? dotColor.withAlphaComponent(min(dotColor.alphaComponent * 2.4, 1)) : dotColor
        fill.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()

        guard showsGlyph || isOn else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 7, weight: .black)
            .applying(.init(paletteColors: [glyphColor]))
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let size = image.size
        image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                              width: size.width, height: size.height))
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
