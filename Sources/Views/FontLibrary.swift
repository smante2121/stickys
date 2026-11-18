import AppKit

/// Looks up installed fonts for the style panel and turns a `FontChoice` into an `NSFont`.
enum FontLibrary {
    static let systemFamilyName = "SF Pro (System)"

    /// Installed font families, alphabetical (hidden system families excluded).
    static let allFamilies: [String] = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

    /// Sleek fonts that suit the glass look, shown at the top of the list if installed.
    static let suggestedFamilies: [String] = [
        "SF Pro", "SF Pro Rounded", "New York", "Avenir Next", "Helvetica Neue", "Gill Sans", "Optima", "Charter",
    ].filter { allFamilies.contains($0) }

    private static let systemWeights: [(name: String, weight: NSFont.Weight)] = [
        ("Ultra Light", .ultraLight), ("Thin", .thin), ("Light", .light), ("Regular", .regular),
        ("Medium", .medium), ("Semibold", .semibold), ("Bold", .bold), ("Heavy", .heavy), ("Black", .black),
    ]

    /// The upright weights available in a family (italics come from ⌘I instead).
    static func faces(for family: String?) -> [String] {
        guard let family else { return systemWeights.map(\.name) }
        var seen = Set<String>()
        return members(of: family).compactMap { member in
            guard let face = member.face, !member.isItalic, seen.insert(face).inserted else { return nil }
            return face
        }
    }

    /// When switching family, keep the same weight name if it exists, otherwise its "regular".
    static func bestFace(for family: String?, preferring current: String) -> String {
        let faces = faces(for: family)
        if faces.contains(current) { return current }
        for name in ["Regular", "Roman", "Book", "Text", "Medium"] where faces.contains(name) { return name }
        return faces.first ?? "Regular"
    }

    static func font(for choice: FontChoice, size: CGFloat? = nil) -> NSFont {
        let size = size ?? CGFloat(choice.size)
        guard let family = choice.family else {
            let weight = systemWeights.first { $0.name == choice.face }?.weight ?? .regular
            return .systemFont(ofSize: size, weight: weight)
        }
        if let member = members(of: family).first(where: { $0.face == choice.face && !$0.isItalic }),
           let font = NSFont(name: member.postScriptName, size: size) {
            return font
        }
        return NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
            ?? .systemFont(ofSize: size)
    }

    /// Describes an existing font as a style-panel choice (family, upright weight, size).
    static func choice(for font: NSFont) -> FontChoice {
        let size = Double(font.pointSize)
        guard let family = font.familyName, !family.hasPrefix(".") else {
            // System font: pick the nearest named weight.
            let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
            let weight = (traits?[.weight] as? CGFloat) ?? 0
            let nearest = systemWeights.min { abs($0.weight.rawValue - weight) < abs($1.weight.rawValue - weight) }
            return FontChoice(family: nil, face: nearest?.name ?? "Regular", size: size)
        }
        var face = members(of: family).first { $0.postScriptName == font.fontName }?.face ?? "Regular"
        // "Light Italic" → "Light", "Italic" → "Regular": the panel lists upright weights only.
        face = face.replacingOccurrences(of: "Italic", with: "").replacingOccurrences(of: "Oblique", with: "")
            .trimmingCharacters(in: .whitespaces)
        return FontChoice(family: family, face: bestFace(for: family, preferring: face.isEmpty ? "Regular" : face),
                          size: size)
    }

    private struct Member {
        let postScriptName: String
        let face: String?
        let isItalic: Bool
    }

    /// NSFontManager describes each member as [PostScript name, face name, weight, traits].
    private static func members(of family: String) -> [Member] {
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { entry in
            guard let name = entry.first as? String else { return nil }
            let traits = (entry.count > 3 ? entry[3] as? NSNumber : nil)?.uintValue ?? 0
            return Member(
                postScriptName: name,
                face: entry.count > 1 ? entry[1] as? String : nil,
                isItalic: traits & NSFontTraitMask.italicFontMask.rawValue != 0
            )
        }
    }
}
