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

/// How a note looks. Grows in later stages (glass, fonts, presets).
nonisolated struct NoteStyle: Codable, Equatable, Sendable {
    var background: RGBAColor
    /// nil = automatic: dark text on light backgrounds, light text on dark ones.
    var textColor: RGBAColor?

    static let `default` = NoteStyle(background: NotePalette.yellow.color, textColor: nil)

    var isDark: Bool { background.isDark }

    var resolvedTextColor: RGBAColor {
        textColor ?? (isDark ? RGBAColor(hex: 0xF2F2F4) : RGBAColor(hex: 0x1D1D1F))
    }

    init(background: RGBAColor, textColor: RGBAColor? = nil) {
        self.background = background
        self.textColor = textColor
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decodeIfPresent(RGBAColor.self, forKey: .background) ?? NotePalette.yellow.color
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor)
    }
}

/// Quick-pick background colours (the color wheel arrives in a later stage).
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

    /// Perceived brightness, 0 (black) … 1 (white).
    var luminance: Double { 0.299 * red + 0.587 * green + 0.114 * blue }

    var isDark: Bool { luminance < 0.55 }

    func isClose(to other: RGBAColor, tolerance: Double = 0.01) -> Bool {
        abs(red - other.red) < tolerance && abs(green - other.green) < tolerance
            && abs(blue - other.blue) < tolerance && abs(alpha - other.alpha) < tolerance
    }
}
