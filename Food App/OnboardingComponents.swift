import SwiftUI
#if canImport(UIKit)
import UIKit
import CoreText
#endif

enum OnboardingGlassTheme {
    static let accentStart = Color(red: 1.00, green: 0.78, blue: 0.33)
    static let accentEnd = Color(red: 0.21, green: 0.86, blue: 0.73)
    static let textPrimary = adaptiveColor(
        light: UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 0.98),
        dark: UIColor(white: 1.0, alpha: 0.98)
    )
    static let textSecondary = adaptiveColor(
        light: UIColor(red: 0.23, green: 0.28, blue: 0.36, alpha: 0.84),
        dark: UIColor(white: 1.0, alpha: 0.84)
    )
    static let textMuted = adaptiveColor(
        light: UIColor(red: 0.33, green: 0.39, blue: 0.47, alpha: 0.70),
        dark: UIColor(white: 1.0, alpha: 0.58)
    )
    static let selectedSurface = Color(red: 1.00, green: 0.85, blue: 0.52).opacity(0.24)
    static let buttonPrimaryText = Color(red: 0.09, green: 0.09, blue: 0.10)
    static let buttonSecondaryText = textPrimary

    /// Primary CTA fill — black in light mode, white in dark mode.
    /// Use together with `ctaForeground` so the button text inverts too.
    static let ctaBackground = adaptiveColor(
        light: UIColor.black,
        dark: UIColor.white
    )
    /// Text/icon color to pair with `ctaBackground`.
    static let ctaForeground = adaptiveColor(
        light: UIColor.white,
        dark: UIColor.black
    )

    // MARK: - Dynamic UIColors for UIKit pickers

    /// Selected row text color for UIPickerView wheels.
    static let pickerSelectedTextUI = UIColor { trait in
        trait.userInterfaceStyle == .dark ? .white : .black
    }
    /// Text color for rows immediately adjacent to the selected row.
    static let pickerAdjacentTextUI = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.55)
            : UIColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1)
    }
    /// Text color for rows further from the selected row.
    static let pickerDistantTextUI = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.30)
            : UIColor(red: 0.81, green: 0.81, blue: 0.81, alpha: 1)
    }
    static let buttonShadow = adaptiveColor(
        light: UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 0.10),
        dark: UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.20)
    )
    static let selectionGlow = adaptiveColor(
        light: UIColor(red: 0.96, green: 0.71, blue: 0.29, alpha: 0.18),
        dark: UIColor(white: 1.0, alpha: 0.14)
    )
    static let panelFill = adaptiveColor(
        light: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.58),
        dark: UIColor(white: 1.0, alpha: 0.07)
    )
    static let panelStroke = adaptiveColor(
        light: UIColor(red: 0.79, green: 0.84, blue: 0.90, alpha: 0.55),
        dark: UIColor(white: 1.0, alpha: 0.14)
    )
    static let backgroundStart = adaptiveColor(
        light: UIColor(red: 0.97, green: 0.98, blue: 0.995, alpha: 1.0),
        dark: UIColor(red: 0.05, green: 0.08, blue: 0.11, alpha: 1.0)
    )
    static let backgroundEnd = adaptiveColor(
        light: UIColor(red: 0.90, green: 0.94, blue: 0.98, alpha: 1.0),
        dark: UIColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1.0)
    )
    static let dotOverlay = adaptiveColor(
        light: UIColor(red: 0.09, green: 0.12, blue: 0.18, alpha: 0.08),
        dark: UIColor(white: 1.0, alpha: 0.10)
    )
    static let noiseOverlay = adaptiveColor(
        light: UIColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.05),
        dark: UIColor(white: 1.0, alpha: 0.03)
    )

    // MARK: - Quiet Wellness Tokens (Onboarding refresh — pilot on OB08)
    //
    // A flatter, warmer palette being piloted on the Account screen. If the
    // direction validates, the rest of onboarding (OB01–07, OB09, OB10)
    // follows in a separate pass. See `docs/UI_COMPONENTS.md` →
    // "Onboarding refresh — in progress".

    /// Warm off-white (light) / soft charcoal (dark). Replaces
    /// `OnboardingAnimatedBackground` on screens migrated to the new direction.
    static let neutralBackground = adaptiveColor(
        light: UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1.0),  // #FAF7F2
        dark: UIColor(red: 0.086, green: 0.082, blue: 0.071, alpha: 1.0)  // #161512
    )

    /// Card and button surface; sits on top of `neutralBackground`.
    static let neutralSurface = adaptiveColor(
        light: UIColor.white,
        dark: UIColor(red: 0.122, green: 0.118, blue: 0.102, alpha: 1.0)  // #1F1E1A
    )

    /// Single accent for the new direction. Replaces the gradient pair
    /// (`accentStart`/`accentEnd`) on migrated screens.
    static let accentAmber = adaptiveColor(
        light: UIColor(red: 0.91, green: 0.64, blue: 0.24, alpha: 1.0),  // #E8A33D
        dark: UIColor(red: 0.94, green: 0.71, blue: 0.35, alpha: 1.0)   // #F0B458
    )

    /// 1-pt border on cards / buttons / circle nav buttons.
    static let hairline = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.06),
        dark: UIColor(white: 1.0, alpha: 0.10)
    )

    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}

enum OnboardingGlassMetrics {
    static let cornerRadius: CGFloat = 16
    static let innerCornerRadius: CGFloat = 12
}

enum OnboardingTypography {
    enum InstrumentSerifStyle {
        case regular
        case italic

        fileprivate var fileName: String {
            switch self {
            case .regular:
                return "InstrumentSerif-Regular"
            case .italic:
                return "InstrumentSerif-Italic"
            }
        }
    }

    static func instrumentSerif(style: InstrumentSerifStyle, size: CGFloat) -> Font {
#if canImport(UIKit)
        if let postScriptName = resolvedPostScriptName(for: style) {
            return .custom(postScriptName, size: size)
        }
#endif
        switch style {
        case .regular:
            return .system(size: size, weight: .regular, design: .serif)
        case .italic:
            return .system(size: size, weight: .regular, design: .serif).italic()
        }
    }

    static func onboardingHeadline(size: CGFloat = 28) -> Font {
        instrumentSerif(style: .regular, size: size)
    }

#if canImport(UIKit)
    private static var cachedPostScriptNames: [InstrumentSerifStyle: String] = [:]

    private static func resolvedPostScriptName(for style: InstrumentSerifStyle) -> String? {
        if let cached = cachedPostScriptNames[style] {
            return cached
        }

        if let direct = UIFont(name: style.fileName, size: 16)?.fontName {
            cachedPostScriptNames[style] = direct
            return direct
        }

        let fontURL =
            Bundle.main.url(forResource: style.fileName, withExtension: "ttf", subdirectory: "Fonts") ??
            Bundle.main.url(forResource: style.fileName, withExtension: "ttf")

        guard let url = fontURL else {
            return nil
        }

        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)

        guard let provider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(provider),
              let postScriptName = cgFont.postScriptName as String? else {
            return nil
        }

        cachedPostScriptNames[style] = postScriptName
        return postScriptName
    }
#endif
}

private struct OnboardingGlassPanel: ViewModifier {
    let cornerRadius: CGFloat
    let fillOpacity: Double
    let strokeOpacity: Double

    func body(content: Content) -> some View {
        let normalizedFill = max(0, min(1, fillOpacity / 0.07))
        let normalizedStroke = max(0, min(1, strokeOpacity / 0.14))

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(OnboardingGlassTheme.panelFill.opacity(normalizedFill))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(OnboardingGlassTheme.panelStroke.opacity(normalizedStroke), lineWidth: 1)
            )
    }
}

extension View {
    func onboardingGlassPanel(
        cornerRadius: CGFloat = OnboardingGlassMetrics.cornerRadius,
        fillOpacity: Double = 0.06,
        strokeOpacity: Double = 0.14
    ) -> some View {
        modifier(
            OnboardingGlassPanel(
                cornerRadius: cornerRadius,
                fillOpacity: fillOpacity,
                strokeOpacity: strokeOpacity
            )
        )
    }
}

struct OnboardingGlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(OnboardingGlassTheme.buttonPrimaryText)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: OnboardingGlassMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OnboardingGlassMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 1)
            )
            .shadow(color: OnboardingGlassTheme.buttonShadow, radius: 8, y: 3)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct OnboardingGlassSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(OnboardingGlassTheme.buttonSecondaryText)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Color.clear)
            .opacity(configuration.isPressed ? 0.84 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct OnboardingPrimaryButton: View {
    let title: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(OnboardingGlassTheme.buttonPrimaryText)
                        .controlSize(.small)
                }
                Text(title)
            }
        }
        .buttonStyle(OnboardingGlassPrimaryButtonStyle())
    }
}

struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(OnboardingGlassSecondaryButtonStyle())
    }
}

struct OnboardingProgressHeader: View {
    let step: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let safeStep = min(max(step, 0), max(total, 1))
            let progress = CGFloat(safeStep) / CGFloat(max(total, 1))

            HStack(spacing: 0) {
                Text("Step ")
                RollingNumberText(value: Double(safeStep), fractionDigits: 0)
                Text(" of ")
                RollingNumberText(value: Double(total), fractionDigits: 0)
            }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [OnboardingGlassTheme.accentStart, OnboardingGlassTheme.accentEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, proxy.size.width * progress))
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingValueCard: View {
    let title: String
    let bodyText: String
    var animatedNumber: Double? = nil
    var animatedFractionDigits: Int = 0
    var animatedPrefix: String = ""
    var animatedSuffix: String = ""
    var animatedUnit: String = ""
    var isSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(OnboardingGlassTheme.textPrimary.opacity(isSuccess ? 1.0 : 0.88))
                    .frame(width: 7, height: 7)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary.opacity(isSuccess ? 1.0 : 0.9))
            }

            if let animatedNumber {
                let effectiveSuffix = !animatedSuffix.isEmpty ? animatedSuffix : (animatedUnit.isEmpty ? "" : " \(animatedUnit)")
                HStack(spacing: 0) {
                    if !animatedPrefix.isEmpty {
                        Text(animatedPrefix)
                    }
                    RollingNumberText(value: animatedNumber, fractionDigits: animatedFractionDigits)
                    if !effectiveSuffix.isEmpty {
                        Text(effectiveSuffix)
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(OnboardingGlassTheme.textPrimary)
            } else {
                Text(bodyText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .onboardingGlassPanel(
            cornerRadius: OnboardingGlassMetrics.cornerRadius,
            fillOpacity: 0.06,
            strokeOpacity: 0.12
        )
    }
}

struct OnboardingSelectableTiles<Option: Identifiable & Equatable>: View {
    let options: [Option]
    let selected: Option?
    let label: (Option) -> String
    let onSelect: (Option) -> Void

    init(
        options: [Option],
        selected: Option?,
        label: @escaping (Option) -> String,
        onSelect: @escaping (Option) -> Void
    ) {
        self.options = options
        self.selected = selected
        self.label = label
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(options) { option in
                let isSelected = option == selected
                Button {
                    onSelect(option)
                } label: {
                    HStack {
                        Text(label(option))
                            .font(.system(size: 17, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? OnboardingGlassTheme.textPrimary : OnboardingGlassTheme.textMuted)
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(OnboardingGlassTheme.buttonPrimaryText)
                            .padding(8)
                            .background(Color.white, in: Circle())
                            .opacity(isSelected ? 1 : 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onboardingGlassPanel(
                        cornerRadius: OnboardingGlassMetrics.cornerRadius,
                        fillOpacity: isSelected ? 0.22 : 0.05,
                        strokeOpacity: 0.12
                    )
                    .shadow(color: isSelected ? OnboardingGlassTheme.selectionGlow : .clear, radius: 8, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Generic multi-select chip grid used for diet preferences and allergies.
///
/// `exclusiveOption` (optional) implements the "No preference" / "I'm picky"
/// shortcut: tapping it clears the rest; tapping any other option clears
/// the exclusive choice. Pass `nil` (the default) for a plain multi-select
/// where any subset including empty is valid (e.g. allergies).
struct OnboardingChipSelector<Option: ChipOption>: View {
    let options: [Option]
    @Binding var selected: Set<Option>
    let exclusiveOption: Option?

    init(
        options: [Option],
        selected: Binding<Set<Option>>,
        exclusiveOption: Option? = nil
    ) {
        self.options = options
        self._selected = selected
        self.exclusiveOption = exclusiveOption
    }

    var body: some View {
        let columns = [
            GridItem(.flexible(minimum: 0), spacing: 10),
            GridItem(.flexible(minimum: 0), spacing: 10)
        ]

        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(options) { option in
                let isSelected = selected.contains(option)
                Button {
                    if let exclusive = exclusiveOption, option == exclusive {
                        selected = [exclusive]
                    } else {
                        if let exclusive = exclusiveOption {
                            selected.remove(exclusive)
                        }
                        if isSelected {
                            selected.remove(option)
                        } else {
                            selected.insert(option)
                        }
                    }
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        Text(option.title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? OnboardingGlassTheme.textPrimary : OnboardingGlassTheme.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                        Spacer(minLength: 0)

                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(OnboardingGlassTheme.buttonPrimaryText)
                            .padding(4)
                            .background(Color.white, in: Circle())
                            .opacity(isSelected ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 9)
                    .onboardingGlassPanel(
                        cornerRadius: 12,
                        fillOpacity: isSelected ? 0.24 : 0.04,
                        strokeOpacity: isSelected ? 0.2 : 0.1
                    )
                    .shadow(color: isSelected ? OnboardingGlassTheme.selectionGlow : .clear, radius: 6, y: 2)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.18), value: selected)
    }
}

struct OnboardingPermissionBlock: View {
    let title: String
    let bodyText: String
    let enabled: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OnboardingGlassTheme.textPrimary)
            Text(bodyText)
                .font(.system(size: 15))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)

            HStack(spacing: 10) {
                Button(enabled ? "Connected" : "Connect") {
                    onToggle()
                }
                .buttonStyle(OnboardingGlassPrimaryButtonStyle())

                Button("Not now") {
                    if enabled {
                        onToggle()
                    }
                }
                .buttonStyle(OnboardingGlassSecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .onboardingGlassPanel(cornerRadius: OnboardingGlassMetrics.cornerRadius)
    }
}

struct OnboardingInputField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var suffix: String? = nil
    var keyboardType: UIKeyboardType = .default
    @FocusState private var isFocused: Bool

    var body: some View {
        let isEmphasized = isFocused || !text.isEmpty

        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isEmphasized ? OnboardingGlassTheme.textPrimary : OnboardingGlassTheme.textMuted)

            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)

                if let suffix {
                    Text(suffix)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(isEmphasized ? OnboardingGlassTheme.textPrimary : OnboardingGlassTheme.textMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .onboardingGlassPanel(
                cornerRadius: OnboardingGlassMetrics.innerCornerRadius,
                fillOpacity: isEmphasized ? 0.16 : 0.08,
                strokeOpacity: 0.12
            )
            .shadow(color: isEmphasized ? OnboardingGlassTheme.selectionGlow : .clear, radius: 6, y: 1)
        }
    }
}

struct OnboardingSegmentedControl<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option?
    let label: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)

            HStack(spacing: 6) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    let isSelected = option == selection
                    Button {
                        selection = option
                    } label: {
                        Text(label(option))
                            .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? OnboardingGlassTheme.textPrimary : OnboardingGlassTheme.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? OnboardingGlassTheme.selectedSurface : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .onboardingGlassPanel(cornerRadius: OnboardingGlassMetrics.innerCornerRadius, fillOpacity: 0.06, strokeOpacity: 0.1)
        }
    }
}

private func baselineValueText(_ value: Double, unit: String? = nil, forceOneDecimal: Bool = false) -> String {
    let formatted: String
    if forceOneDecimal {
        formatted = String(format: "%.1f", value)
    } else if abs(value.rounded() - value) < 0.0001 {
        formatted = String(Int(value.rounded()))
    } else {
        formatted = String(format: "%.1f", value)
    }

    if let unit, !unit.isEmpty {
        return "\(formatted) \(unit)"
    }
    return formatted
}

private func baselineScaledFont(_ size: CGFloat) -> CGFloat {
    size * 0.7
}

struct BaselineSliderCard: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let minimumLabel: String
    let maximumLabel: String
    var subtitle: String? = nil
    var onValueChange: ((Double) -> Void)? = nil

    private var titleLabel: some View {
        Text(title.uppercased())
            .font(.system(size: baselineScaledFont(11), weight: .semibold, design: .monospaced))
            .foregroundStyle(OnboardingGlassTheme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var valuePill: some View {
        Text(valueText)
            .font(.system(size: baselineScaledFont(14), weight: .semibold, design: .monospaced))
            .foregroundStyle(OnboardingGlassTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                OnboardingGlassTheme.accentStart.opacity(0.3),
                                OnboardingGlassTheme.accentEnd.opacity(0.3)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    titleLabel
                    Spacer(minLength: 8)
                    valuePill
                }

                VStack(alignment: .leading, spacing: 8) {
                    titleLabel
                    valuePill
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: baselineScaledFont(13), weight: .regular))
                    .foregroundStyle(OnboardingGlassTheme.textMuted)
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in
                        value = newValue
                        onValueChange?(newValue)
                    }
                ),
                in: range,
                step: step
            )
            .tint(OnboardingGlassTheme.accentEnd)

            HStack {
                Text(minimumLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                Text(maximumLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.system(size: baselineScaledFont(11), weight: .medium, design: .monospaced))
            .foregroundStyle(OnboardingGlassTheme.textMuted)
        }
        .padding(14)
        .onboardingGlassPanel(
            cornerRadius: OnboardingGlassMetrics.cornerRadius,
            fillOpacity: 0.08,
            strokeOpacity: 0.14
        )
    }
}

struct BaselineAgeCard: View {
    @Binding var age: Double
    @Binding var isTouched: Bool

    var body: some View {
        BaselineSliderCard(
            title: "Age",
            valueText: baselineValueText(age),
            value: $age,
            range: Double(OnboardingBaselineRange.age.lowerBound) ... Double(OnboardingBaselineRange.age.upperBound),
            step: 1,
            minimumLabel: "\(OnboardingBaselineRange.age.lowerBound)",
            maximumLabel: "\(OnboardingBaselineRange.age.upperBound)"
        ) { _ in
            isTouched = true
        }
    }
}

struct BaselineMetricHeightCard: View {
    @Binding var heightCm: Double
    @Binding var isTouched: Bool

    var body: some View {
        BaselineSliderCard(
            title: "Height",
            valueText: baselineValueText(heightCm, unit: "cm"),
            value: $heightCm,
            range: Double(OnboardingBaselineRange.heightCm.lowerBound) ... Double(OnboardingBaselineRange.heightCm.upperBound),
            step: 1,
            minimumLabel: "\(OnboardingBaselineRange.heightCm.lowerBound) cm",
            maximumLabel: "\(OnboardingBaselineRange.heightCm.upperBound) cm"
        ) { _ in
            isTouched = true
        }
    }
}

struct BaselineImperialHeightCard: View {
    @Binding var feet: Int
    @Binding var inches: Int
    @Binding var isTouched: Bool

    private var maxInchesForSelectedFeet: Int {
        feet >= OnboardingBaselineRange.maxImperialFeet ? OnboardingBaselineRange.maxInchesForMaxFeet : 11
    }

    private var feetBinding: Binding<Double> {
        Binding(
            get: { Double(feet) },
            set: { value in
                feet = Int(value.rounded())
                if feet >= OnboardingBaselineRange.maxImperialFeet {
                    inches = min(inches, OnboardingBaselineRange.maxInchesForMaxFeet)
                }
                isTouched = true
            }
        )
    }

    private var inchesBinding: Binding<Double> {
        Binding(
            get: { Double(inches) },
            set: { value in
                let rounded = Int(value.rounded())
                inches = min(max(rounded, 0), maxInchesForSelectedFeet)
                isTouched = true
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text("HEIGHT".uppercased())
                        .font(.system(size: baselineScaledFont(11), weight: .semibold, design: .monospaced))
                        .foregroundStyle(OnboardingGlassTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    Text("\(feet)′ \(inches)″")
                        .font(.system(size: baselineScaledFont(15), weight: .semibold, design: .monospaced))
                        .foregroundStyle(OnboardingGlassTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            OnboardingGlassTheme.accentStart.opacity(0.3),
                                            OnboardingGlassTheme.accentEnd.opacity(0.3)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("HEIGHT".uppercased())
                        .font(.system(size: baselineScaledFont(11), weight: .semibold, design: .monospaced))
                        .foregroundStyle(OnboardingGlassTheme.textSecondary)
                    Text("\(feet)′ \(inches)″")
                        .font(.system(size: baselineScaledFont(15), weight: .semibold, design: .monospaced))
                        .foregroundStyle(OnboardingGlassTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            OnboardingGlassTheme.accentStart.opacity(0.3),
                                            OnboardingGlassTheme.accentEnd.opacity(0.3)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            BaselineSliderCard(
                title: "Feet",
                valueText: "\(feet)′",
                value: feetBinding,
                range: Double(OnboardingBaselineRange.minImperialFeet) ... Double(OnboardingBaselineRange.maxImperialFeet),
                step: 1,
                minimumLabel: "\(OnboardingBaselineRange.minImperialFeet)′",
                maximumLabel: "\(OnboardingBaselineRange.maxImperialFeet)′"
            ) { _ in
                isTouched = true
            }

            BaselineSliderCard(
                title: "Inches",
                valueText: "\(inches)″",
                value: inchesBinding,
                range: 0 ... Double(maxInchesForSelectedFeet),
                step: 1,
                minimumLabel: "0″",
                maximumLabel: "\(maxInchesForSelectedFeet)″"
            ) { _ in
                isTouched = true
            }
        }
        .padding(14)
        .onboardingGlassPanel(
            cornerRadius: OnboardingGlassMetrics.cornerRadius,
            fillOpacity: 0.08,
            strokeOpacity: 0.14
        )
    }
}

struct BaselineWeightCard: View {
    @Binding var weight: Double
    let units: UnitsOption
    @Binding var isTouched: Bool

    private var range: ClosedRange<Double> {
        switch units {
        case .metric:
            return OnboardingBaselineRange.weightKg
        case .imperial:
            return OnboardingBaselineRange.weightLb
        }
    }

    private var unitLabel: String {
        units == .metric ? "kg" : "lb"
    }

    var body: some View {
        BaselineSliderCard(
            title: "Current weight",
            valueText: baselineValueText(weight, unit: unitLabel, forceOneDecimal: weight.truncatingRemainder(dividingBy: 1) != 0),
            value: $weight,
            range: range,
            step: OnboardingBaselineRange.weightStep,
            minimumLabel: baselineValueText(range.lowerBound, unit: unitLabel),
            maximumLabel: baselineValueText(range.upperBound, unit: unitLabel)
        ) { _ in
            isTouched = true
        }
    }
}
