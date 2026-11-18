import SwiftUI

/// Live-editing state for one note's style popover.
@Observable
final class StyleEditorModel {
    var style: NoteStyle {
        didSet { if style != oldValue { onChange?(style) } }
    }
    var onChange: ((NoteStyle) -> Void)?
    var onUseAsDefault: (() -> Void)?

    /// Text that was highlighted when the panel opened. If set, font changes apply only to it.
    var selection: NSRange?
    /// The highlighted text's current font (shown in the Text tab while `selection` is set).
    var selectionFont = FontChoice()
    var onSelectionFontChange: ((_ old: FontChoice, _ new: FontChoice, _ range: NSRange) -> Void)?

    init(style: NoteStyle) {
        self.style = style
    }

    /// What the Text tab's font controls show and edit: the highlighted text, or the whole note.
    var textFont: FontChoice {
        get { selection == nil ? style.font : selectionFont }
        set {
            if let selection {
                let old = selectionFont
                guard newValue != old else { return }
                selectionFont = newValue
                onSelectionFontChange?(old, newValue, selection)
            } else {
                style.font = newValue
            }
        }
    }
}

/// The popover opened by a note's palette button, in three tabs:
/// Background (solid/glass), Text (font, weight, size, line spacing) and Bullets.
struct StyleEditorView: View {
    @Bindable var model: StyleEditorModel
    @State private var savedAsDefault = false
    @AppStorage("styleEditorTab") private var tab: Tab = .background

    /// One fixed size for every tab, so the popover never resizes (and shifts) when
    /// switching tabs. Wide enough for the widest control (the tab bar, ~290 pt) plus
    /// padding; tall enough for the tallest tab (Text).
    static let panelSize = CGSize(width: 340, height: 340)
    static let padding: CGFloat = 16

    enum Tab: String, CaseIterable {
        case background = "Background", text = "Text", bullets = "Bullets"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .background: backgroundControls
            case .text: textControls
            case .bullets: bulletControls
            }

            Spacer(minLength: 0)

            Divider()

            Button(savedAsDefault ? "Saved as Default ✓" : "Use as Default for New Notes") {
                model.onUseAsDefault?()
                savedAsDefault = true
            }
            .buttonStyle(.borderless)
            .disabled(savedAsDefault)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Self.padding)
        .frame(width: Self.panelSize.width, height: Self.panelSize.height, alignment: .top)
        .onChange(of: model.style) { savedAsDefault = false }
    }

    // MARK: - Background

    private var backgroundControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Background", selection: $model.style.kind) {
                Text("Solid").tag(NoteStyle.Kind.solid)
                Text("Glass").tag(NoteStyle.Kind.glass)
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()

            switch model.style.kind {
            case .solid: solidControls
            case .glass: glassControls
            }
        }
    }

    // MARK: - Solid

    private var solidControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Color")
            HStack(spacing: 6) {
                ForEach(NotePalette.allCases, id: \.self) { swatch in
                    SwatchButton(
                        color: swatch.color,
                        isSelected: model.style.background.isClose(to: swatch.color),
                        help: swatch.name
                    ) {
                        model.style.background = swatch.color
                    }
                }
            }
            HStack {
                Text("Custom color")
                Spacer()
                // Opens the macOS Colors panel (wheel, sliders, palettes, eyedropper).
                ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                    .labelsHidden()
            }
            percentSlider("Opacity", value: $model.style.opacity, in: NoteStyle.opacityRange)
        }
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: model.style.background.nsColor) },
            set: { model.style.background = RGBAColor(NSColor($0)).withAlpha(1) }
        )
    }

    // MARK: - Glass

    private var glassControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Tone")
            Picker("Tone", selection: $model.style.glassTone) {
                Text("Light").tag(NoteStyle.Tone.light)
                Text("Dark").tag(NoteStyle.Tone.dark)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            percentSlider("Intensity", value: $model.style.glassIntensity, in: 0...1)
        }
    }

    // MARK: - Text

    private var textControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Font")
            Picker("Font", selection: fontFamily) {
                Text(FontLibrary.systemFamilyName).tag(String?.none)
                if !FontLibrary.suggestedFamilies.isEmpty {
                    Section("Suggested") {
                        ForEach(FontLibrary.suggestedFamilies, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                }
                Section("All Fonts") {
                    ForEach(FontLibrary.allFamilies, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            .labelsHidden()

            HStack {
                sectionLabel("Weight")
                Spacer()
                Picker("Weight", selection: $model.textFont.face) {
                    ForEach(FontLibrary.faces(for: model.textFont.family), id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    sectionLabel("Size")
                    Spacer()
                    Stepper(value: $model.textFont.size, in: FontChoice.sizeRange, step: 1) {
                        Text("\(Int(model.textFont.size.rounded())) pt")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Slider(value: $model.textFont.size, in: FontChoice.sizeRange, step: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    sectionLabel(model.selection == nil ? "Line spacing" : "Line spacing (whole note)")
                    Spacer()
                    Text(model.style.lineSpacing.formatted(.number.precision(.fractionLength(2))) + "×")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.style.lineSpacing, in: NoteStyle.lineSpacingRange, step: 0.05)
            }

            Text(model.selection == nil
                 ? "Changing the whole note. Highlight text first to change just that part."
                 : "Changing the highlighted text only.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Changing family keeps the weight if the new family has it, else picks its regular.
    private var fontFamily: Binding<String?> {
        Binding(
            get: { model.textFont.family },
            set: { family in
                var font = model.textFont
                font.face = FontLibrary.bestFace(for: family, preferring: font.face)
                font.family = family
                model.textFont = font
            }
        )
    }

    // MARK: - Bullets

    private var bulletControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Shape")
            HStack(spacing: 4) {
                ForEach(BulletStyle.Shape.allCases, id: \.self) { shape in
                    BulletShapeButton(shape: shape, isSelected: model.style.bullets.shape == shape) {
                        model.style.bullets.shape = shape
                    }
                }
            }
            percentSlider("Size", value: $model.style.bullets.size, in: BulletStyle.sizeRange)
            pointSlider("Indent", value: $model.style.bullets.indent, in: BulletStyle.indentRange)
            pointSlider("Space before text", value: $model.style.bullets.spacing, in: BulletStyle.spacingRange)
        }
    }

    private func pointSlider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionLabel(title)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded())) pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 1)
        }
    }

    // MARK: - Pieces

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func percentSlider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionLabel(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

private struct SwatchButton: View {
    let color: RGBAColor
    let isSelected: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: color.nsColor))
                .overlay(Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 0.5))
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .padding(-3)
                        .opacity(isSelected ? 1 : 0)
                )
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct BulletShapeButton: View {
    let shape: BulletStyle.Shape
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(String(shape.marker))
                .font(.system(size: 15 * shape.baseScale))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 1.5 : 0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shape.name)
    }
}
