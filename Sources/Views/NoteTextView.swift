import AppKit
import CoreText

/// The note's text editor: a standard rich-text NSTextView plus bulleted lists.
///
/// A bullet item is a paragraph that starts with a bullet character and a tab
/// (e.g. "•\t"), with a hanging indent so wrapped lines align with the text.
/// Lists therefore save to RTFD and open correctly in TextEdit too.
final class NoteTextView: NSTextView {
    /// Shape, size, indent and spacing for this note's bullets.
    var bulletStyle = BulletStyle()
    /// Line height multiple for every paragraph (1 = normal).
    var lineSpacing: Double = 1

    private var markerString: String { "\(bulletStyle.shape.marker)\t" }
    private static let markerLength = 2   // bullet + tab, in UTF-16 units

    // MARK: - Toggle (⇧⌘7, header button, right-click menu)

    @objc func toggleBulletList(_ sender: Any?) {
        guard isEditable, let storage = textStorage else { return }
        let text = storage.string as NSString
        let selection = selectedRange()
        let range = text.paragraphRange(for: selection)

        // Paragraph ranges relative to `range` (each includes its line break).
        var paragraphs: [NSRange] = []
        text.enumerateSubstrings(in: range, options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in
            paragraphs.append(NSRange(location: enclosing.location - range.location, length: enclosing.length))
        }
        if paragraphs.isEmpty {   // empty note, or cursor on the empty last line
            paragraphs = [NSRange(location: 0, length: 0)]
        }

        let edited = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let removing = paragraphs.allSatisfy { Self.isBullet(edited.string, at: $0.location) }

        for paragraph in paragraphs.reversed() {
            if removing {
                removeBullet(in: edited, paragraph: paragraph)
            } else if !Self.isBullet(edited.string, at: paragraph.location) {
                addBullet(in: edited, paragraph: paragraph)
            }
        }

        guard shouldChangeText(in: range, replacementString: edited.string) else { return }
        storage.replaceCharacters(in: range, with: edited)
        didChangeText()

        // Keep the cursor where it was (shifted by the marker), or select the list.
        if paragraphs.count == 1 && selection.length == 0 {
            let shift = removing ? -Self.markerLength : Self.markerLength
            let location = max(range.location, min(selection.location + shift, range.location + edited.length))
            setSelectedRange(NSRange(location: location, length: 0))
        } else {
            setSelectedRange(NSRange(location: range.location, length: max(edited.length - 1, 0)))
        }
        syncTypingAttributes()
    }

    func isInBulletList() -> Bool {
        let paragraph = (string as NSString).paragraphRange(for: NSRange(location: selectedRange().location, length: 0))
        return Self.isBullet(string, at: paragraph.location)
    }

    // MARK: - Restyling existing text

    /// Converts the whole note from one note font to another. Sizes scale
    /// proportionally, and words that were bold or italic stay bold or italic.
    func applyNoteFont(from old: FontChoice, to new: FontChoice) {
        convertFonts(from: old, to: new, in: nil)
    }

    /// Converts only the text in `range` (the highlighted text). Can be undone with ⌘Z.
    func applyFont(from old: FontChoice, to new: FontChoice, in range: NSRange) {
        guard let storage = textStorage else { return }
        let range = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard range.length > 0, shouldChangeText(in: range, replacementString: nil) else { return }
        convertFonts(from: old, to: new, in: range)
        didChangeText()
    }

    /// The font of the character at `location`, as a style-panel choice.
    func fontChoice(at location: Int) -> FontChoice {
        guard let storage = textStorage, storage.length > 0 else { return FontChoice() }
        let index = min(location, storage.length - 1)
        let font = (storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont) ?? NoteContentView.defaultFont
        return FontLibrary.choice(for: font)
    }

    private func convertFonts(from old: FontChoice, to new: FontChoice, in limit: NSRange?) {
        guard let storage = textStorage, !hasMarkedText() else { return }
        let manager = NSFontManager.shared
        let oldBase = FontLibrary.font(for: old)
        let oldWeight = manager.weight(of: oldBase)
        let oldTraits = manager.traits(of: oldBase)
        let scale = CGFloat(new.size / old.size)

        func convert(_ font: NSFont) -> NSFont {
            let size = max(4, (font.pointSize * scale * 2).rounded() / 2)
            var result = FontLibrary.font(for: new, size: size)
            let traits = manager.traits(of: font)
            let wasEmphasized = manager.weight(of: font) > oldWeight + 1
                || (traits.contains(.boldFontMask) && !oldTraits.contains(.boldFontMask))
            if wasEmphasized { result = manager.convert(result, toHaveTrait: .boldFontMask) }
            if traits.contains(.italicFontMask) && !oldTraits.contains(.italicFontMask) {
                result = manager.convert(result, toHaveTrait: .italicFontMask)
            }
            return result
        }

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: limit ?? NSRange(location: 0, length: storage.length)) { value, range, _ in
            storage.addAttribute(.font, value: convert((value as? NSFont) ?? oldBase), range: range)
        }
        storage.endEditing()
        if limit == nil {
            typingAttributes[.font] = convert((typingAttributes[.font] as? NSFont) ?? oldBase)
        }
        applyLayout()   // bullets and line spacing follow the new font size
    }

    /// Re-applies line spacing and bullet style to the whole note.
    func applyLayout() {
        applyLineSpacing()
        applyBulletStyle()
    }

    /// Sets the line spacing on every paragraph, and for whatever is typed next.
    func applyLineSpacing() {
        guard let storage = textStorage, !hasMarkedText() else { return }
        let text = storage.string as NSString
        var paragraphs: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length),
                                 options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in
            paragraphs.append(enclosing)
        }

        storage.beginEditing()
        for paragraph in paragraphs where !Self.isBullet(storage.string, at: paragraph.location) {
            let fallback = (storage.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont)
                ?? NoteContentView.defaultFont
            let style = ((storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil)
                as? NSParagraphStyle) ?? .default).mutableCopy() as! NSMutableParagraphStyle
            Self.setLineSpacing(style, multiple: lineSpacing,
                                lineHeight: Self.textLineHeight(in: storage, paragraph: paragraph, fallback: fallback,
                                                                skipFirst: false),
                                capAtNaturalHeight: false)
            storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
        }
        storage.endEditing()

        let typing = ((typingAttributes[.paragraphStyle] as? NSParagraphStyle) ?? .default)
            .mutableCopy() as! NSMutableParagraphStyle
        let typingFont = (typingAttributes[.font] as? NSFont) ?? NoteContentView.defaultFont
        let typingIsBullet = typing.headIndent > 0 && isInBulletList()
        Self.setLineSpacing(typing, multiple: lineSpacing, lineHeight: Self.lineHeight(of: typingFont),
                            capAtNaturalHeight: typingIsBullet)
        typingAttributes[.paragraphStyle] = typing
    }

    /// Line spacing is added *between* lines (not above them), so the first line of a
    /// note stays put. Below 1× the lines are tightened instead.
    private static func setLineSpacing(_ style: NSMutableParagraphStyle, multiple: Double,
                                       lineHeight: CGFloat, capAtNaturalHeight: Bool) {
        style.lineHeightMultiple = 0
        if multiple >= 1 {
            style.lineSpacing = (CGFloat(multiple) - 1) * lineHeight
            // Bullets: a big bullet shouldn't make its line taller than the text.
            style.maximumLineHeight = capAtNaturalHeight ? lineHeight : 0
        } else {
            style.lineSpacing = 0
            style.maximumLineHeight = lineHeight * CGFloat(multiple)
        }
    }

    /// A normal (non-bullet) paragraph style with this note's line spacing.
    private var plainParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let font = (typingAttributes[.font] as? NSFont) ?? NoteContentView.defaultFont
        Self.setLineSpacing(style, multiple: lineSpacing, lineHeight: Self.lineHeight(of: font), capAtNaturalHeight: false)
        return style
    }

    /// Re-applies `bulletStyle` (shape, size, indent, spacing) to every bullet in the note.
    /// Shapes are single characters, so text length never changes and undo stays valid.
    func applyBulletStyle() {
        guard let storage = textStorage, !hasMarkedText() else { return }
        let text = storage.string as NSString
        var starts: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length),
                                 options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in
            if Self.isBullet(storage.string, at: enclosing.location) { starts.append(enclosing) }
        }
        guard !starts.isEmpty else { return }

        let marker = String(bulletStyle.shape.marker)
        storage.beginEditing()
        for paragraph in starts {
            let markerRange = NSRange(location: paragraph.location, length: 1)
            if text.substring(with: markerRange) != marker {
                let attributes = storage.attributes(at: paragraph.location, effectiveRange: nil)
                storage.replaceCharacters(in: markerRange, with: NSAttributedString(string: marker, attributes: attributes))
            }
            formatBullet(in: storage, paragraph: paragraph)
        }
        storage.endEditing()
        syncTypingAttributes()
    }

    /// Font changes (Fonts panel, Bigger/Smaller, Bold…) and pastes re-size the bullets to match.
    override func changeFont(_ sender: Any?) {
        super.changeFont(sender)
        applyLayout()
    }

    /// Pasted text takes on this note's line spacing and bullet style.
    override func paste(_ sender: Any?) {
        super.paste(sender)
        applyLayout()
    }

    // MARK: - Typing behaviour inside lists

    /// Return continues the list; Return on an empty bullet ends it.
    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let selection = selectedRange()
        let paragraph = text.paragraphRange(for: NSRange(location: selection.location, length: 0))

        guard Self.isBullet(string, at: paragraph.location) else {
            super.insertNewline(sender)
            return
        }

        let content = text.substring(with: paragraph)
            .dropFirst(2)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty && selection.length == 0 {
            toggleBulletList(sender)   // empty item: leave the list
            return
        }

        super.insertNewline(sender)
        let start = selectedRange().location
        insertText(markerString, replacementRange: selectedRange())
        if let storage = textStorage {
            let newParagraph = (storage.string as NSString).paragraphRange(for: NSRange(location: start, length: 0))
            formatBullet(in: storage, paragraph: newParagraph)
        }
        syncTypingAttributes()
    }

    /// Delete right after a bullet removes the bullet (not the previous line).
    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0 {
            let paragraph = (string as NSString).paragraphRange(for: NSRange(location: selection.location, length: 0))
            if Self.isBullet(string, at: paragraph.location),
               selection.location == paragraph.location + Self.markerLength {
                toggleBulletList(sender)
                return
            }
        }
        super.deleteBackward(sender)
    }

    /// Typing "- " or "* " at the start of a line starts a list (like Notes).
    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let typed = (string as? String) ?? (string as? NSAttributedString)?.string, typed == " ",
           selectedRange().length == 0 {
            let text = self.string as NSString
            let cursor = selectedRange().location
            let paragraph = text.paragraphRange(for: NSRange(location: cursor, length: 0))
            let before = text.substring(with: NSRange(location: paragraph.location, length: cursor - paragraph.location))
            if before == "-" || before == "*" {
                let dash = NSRange(location: paragraph.location, length: 1)
                if shouldChangeText(in: dash, replacementString: "") {
                    textStorage?.replaceCharacters(in: dash, with: "")
                    didChangeText()
                    setSelectedRange(NSRange(location: paragraph.location, length: 0))
                    toggleBulletList(nil)
                    return
                }
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    // MARK: - Helpers

    /// A paragraph is a bullet item if it starts with one of the bullet characters + tab.
    static func isBullet(_ string: String, at location: Int) -> Bool {
        let text = string as NSString
        guard location + markerLength <= text.length else { return false }
        let pair = text.substring(with: NSRange(location: location, length: markerLength))
        guard pair.count == 2, pair.last == "\t", let first = pair.first else { return false }
        return BulletStyle.Shape.allMarkers.contains(first)
    }

    private func addBullet(in text: NSMutableAttributedString, paragraph: NSRange) {
        var attributes = paragraph.length > 0 && paragraph.location < text.length
            ? text.attributes(at: paragraph.location, effectiveRange: nil)
            : typingAttributes
        attributes.removeValue(forKey: .link)
        attributes.removeValue(forKey: .attachment)
        attributes.removeValue(forKey: .baselineOffset)
        text.insert(NSAttributedString(string: markerString, attributes: attributes), at: paragraph.location)
        formatBullet(in: text, paragraph: NSRange(location: paragraph.location, length: paragraph.length + Self.markerLength))
    }

    private func removeBullet(in text: NSMutableAttributedString, paragraph: NSRange) {
        guard Self.isBullet(text.string, at: paragraph.location) else { return }
        text.deleteCharacters(in: NSRange(location: paragraph.location, length: Self.markerLength))
        let remaining = NSRange(location: paragraph.location, length: paragraph.length - Self.markerLength)
        if remaining.length > 0 {
            text.addAttribute(.paragraphStyle, value: plainParagraphStyle, range: remaining)
        }
        typingAttributes[.paragraphStyle] = plainParagraphStyle
    }

    /// Sizes and centres the bullet glyph, and sets the paragraph's indent and tab stop.
    /// `paragraph` starts with the bullet and includes the paragraph's line break.
    private func formatBullet(in text: NSMutableAttributedString, paragraph: NSRange) {
        let loc = paragraph.location
        guard loc + Self.markerLength <= text.length else { return }

        // The text's font: the first character after the tab, or the tab itself on an empty item.
        let contentIndex = loc + Self.markerLength
        let hasContent = contentIndex < text.length
            && !CharacterSet.newlines.contains(Unicode.Scalar((text.string as NSString).character(at: contentIndex)) ?? " ")
        let fontIndex = hasContent ? contentIndex : loc + 1
        let bodyFont = (text.attribute(.font, at: fontIndex, effectiveRange: nil) as? NSFont) ?? NoteContentView.defaultFont

        let shape = bulletStyle.shape
        let markerSize = bodyFont.pointSize * shape.baseScale * min(max(bulletStyle.size, BulletStyle.sizeRange.lowerBound),
                                                                   BulletStyle.sizeRange.upperBound)
        let markerFont = NSFont.systemFont(ofSize: markerSize)
        let glyph = Self.glyphBounds(of: shape.marker, in: markerFont)

        // Centre the bullet on the middle of the text's lowercase letters.
        let baselineOffset = bodyFont.xHeight / 2 - glyph.midY

        text.addAttributes([.font: markerFont, .baselineOffset: baselineOffset],
                           range: NSRange(location: loc, length: 1))
        text.addAttribute(.font, value: bodyFont, range: NSRange(location: loc + 1, length: 1))
        text.removeAttribute(.baselineOffset, range: NSRange(location: loc + 1, length: 1))

        let indent = CGFloat(bulletStyle.indent)
        let textStart = indent + glyph.advance + CGFloat(bulletStyle.spacing)
        let base = (text.attribute(.paragraphStyle, at: loc, effectiveRange: nil) as? NSParagraphStyle) ?? .default
        let style = base.mutableCopy() as! NSMutableParagraphStyle
        style.firstLineHeadIndent = indent
        style.headIndent = textStart
        style.tabStops = [NSTextTab(textAlignment: .left, location: textStart)]
        style.defaultTabInterval = 28
        // A big bullet shouldn't make its line taller than the text needs.
        Self.setLineSpacing(style, multiple: lineSpacing,
                            lineHeight: Self.textLineHeight(in: text, paragraph: paragraph, fallback: bodyFont),
                            capAtNaturalHeight: true)
        text.addAttribute(.paragraphStyle, value: style, range: paragraph)
    }

    /// Natural line height of the tallest text font in the paragraph (ignoring the bullet).
    private static func textLineHeight(in text: NSAttributedString, paragraph: NSRange, fallback: NSFont,
                                       skipFirst: Bool = true) -> CGFloat {
        var height = lineHeight(of: fallback)
        let skip = skipFirst ? 1 : 0   // skip the bullet character
        let textRange = NSRange(location: paragraph.location + skip, length: max(paragraph.length - skip, 0))
        text.enumerateAttribute(.font, in: textRange) { value, _, _ in
            if let font = value as? NSFont { height = max(height, lineHeight(of: font)) }
        }
        return height
    }

    private static func lineHeight(of font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    /// Typing right after a bullet should use the text's font, not the bullet's.
    private func syncTypingAttributes() {
        guard let storage = textStorage else { return }
        let cursor = selectedRange().location
        guard cursor > 0, cursor <= storage.length else { return }
        var attributes = storage.attributes(at: cursor - 1, effectiveRange: nil)
        if (storage.string as NSString).character(at: cursor - 1) == 0x09 /* tab */ {
            attributes.removeValue(forKey: .baselineOffset)
            typingAttributes = attributes
        }
    }

    private static func glyphBounds(of character: Character, in font: NSFont) -> (midY: CGFloat, advance: CGFloat) {
        let ctFont = font as CTFont
        var chars = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        guard CTFontGetGlyphsForCharacters(ctFont, &chars, &glyphs, chars.count) else {
            return (font.xHeight / 2, font.pointSize * 0.5)
        }
        var rect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &glyphs, &rect, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyphs, &advance, 1)
        return (rect.midY, advance.width)
    }
}
