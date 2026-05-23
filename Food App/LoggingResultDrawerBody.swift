import SwiftUI
import Foundation

// Drawer chip palette (Phase C, 2026-05-22; re-tuned 2026-05-23 to match
// the Apple-Health-style charts the user already has in Insights — blue
// for protein, orange for carbs, red for fat. The earlier violet/green/red
// drawer-only palette diverged from the chart, so totals on the drawer
// didn't visually agree with the histogram below them.
private let kDrawerProteinInk = Color(red: 0.000, green: 0.478, blue: 1.000)
private let kDrawerProteinBg = Color(red: 0.870, green: 0.940, blue: 1.000)
private let kDrawerCarbsInk = Color(red: 0.961, green: 0.486, blue: 0.078)
private let kDrawerCarbsBg = Color(red: 1.000, green: 0.929, blue: 0.871)
private let kDrawerFatInk = Color(red: 0.937, green: 0.267, blue: 0.267)
private let kDrawerFatBg = Color(red: 1.000, green: 0.894, blue: 0.894)

private let kDrawerBrandOrange = Color(red: 0.902, green: 0.361, blue: 0.102)
private let kDrawerInk = Color(red: 0.141, green: 0.098, blue: 0.078)
private let kDrawerMuted = Color(red: 0.467, green: 0.416, blue: 0.380)

enum LoggingResultDrawerMode {
    case textDetails
    case photoReview
}

/// Shared result body used by both the camera drawer (CameraResultDrawerView)
/// and the text-entry drawer (detailsDrawer in MainLoggingShellView).
/// Callers place whatever appears above this (hero image or eyebrow label),
/// and whatever appears below (CTAs or nothing for auto-saved text flow).
struct LoggingResultDrawerBody: View {
    let foodName: String
    let totals: NutritionTotals
    let items: [ParsedFoodItem]
    let thoughtProcess: String
    let mode: LoggingResultDrawerMode
    let showsThoughtProcess: Bool
    let onItemQuantityChange: ((Int, Double) -> Void)?
    let onRecalculate: (() -> Void)?

    init(
        foodName: String,
        totals: NutritionTotals,
        items: [ParsedFoodItem],
        thoughtProcess: String,
        mode: LoggingResultDrawerMode = .textDetails,
        showsThoughtProcess: Bool = true,
        onItemQuantityChange: ((Int, Double) -> Void)?,
        onRecalculate: (() -> Void)?
    ) {
        self.foodName = foodName
        self.totals = totals
        self.items = items
        self.thoughtProcess = thoughtProcess
        self.mode = mode
        self.showsThoughtProcess = showsThoughtProcess
        self.onItemQuantityChange = onItemQuantityChange
        self.onRecalculate = onRecalculate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mode == .photoReview {
                photoSummaryLabel
            }
            foodNameView
            calorieHero
            macroCards
            if !items.isEmpty {
                detectedItemsList
            }
            if showsThoughtProcess {
                LoggingResultThoughtProcessCard(thoughtProcess: thoughtProcess)
            }
            if let onRecalculate {
                Button(action: onRecalculate) {
                    Text("Something wrong? Recalculate")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(kDrawerBrandOrange)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            }
        }
    }

    // MARK: - Food name — Title 2

    private var foodNameView: some View {
        Text(foodName)
            .font(.system(size: mode == .photoReview ? 20 : 22, weight: .bold, design: .rounded))
            .foregroundStyle(kDrawerInk)
            .lineLimit(2)
            .padding(.horizontal, 20)
            .padding(.top, mode == .photoReview ? 4 : 12)
    }

    // MARK: - Calorie hero — Large Title

    private var calorieHero: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(totals.calories.rounded()))")
                    .font(.system(size: mode == .photoReview ? 42 : 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(kDrawerInk)
                    .monospacedDigit()
                Text("kcal")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(kDrawerMuted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Macro chips — three categories, distinct palette

    private var macroCards: some View {
        HStack(spacing: 8) {
            macroChip(
                value: "\(Int(totals.protein.rounded()))g",
                label: "Protein",
                ink: kDrawerProteinInk,
                bg: kDrawerProteinBg
            )
            macroChip(
                value: "\(Int(totals.carbs.rounded()))g",
                label: "Carbs",
                ink: kDrawerCarbsInk,
                bg: kDrawerCarbsBg
            )
            macroChip(
                value: "\(Int(totals.fat.rounded()))g",
                label: "Fat",
                ink: kDrawerFatInk,
                bg: kDrawerFatBg
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    @ViewBuilder
    private func macroChip(
        value: String,
        label: String,
        ink: Color,
        bg: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(ink.opacity(0.78))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minHeight: 72)
        .background(bg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ink.opacity(0.10), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    // MARK: - Detected items

    private var detectedItemsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Detected items")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(kDrawerMuted)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 10)

            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                DrawerItemRow(
                    item: item,
                    itemOffset: idx,
                    onQuantityChange: onItemQuantityChange
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
        }
    }

    private var photoSummaryLabel: some View {
        Text(items.count == 1 ? "Detected from photo" : "\(items.count) items detected from photo")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(kDrawerBrandOrange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(kDrawerBrandOrange.opacity(0.10), in: Capsule())
            .padding(.horizontal, 20)
            .padding(.top, 18)
    }
}

// MARK: - Per-item row with native quantity + unit pickers (Items 11 & 12)

private struct DrawerItemRow: View {
    let item: ParsedFoodItem
    let itemOffset: Int
    let onQuantityChange: ((Int, Double) -> Void)?

    @State private var expandedPicker: ExpandedPicker = .none
    @State private var customQuantityText: String = ""
    @State private var isCustomQuantitySheetPresented = false
    /// Local override for the user-selected unit. Persistence to the backend
    /// is a separate workstream; this keeps the display + macro recalc
    /// reactive while we wait for that.
    @State private var localUnitOverride: ServingUnitOption?

    private enum ExpandedPicker {
        case none
        case quantity
        case unit
    }

    private var currentQuantity: Double {
        item.amount ?? item.quantity
    }

    private var currentUnit: ServingUnitOption {
        localUnitOverride ?? ServingUnitOption.bestMatch(for: item.unitNormalized ?? item.unit)
    }

    private var isAtSuggestedDefaults: Bool {
        localUnitOverride == nil &&
            abs(currentQuantity - (item.amount ?? item.quantity)) < 0.001
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(kDrawerInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        quantityChip
                        unitChip
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(item.calories.rounded())) kcal")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(kDrawerInk)
                        .monospacedDigit()

                    Text("P \(macroLabel(item.protein)) · C \(macroLabel(item.carbs)) · F \(macroLabel(item.fat))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(kDrawerMuted)
                        .multilineTextAlignment(.trailing)
                }
            }

            if isAtSuggestedDefaults {
                Text("Suggested")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(kDrawerBrandOrange.opacity(0.86))
                    .textCase(.uppercase)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(kDrawerBrandOrange.opacity(0.08), in: Capsule())
            }

            switch expandedPicker {
            case .none:
                EmptyView()
            case .quantity:
                quantityPickerWheel
            case .unit:
                unitPickerWheel
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(red: 0.278, green: 0.176, blue: 0.098).opacity(0.10), lineWidth: 1)
                )
        )
        .animation(.spring(response: 0.30, dampingFraction: 0.84), value: expandedPicker)
        .sheet(isPresented: $isCustomQuantitySheetPresented) {
            CustomQuantityInputSheet(
                initialValue: currentQuantity,
                onCommit: { value in
                    onQuantityChange?(itemOffset, value)
                    isCustomQuantitySheetPresented = false
                },
                onCancel: { isCustomQuantitySheetPresented = false }
            )
        }
    }

    private var quantityChip: some View {
        Button {
            // Close the unit picker if it's open, then toggle quantity.
            if expandedPicker == .quantity {
                expandedPicker = .none
            } else {
                expandedPicker = .quantity
            }
        } label: {
            HStack(spacing: 4) {
                Text(quantityChipLabel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(expandedPicker == .quantity ? 180 : 0))
            }
            .foregroundStyle(kDrawerInk)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(.white)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(kDrawerBrandOrange.opacity(0.32), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Quantity \(quantityChipLabel). Tap to change."))
    }

    private var unitChip: some View {
        Button {
            if expandedPicker == .unit {
                expandedPicker = .none
            } else {
                expandedPicker = .unit
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentUnit.displayName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(expandedPicker == .unit ? 180 : 0))
            }
            .foregroundStyle(kDrawerInk)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(.white)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(kDrawerBrandOrange.opacity(0.32), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Serving type \(currentUnit.displayName). Tap to change."))
    }

    private var quantityPickerWheel: some View {
        VStack(spacing: 8) {
            Picker("Quantity", selection: quantityBinding) {
                ForEach(ServingQuantityOption.options, id: \.value) { option in
                    Text(option.displayName).tag(option.value)
                }
                Text("Custom…").tag(-1.0)
            }
            .pickerStyle(.wheel)
            .frame(height: 128)
            .clipped()
        }
        .padding(.top, 4)
    }

    private var unitPickerWheel: some View {
        Picker("Serving type", selection: unitBinding) {
            ForEach(ServingUnitOption.allCases, id: \.self) { option in
                Text(option.displayName).tag(option)
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 128)
        .clipped()
        .padding(.top, 4)
    }

    private var quantityBinding: Binding<Double> {
        Binding(
            get: { currentQuantity },
            set: { newValue in
                if newValue < 0 {
                    isCustomQuantitySheetPresented = true
                    expandedPicker = .none
                } else {
                    onQuantityChange?(itemOffset, newValue)
                }
            }
        )
    }

    private var unitBinding: Binding<ServingUnitOption> {
        Binding(
            get: { currentUnit },
            set: { newValue in
                localUnitOverride = newValue
            }
        )
    }

    private var quantityChipLabel: String {
        let q = currentQuantity
        if let match = ServingQuantityOption.options.first(where: { abs($0.value - q) < 0.001 }) {
            return match.displayName
        }
        if abs(q.rounded() - q) < 0.001 {
            return "\(Int(q.rounded()))"
        }
        return String(format: "%.2f", q).trimmingTrailingZeros()
    }

    private func macroLabel(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return "\(Int(value.rounded()))g"
        }
        return String(format: "%.1fg", value)
    }
}

// MARK: - Serving option models (Items 11 & 12 backing data)

struct ServingQuantityOption {
    let value: Double
    let displayName: String

    /// Curated curated wheel set: covers fractions users commonly need plus
    /// whole numbers. "Custom…" is added as a sentinel option in the picker
    /// at value = -1.
    static let options: [ServingQuantityOption] = [
        ServingQuantityOption(value: 0.25, displayName: "1/4"),
        ServingQuantityOption(value: 1.0 / 3.0, displayName: "1/3"),
        ServingQuantityOption(value: 0.5, displayName: "1/2"),
        ServingQuantityOption(value: 0.75, displayName: "3/4"),
        ServingQuantityOption(value: 1.0, displayName: "1"),
        ServingQuantityOption(value: 1.25, displayName: "1.25"),
        ServingQuantityOption(value: 1.5, displayName: "1.5"),
        ServingQuantityOption(value: 2.0, displayName: "2"),
        ServingQuantityOption(value: 2.5, displayName: "2.5"),
        ServingQuantityOption(value: 3.0, displayName: "3"),
        ServingQuantityOption(value: 4.0, displayName: "4"),
        ServingQuantityOption(value: 5.0, displayName: "5")
    ]
}

enum ServingUnitOption: String, CaseIterable {
    case cup
    case glass
    case bowl
    case slice
    case piece
    case half
    case whole
    case tablespoon
    case teaspoon
    case ounce
    case fluidOunce
    case gram
    case milliliter
    case scoop
    case can
    case bottle
    case packet
    case serving

    var displayName: String {
        switch self {
        case .cup: return "cup"
        case .glass: return "glass"
        case .bowl: return "bowl"
        case .slice: return "slice"
        case .piece: return "piece"
        case .half: return "half"
        case .whole: return "whole"
        case .tablespoon: return "tbsp"
        case .teaspoon: return "tsp"
        case .ounce: return "oz"
        case .fluidOunce: return "fl oz"
        case .gram: return "g"
        case .milliliter: return "ml"
        case .scoop: return "scoop"
        case .can: return "can"
        case .bottle: return "bottle"
        case .packet: return "packet"
        case .serving: return "serving"
        }
    }

    /// Map a raw unit string from the parser (which can be anything — "Cup",
    /// "cups", "cup(s)", etc.) to the canonical option. Defaults to
    /// `.serving` when no obvious match exists, which keeps the picker
    /// rendering a valid selection rather than going blank.
    static func bestMatch(for raw: String) -> ServingUnitOption {
        let normalized = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for option in ServingUnitOption.allCases {
            if normalized.hasPrefix(option.displayName.lowercased()) {
                return option
            }
        }
        // Common aliases.
        if normalized.contains("tablespoon") || normalized == "tbs" { return .tablespoon }
        if normalized.contains("teaspoon") { return .teaspoon }
        if normalized.contains("ounce") { return .ounce }
        if normalized.contains("gram") { return .gram }
        return .serving
    }
}

// MARK: - Custom quantity keypad sheet

private struct CustomQuantityInputSheet: View {
    let initialValue: Double
    let onCommit: (Double) -> Void
    let onCancel: () -> Void

    @State private var input: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Custom serving")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .padding(.top, 36)

            Text(input.isEmpty ? "0" : input)
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(kDrawerInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal, 28)

            // Number pad — 4 rows × 3 columns
            VStack(spacing: 10) {
                ForEach(0..<4) { row in
                    HStack(spacing: 10) {
                        ForEach(0..<3) { col in
                            keypadButton(for: keypadLabel(row: row, col: col))
                        }
                    }
                }
            }
            .padding(.horizontal, 28)

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(kDrawerMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(kDrawerMuted.opacity(0.24), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    if let parsed = Double(input), parsed > 0 {
                        onCommit(parsed)
                    } else {
                        onCancel()
                    }
                } label: {
                    Text("Use this")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(kDrawerBrandOrange, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(Double(input) == nil || (Double(input) ?? 0) <= 0)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
        .onAppear {
            input = formatInitialValue(initialValue)
        }
    }

    private func keypadLabel(row: Int, col: Int) -> String {
        let layout = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            [".", "0", "⌫"]
        ]
        return layout[row][col]
    }

    private func keypadButton(for label: String) -> some View {
        Button {
            switch label {
            case "⌫":
                if !input.isEmpty { input.removeLast() }
            case ".":
                if !input.contains(".") {
                    input += input.isEmpty ? "0." : "."
                }
            default:
                // Cap input length to 5 chars (e.g. "99.99") to keep things sane.
                if input.count < 5 {
                    input += label
                }
            }
        } label: {
            Text(label)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(kDrawerInk)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func formatInitialValue(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.2f", value).trimmingTrailingZeros()
    }
}

private extension String {
    func trimmingTrailingZeros() -> String {
        if contains(".") {
            return trimmingCharacters(in: CharacterSet(charactersIn: "0"))
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .nilIfEmpty ?? "0"
        }
        return self
    }

    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Thought process card

struct LoggingResultThoughtProcessCard: View {
    let thoughtProcess: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How Food App Estimated This")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(kDrawerInk)
            Text(thoughtProcess)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(kDrawerMuted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(red: 0.278, green: 0.176, blue: 0.098).opacity(0.10), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}
