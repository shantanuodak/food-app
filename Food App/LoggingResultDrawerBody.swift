import SwiftUI
import Foundation

// Drawer palette. Macro inks stay saturated across modes for chart
// alignment (blue protein / orange carbs / red fat), while neutral
// surfaces adapt to dark mode.
private let kDrawerProteinInk = Color(red: 0.000, green: 0.478, blue: 1.000)
private let kDrawerCarbsInk = Color(red: 0.961, green: 0.486, blue: 0.078)
private let kDrawerFatInk = AppColor.macroFat

private let kDrawerBrandOrange = Color(red: 0.902, green: 0.361, blue: 0.102)
private let kDrawerInk = AppColor.textPrimary
private let kDrawerMuted = AppColor.textSecondary
/// Used for small chips (quantity/unit pills) AND larger detected-item
/// cards. Light → pure white. Dark → solid mid-charcoal that lifts off
/// the dark drawer surface (~5% brightness delta over surfaceWarm).
private let kDrawerChipFill = Color(uiColor: UIColor { trait in
    trait.userInterfaceStyle == .dark
        ? UIColor(white: 0.157, alpha: 1.0)
        : UIColor.white
})

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
    let loggedAt: Date
    let mealTag: FoodLogMealTag?
    let onMealTagChange: ((FoodLogMealTag) -> Void)?
    let onLoggedAtChange: ((Date) -> Void)?
    let onItemQuantityChange: ((Int, Double) -> Void)?
    let onRecalculate: (() -> Void)?

    @State private var selectedMealTag: FoodLogMealTag
    @State private var selectedLoggedAt: Date
    @State private var hasManuallySelectedMealTag: Bool

    init(
        foodName: String,
        totals: NutritionTotals,
        items: [ParsedFoodItem],
        thoughtProcess: String,
        mode: LoggingResultDrawerMode = .textDetails,
        showsThoughtProcess: Bool = true,
        loggedAt: Date = Date(),
        mealTag: FoodLogMealTag? = nil,
        onItemQuantityChange: ((Int, Double) -> Void)?,
        onMealTagChange: ((FoodLogMealTag) -> Void)? = nil,
        onLoggedAtChange: ((Date) -> Void)? = nil,
        onRecalculate: (() -> Void)?
    ) {
        self.foodName = foodName
        self.totals = totals
        self.items = items
        self.thoughtProcess = thoughtProcess
        self.mode = mode
        self.showsThoughtProcess = showsThoughtProcess
        self.loggedAt = min(loggedAt, Date())
        self.mealTag = mealTag
        self.onMealTagChange = onMealTagChange
        self.onLoggedAtChange = onLoggedAtChange
        self.onItemQuantityChange = onItemQuantityChange
        self.onRecalculate = onRecalculate

        let clampedLoggedAt = min(loggedAt, Date())
        let initialTag = mealTag ?? FoodLogMealTag.inferred(from: clampedLoggedAt)
        _selectedLoggedAt = State(initialValue: clampedLoggedAt)
        _selectedMealTag = State(initialValue: initialTag)
        _hasManuallySelectedMealTag = State(initialValue: mealTag != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            foodNameView
            calorieHero
            macroStrip
            tagSection
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
        .onChange(of: mealTag) { _, newValue in
            guard let newValue else { return }
            selectedMealTag = newValue
            hasManuallySelectedMealTag = true
        }
        .onChange(of: loggedAt) { _, newValue in
            let clamped = min(newValue, Date())
            selectedLoggedAt = clamped
            guard mealTag == nil, !hasManuallySelectedMealTag else { return }
            selectedMealTag = FoodLogMealTag.inferred(from: clamped)
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
        HStack(alignment: .bottom) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(totals.calories.rounded()))")
                    .font(.system(size: mode == .photoReview ? 42 : 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(kDrawerInk)
                    .monospacedDigit()
                Text("kcal")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(kDrawerMuted)
            }

            Spacer()

            if let bucket = mealTrustBucket {
                TrustBars(bucket: bucket)
                    .padding(.bottom, 7)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Tag + time

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Log details")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(kDrawerMuted)
                .textCase(.uppercase)

            mealTagFlow

            loggedAtCompactControl
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var mealTagFlow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(FoodLogMealTag.allCases) { tag in
                    mealTagButton(tag)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ForEach([FoodLogMealTag.breakfast, .lunch]) { tag in
                        mealTagButton(tag)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    ForEach([FoodLogMealTag.dinner, .snack]) { tag in
                        mealTagButton(tag)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var loggedAtCompactControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(kDrawerBrandOrange)

            Text("Logged at")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(kDrawerMuted)

            Spacer(minLength: 8)

            ZStack(alignment: .trailing) {
                DatePicker(
                    "",
                    selection: $selectedLoggedAt,
                    in: ...Date(),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(kDrawerBrandOrange)
                .opacity(0.01)
                .accessibilityHidden(true)
                .onChange(of: selectedLoggedAt) { _, newValue in
                    let clamped = min(newValue, Date())
                    if clamped != newValue {
                        selectedLoggedAt = clamped
                        return
                    }
                    onLoggedAtChange?(clamped)
                    if !hasManuallySelectedMealTag {
                        let inferredTag = FoodLogMealTag.inferred(from: clamped)
                        selectedMealTag = inferredTag
                        onMealTagChange?(inferredTag)
                    }
                }

                Text(timeFormatter.string(from: selectedLoggedAt))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(kDrawerInk)
                    .monospacedDigit()
                    .allowsHitTesting(false)
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(kDrawerChipFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .accessibilityLabel(Text("Logged at \(timeFormatter.string(from: selectedLoggedAt))"))
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private func mealTagButton(_ tag: FoodLogMealTag) -> some View {
        let isSelected = selectedMealTag == tag
        return Button {
            selectedMealTag = tag
            hasManuallySelectedMealTag = true
            onMealTagChange?(tag)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tag.systemImage)
                    .font(.system(size: 11, weight: .bold))
                Text(tag.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? Color.white : kDrawerInk)
            .frame(minHeight: 36)
            .padding(.horizontal, 8)
            .background(
                isSelected
                    ? kDrawerBrandOrange
                    : kDrawerChipFill,
                in: Capsule(style: .continuous)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? kDrawerBrandOrange.opacity(0.16) : AppColor.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Worst-case confidence across all parsed items — one shaky item
    /// shouldn't get hidden by three confident ones. Filters out
    /// unresolved placeholders (their `matchConfidence` is meaningless
    /// since the row never got parsed) and items with zero/missing
    /// confidence so they don't pull the whole meal down to .lessSure.
    private var mealTrustBucket: TrustBucket? {
        let confidences = items
            .filter { !$0.isUnresolvedPlaceholder }
            .map(\.matchConfidence)
            .filter { $0 > 0 }
        guard let minimum = confidences.min() else { return nil }
        return TrustBucket(confidence: minimum)
    }

    // MARK: - Macro strip — composition first, numbers second

    private var macroStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            MacroCompositionBar(
                protein: totals.protein,
                carbs: totals.carbs,
                fat: totals.fat
            )

            HStack(spacing: 8) {
                macroMetric(
                    value: "\(Int(totals.protein.rounded()))g",
                    label: "Protein",
                    ink: kDrawerProteinInk
                )
                macroMetric(
                    value: "\(Int(totals.carbs.rounded()))g",
                    label: "Carbs",
                    ink: kDrawerCarbsInk
                )
                macroMetric(
                    value: "\(Int(totals.fat.rounded()))g",
                    label: "Fat",
                    ink: kDrawerFatInk
                )
            }
        }
        .padding(13)
        .background(kDrawerChipFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protein \(Int(totals.protein.rounded())) grams, carbs \(Int(totals.carbs.rounded())) grams, fat \(Int(totals.fat.rounded())) grams")
    }

    @ViewBuilder
    private func macroMetric(
        value: String,
        label: String,
        ink: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(ink)
                    .frame(width: 7, height: 7)
                Text(value)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.35)
                .foregroundStyle(kDrawerMuted)
                .textCase(.uppercase)
                .padding(.leading, 13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Detected items

    private var detectedItemsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Items")
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

}

private struct MacroCompositionBar: View {
    let protein: Double
    let carbs: Double
    let fat: Double

    private struct Segment: Identifiable {
        let id: String
        let energy: Double
        let color: Color
    }

    private var segments: [Segment] {
        [
            Segment(id: "protein", energy: max(0, protein) * 4, color: kDrawerProteinInk),
            Segment(id: "carbs", energy: max(0, carbs) * 4, color: kDrawerCarbsInk),
            Segment(id: "fat", energy: max(0, fat) * 9, color: kDrawerFatInk)
        ]
        .filter { $0.energy > 0 }
    }

    private var totalEnergy: Double {
        segments.reduce(0) { $0 + $1.energy }
    }

    var body: some View {
        GeometryReader { proxy in
            if totalEnergy > 0 {
                let gap: CGFloat = 3
                let totalGap = gap * CGFloat(max(segments.count - 1, 0))
                let availableWidth = max(0, proxy.size.width - totalGap)

                HStack(spacing: gap) {
                    ForEach(segments) { segment in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(segment.color)
                            .frame(width: max(3, availableWidth * CGFloat(segment.energy / totalEnergy)))
                    }
                }
                .clipShape(Capsule(style: .continuous))
            } else {
                Capsule(style: .continuous)
                    .fill(kDrawerMuted.opacity(0.14))
            }
        }
        .frame(height: 8)
        .background(kDrawerMuted.opacity(0.12), in: Capsule(style: .continuous))
        .accessibilityHidden(true)
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
                .fill(kDrawerChipFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColor.borderSubtle, lineWidth: 1)
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
                    .fill(kDrawerChipFill)
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
                    .fill(kDrawerChipFill)
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
                .fill(kDrawerChipFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColor.borderSubtle, lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}

// MARK: - Trust signal (signal-strength-style dots)

/// Three-bucket confidence indicator shown on the right side of the
/// calorie hero in the drawer. Avoids the false-precision tax of a
/// numeric confidence score — LLM confidence isn't well-calibrated
/// enough to render a percentage honestly. Three discrete buckets
/// match what the data can actually distinguish.
private enum TrustBucket {
    case confident      // 3 dots
    case approximate    // 2 dots
    case lessSure       // 1 dot

    init(confidence: Double) {
        switch confidence {
        case 0.80...:     self = .confident
        case 0.55..<0.80: self = .approximate
        default:          self = .lessSure
        }
    }

    var label: String {
        switch self {
        case .confident:   return "Confident"
        case .approximate: return "Approximate"
        case .lessSure:    return "Less sure"
        }
    }

    var filledDots: Int {
        switch self {
        case .confident:   return 3
        case .approximate: return 2
        case .lessSure:    return 1
        }
    }
}

/// Three small dots stacked horizontally over a tiny label. Cellular
/// signal-strength metaphor — universally understood "how strong is
/// this thing" without claiming a precise number.
private struct TrustBars: View {
    let bucket: TrustBucket

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < bucket.filledDots ? kDrawerInk : kDrawerInk.opacity(0.18))
                        .frame(width: 5, height: 5)
                }
            }
            Text(bucket.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(kDrawerMuted)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(kDrawerChipFill, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Estimate confidence: \(bucket.label)"))
    }
}
