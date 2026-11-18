import AppKit

/// The inside of a note: background, header strip, and the rich-text editor.
final class NoteContentView: NSView {
    static let headerHeight: CGFloat = 28
    static let cornerRadius: CGFloat = 14
    static let defaultFont = NSFont.systemFont(ofSize: 15)

    let header = NoteHeaderView()
    let scrollView: NSScrollView
    let textView: NSTextView
    private let backgroundView = NSView()
    private var hoverArea: NSTrackingArea?

    override init(frame: NSRect) {
        scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as! NSTextView
        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        backgroundView.wantsLayer = true

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
        textView.textContainerInset = NSSize(width: 12, height: 2)
        textView.font = Self.defaultFont
    }

    func applyStyle(_ style: NoteStyle) {
        backgroundView.layer?.backgroundColor = style.background.nsColor.cgColor
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
