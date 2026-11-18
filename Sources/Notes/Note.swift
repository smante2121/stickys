import AppKit

/// Everything about a note except its text (which is stored as RTFD alongside).
nonisolated struct Note: Codable, Identifiable, Sendable {
    let id: UUID
    /// Window frame in screen coordinates. While collapsed this is the collapsed frame.
    var frame: CGRect
    /// Height to restore when expanding a collapsed note.
    var expandedHeight: CGFloat?
    var isCollapsed: Bool
    var floatsOnTop: Bool
    var style: NoteStyle
    var created: Date
    var modified: Date

    init(id: UUID = UUID(), frame: CGRect, style: NoteStyle = .default) {
        self.id = id
        self.frame = frame
        self.expandedHeight = nil
        self.isCollapsed = false
        self.floatsOnTop = false
        self.style = style
        self.created = Date()
        self.modified = Date()
    }

    /// Tolerant decoding: fields added in later versions fall back to defaults,
    /// so older notes.json files always load.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        frame = try c.decode(CGRect.self, forKey: .frame)
        expandedHeight = try c.decodeIfPresent(CGFloat.self, forKey: .expandedHeight)
        isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        floatsOnTop = try c.decodeIfPresent(Bool.self, forKey: .floatsOnTop) ?? false
        style = try c.decodeIfPresent(NoteStyle.self, forKey: .style) ?? .default
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? Date()
    }
}

/// How a note looks.
nonisolated struct NoteStyle: Codable, Equatable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable { case solid, glass }
    nonisolated enum Tone: String, Codable, Sendable { case light, dark }

    /// Solid colour or colourless Liquid Glass.
    var kind: Kind
    /// Solid background colour (always fully opaque; see `opacity`).
    var background: RGBAColor
    /// Solid background opacity, 0.15 … 1.
    var opacity: Double
    /// Glass: light (white frost, dark text) or dark (dark frost, light text).
    var glassTone: Tone
    /// Glass: 0 = barely there, 1 = heavily frosted.
    var glassIntensity: Double
    /// nil = automatic: dark text on light backgrounds, light text on dark ones.
    var textColor: RGBAColor?
    /// How bulleted lists look in this note.
    var bullets: BulletStyle
    /// Space between lines, as a multiple of the font's normal line height (1 = normal).
    var lineSpacing: Double
    /// The note's font: family, weight and size.
    var font: FontChoice

    static let lineSpacingRange: ClosedRange<Double> = 0.9...2

    static let `default` = NoteStyle()

    static let opacityRange: ClosedRange<Double> = 0.15...1

    init(
        kind: Kind = .solid,
        background: RGBAColor = NotePalette.yellow.color,
        opacity: Double = 1,
        glassTone: Tone = .dark,
        glassIntensity: Double = 0.35,
        textColor: RGBAColor? = nil,
        bullets: BulletStyle = BulletStyle(),
        lineSpacing: Double = 1,
        font: FontChoice = FontChoice()
    ) {
        self.kind = kind
        self.background = background
        self.opacity = opacity
        self.glassTone = glassTone
        self.glassIntensity = glassIntensity
        self.textColor = textColor
        self.bullets = bullets
        self.lineSpacing = lineSpacing
        self.font = font
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NoteStyle()
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? d.kind
        background = try c.decodeIfPresent(RGBAColor.self, forKey: .background) ?? d.background
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
        glassTone = try c.decodeIfPresent(Tone.self, forKey: .glassTone) ?? d.glassTone
        glassIntensity = try c.decodeIfPresent(Double.self, forKey: .glassIntensity) ?? d.glassIntensity
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor)
        bullets = try c.decodeIfPresent(BulletStyle.self, forKey: .bullets) ?? d.bullets
        lineSpacing = try c.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? d.lineSpacing
        font = try c.decodeIfPresent(FontChoice.self, forKey: .font) ?? d.font
    }

    var isDark: Bool {
        switch kind {
        case .solid: background.isDark
        case .glass: glassTone == .dark
        }
    }

    var resolvedTextColor: RGBAColor {
        textColor ?? (isDark ? RGBAColor(hex: 0xF2F2F4) : RGBAColor(hex: 0x1D1D1F))
    }
}

/// A note's font. Changing it converts the whole note: the family and weight change,
/// sizes scale proportionally (headings stay bigger), and bold/italic words stay bold/italic.
nonisolated struct FontChoice: Codable, Equatable, Sendable {
    /// nil = the system font (SF Pro).
    var family: String?
    /// Face within the family, e.g. "Regular", "Light", "Medium".
    var face: String = "Regular"
    var size: Double = 15

    static let sizeRange: ClosedRange<Double> = 9...48

    init(family: String? = nil, face: String = "Regular", size: Double = 15) {
        self.family = family
        self.face = face
        self.size = size
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        family = try c.decodeIfPresent(String.self, forKey: .family)
        face = try c.decodeIfPresent(String.self, forKey: .face) ?? "Regular"
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 15
    }
}

/// How bullets look: shape, size, indent from the edge, and gap before the text.
nonisolated struct BulletStyle: Codable, Equatable, Sendable {
    nonisolated enum Shape: String, Codable, CaseIterable, Sendable {
        case disc, circle, square, diamond, dash, arrow, check, star

        /// The character used in the text. Each is a single character, so switching
        /// shapes never changes the length of the text.
        var marker: Character {
            switch self {
            case .disc: "●"
            case .circle: "○"
            case .square: "■"
            case .diamond: "◆"
            case .dash: "–"
            case .arrow: "→"
            case .check: "✓"
            case .star: "★"
            }
        }

        /// Evens out how big the different glyphs look at the same size setting.
        var baseScale: Double {
            switch self {
            case .disc: 0.5
            case .circle: 0.5
            case .square: 0.42
            case .diamond: 0.55
            case .dash: 0.9
            case .arrow: 0.85
            case .check: 0.85
            case .star: 0.65
            }
        }

        var name: String { rawValue.capitalized }

        /// Every character recognised as a bullet, including ones used by earlier versions.
        static let allMarkers = Set(allCases.map(\.marker)).union(["•", "◦", "▪"])
    }

    var shape: Shape = .disc
    /// Relative to the text size: 1 = normal.
    var size: Double = 1.0
    /// Points from the note's left text edge to the bullet.
    var indent: Double = 8
    /// Points between the bullet and the text.
    var spacing: Double = 8

    static let sizeRange: ClosedRange<Double> = 0.6...1.6
    static let indentRange: ClosedRange<Double> = 0...40
    static let spacingRange: ClosedRange<Double> = 2...24

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BulletStyle()
        shape = try c.decodeIfPresent(Shape.self, forKey: .shape) ?? d.shape
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        indent = try c.decodeIfPresent(Double.self, forKey: .indent) ?? d.indent
        spacing = try c.decodeIfPresent(Double.self, forKey: .spacing) ?? d.spacing
    }
}

/// Quick-pick background colours (any other colour comes from the colour wheel).
nonisolated enum NotePalette: String, CaseIterable, Sendable {
    case yellow, paper, charcoal, blue, green, pink, purple, gray

    var name: String {
        switch self {
        case .yellow: "Yellow"
        case .paper: "Paper White"
        case .charcoal: "Charcoal"
        case .blue: "Blue"
        case .green: "Green"
        case .pink: "Pink"
        case .purple: "Purple"
        case .gray: "Gray"
        }
    }

    var color: RGBAColor {
        switch self {
        case .yellow: RGBAColor(hex: 0xFFF1A8)
        case .paper: RGBAColor(hex: 0xFFFFFF)
        case .charcoal: RGBAColor(hex: 0x2A2422)
        case .blue: RGBAColor(hex: 0xD2E7FF)
        case .green: RGBAColor(hex: 0xD6F2CC)
        case .pink: RGBAColor(hex: 0xFFD9E6)
        case .purple: RGBAColor(hex: 0xE6DCFF)
        case .gray: RGBAColor(hex: 0xE7E7EA)
        }
    }
}

/// A colour that can be saved to JSON (sRGB components 0…1).
nonisolated struct RGBAColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? NSColor.black
        self.init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func withAlpha(_ alpha: Double) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Perceived brightness, 0 (black) … 1 (white).
    var luminance: Double { 0.299 * red + 0.587 * green + 0.114 * blue }

    var isDark: Bool { luminance < 0.55 }

    func isClose(to other: RGBAColor, tolerance: Double = 0.01) -> Bool {
        abs(red - other.red) < tolerance && abs(green - other.green) < tolerance
            && abs(blue - other.blue) < tolerance && abs(alpha - other.alpha) < tolerance
    }
}
