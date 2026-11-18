import AppKit

/// The inside of a note: background, header strip, and the rich-text editor.
final class NoteContentView: NSView {
    static let headerHeight: CGFloat = 28
    /// Space between the header strip and the top of the first line of text.
    static let textTopPadding: CGFloat = 2
    static let cornerRadius: CGFloat = 14
    static let defaultFont = NSFont.systemFont(ofSize: 15)

    let header = NoteHeaderView()
    let scrollView: NSScrollView
    let textView: NoteTextView
    private let backgroundView = NoteBackgroundView()
    private var hoverArea: NSTrackingArea?

    override init(frame: NSRect) {
        scrollView = NSScrollView()
        textView = NoteTextView(frame: .zero)
        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        for view in [backgroundView, scrollView, header] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),

            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        configureTextView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configureTextView() {
        // Standard "text view inside a scroll view" setup: grows vertically, wraps to width.
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView

        // The window's (invisible) title bar is 32 pt tall. By default the scroll view
        // pads its top to clear it, adding hidden space above the text — turn that off.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsImageEditing = true
        textView.allowsUndo = true
        textView.usesFontPanel = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.allowsDocumentBackgroundColorChange = false
        textView.textContainerInset = NSSize(width: 12, height: Self.textTopPadding)
        textView.font = Self.defaultFont
    }

    func applyStyle(_ style: NoteStyle) {
        backgroundView.apply(style)
        header.applyStyle(style)
    }

    func setCollapsed(_ collapsed: Bool, title: String) {
        scrollView.isHidden = collapsed
        header.setTitle(collapsed ? title : nil)
    }

    // MARK: - Hover: show the header controls only while the mouse is over the note

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

    override func mouseEntered(with event: NSEvent) { header.setControlsVisible(true) }
    override func mouseExited(with event: NSEvent) { header.setControlsVisible(false) }
}

/// The note's background: a solid colour (with adjustable opacity), or colourless glass.
///
/// Glass is a live blur of whatever is behind the note, plus a frost layer (intensity),
/// a soft top sheen and a bright rim. It uses NSVisualEffectView pinned to its *active*
/// look — Apple's NSGlassEffectView dims whenever its window isn't focused and offers no
/// way to turn that off, so it can't stay consistent on a desktop note.
final class NoteBackgroundView: NSView {
    private let solid = NSView()
    private let blur = NSVisualEffectView()
    private let frost = NSView()
    private let sheen = GradientView()
    private let rim = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        solid.wantsLayer = true
        frost.wantsLayer = true

        blur.blendingMode = .behindWindow
        blur.state = .active          // never switch to the dimmed "inactive" look

        rim.wantsLayer = true
        rim.layer?.cornerRadius = NoteContentView.cornerRadius
        rim.layer?.cornerCurve = .continuous
        rim.layer?.borderWidth = 1

        for view in [blur, frost, sheen, rim, solid] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ style: NoteStyle) {
        let isGlass = style.kind == .glass
        solid.isHidden = isGlass
        for view in [blur, frost, sheen, rim] { view.isHidden = !isGlass }

        switch style.kind {
        case .solid:
            let opacity = min(max(style.opacity, NoteStyle.opacityRange.lowerBound), 1)
            solid.layer?.backgroundColor = style.background.withAlpha(opacity).nsColor.cgColor

        case .glass:
            let intensity = min(max(style.glassIntensity, 0), 1)
            let dark = style.glassTone == .dark
            blur.material = dark ? .hudWindow : .popover
            // Fading the blur in/out is what makes the intensity slider continuous:
            // low = mostly clear, high = fully blurred and frosted.
            blur.alphaValue = 0.3 + 0.7 * intensity
            let frostColor: NSColor = dark ? .black : .white
            frost.layer?.backgroundColor = frostColor.withAlphaComponent((dark ? 0.4 : 0.45) * intensity).cgColor
            sheen.colors = [NSColor.white.withAlphaComponent(dark ? 0.10 : 0.22), NSColor.white.withAlphaComponent(0)]
            rim.layer?.borderColor = NSColor.white.withAlphaComponent(dark ? 0.18 : 0.55).cgColor
        }
    }
}

/// A vertical gradient, top to bottom (used for the glass sheen).
final class GradientView: NSView {
    var colors: [NSColor] = [] { didSet { updateGradient() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func makeBackingLayer() -> CALayer { CAGradientLayer() }

    private func updateGradient() {
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = colors.map(\.cgColor)
        // Layer coordinates: y = 1 is the top of a non-flipped view.
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0.45)
    }
}
