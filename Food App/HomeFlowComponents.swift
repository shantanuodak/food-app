import SwiftUI
import UIKit

/// Purple-pink gradient used for AI-related shimmer and loading effects.
private let aiShimmerGradient = LinearGradient(
    colors: [
        Color(red: 0.58, green: 0.29, blue: 0.98),  // purple
        Color(red: 0.91, green: 0.30, blue: 0.60),  // pink
        Color(red: 0.58, green: 0.29, blue: 0.98)   // purple (bookend)
    ],
    startPoint: .leading,
    endPoint: .trailing
)

enum HomeInputMode: String, Hashable {
    case text
    case voice
    case camera
    case manualAdd

    var title: String {
        switch self {
        case .text: return "Text"
        case .voice: return "Voice"
        case .camera: return "Camera"
        case .manualAdd: return "Manual Add"
        }
    }

    var icon: String {
        switch self {
        case .text: return "character.cursor.ibeam"
        case .voice: return "mic.fill"
        case .camera: return "camera.fill"
        case .manualAdd: return "plus.circle.fill"
        }
    }
}

enum LoadingRouteHint: String, Hashable {
    case foodDatabase
    case ai
    case unknown
}

enum RowParsePhase: Equatable {
    case idle
    case active(routeHint: LoadingRouteHint, startedAt: Date)
    case queued
    case failed
    case unresolved
}

struct HomeLogRow: Identifiable, Equatable {
    let id: UUID
    var text: String
    var calories: Int?
    var calorieRangeText: String?
    var isApproximate: Bool
    var parsePhase: RowParsePhase
    var parsedItem: ParsedFoodItem?
    var parsedItems: [ParsedFoodItem]
    var editableItemIndices: [Int]
    var normalizedTextAtParse: String?
    var imagePreviewData: Data?
    var imageRef: String?
    /// True for rows that have already been saved to the backend.
    /// Saved rows are read-only and appear above the active input (Apple Notes style).
    var isSaved: Bool
    /// Pre-formatted time string shown below a saved row (e.g. "7:48 AM").
    var savedAt: String?
    /// Triggers a one-time shimmer animation when the row is inserted via voice.
    var showInsertShimmer: Bool = false
    /// Triggers a one-time purple shimmer on the calorie label when it first appears.
    var showCalorieRevealShimmer: Bool = false
    /// Triggers a brief shimmer sweep on the calorie pill when the calorie
    /// value is updated in place (e.g. the user changed "1 chicken tender" to
    /// "2" and the client-side math rescaled the macros). Distinct from the
    /// reveal shimmer: faster, purely confirmatory, fires on *every* update.
    var showCalorieUpdateShimmer: Bool = false
    /// Server-side `food_logs.id` for rows that were loaded from the backend.
    /// Used to branch the save path between POST (new) and PATCH (edit) so
    /// editing a saved row doesn't create a duplicate entry.
    var serverLogId: String? = nil
    /// ISO-8601 `logged_at` stamp for server-backed rows. Preserved across
    /// un-save → edit → PATCH so cache invalidation targets the correct day
    /// (not the day the user happens to be viewing now).
    var serverLoggedAt: String? = nil
    /// Optimistic delete marker used to avoid refocusing a row while it is being
    /// removed from the backend.
    var isDeleting: Bool = false

    static func empty() -> HomeLogRow {
        HomeLogRow(
            id: UUID(),
            text: "",
            calories: nil,
            calorieRangeText: nil,
            isApproximate: false,
            parsePhase: .idle,
            parsedItem: nil,
            parsedItems: [],
            editableItemIndices: [],
            normalizedTextAtParse: nil,
            imagePreviewData: nil,
            imageRef: nil,
            isSaved: false,
            savedAt: nil,
            serverLogId: nil
        )
    }

    var isLoading: Bool {
        if case .active = parsePhase {
            return true
        }
        return false
    }

    var isQueued: Bool {
        if case .queued = parsePhase {
            return true
        }
        return false
    }

    var isFailed: Bool {
        if case .failed = parsePhase {
            return true
        }
        return false
    }

    var isUnresolved: Bool {
        if case .unresolved = parsePhase {
            return true
        }
        return false
    }

    /// True when the row's parsed items contain ≥1 backend-emitted
    /// unresolved placeholder. Distinct from `isUnresolved` (whole-row
    /// failure) — this signals a *partial* failure where some segments
    /// parsed and some didn't. Drives the red exclamation badge next to
    /// the calorie value and the per-item Retry buttons in the drawer.
    var hasUnresolvedItems: Bool {
        parsedItems.contains(where: { $0.isUnresolvedPlaceholder })
    }

    var unresolvedItemCount: Int {
        parsedItems.filter { $0.isUnresolvedPlaceholder }.count
    }

    var loadingRouteHint: LoadingRouteHint? {
        if case let .active(routeHint, _) = parsePhase {
            return routeHint
        }
        return nil
    }

    var loadingStatusStartedAt: Date? {
        if case let .active(_, startedAt) = parsePhase {
            return startedAt
        }
        return nil
    }

    mutating func setParseActive(routeHint: LoadingRouteHint, startedAt: Date = Date()) {
        parsePhase = .active(routeHint: routeHint, startedAt: startedAt)
    }

    mutating func setParseQueued() {
        parsePhase = .queued
    }

    mutating func clearParsePhase() {
        parsePhase = .idle
    }

    mutating func setParseFailed() {
        parsePhase = .failed
    }

    mutating func setParseUnresolved() {
        parsePhase = .unresolved
    }

    static func predictedLoadingRouteHint(for rawText: String) -> LoadingRouteHint {
        let normalized = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return .unknown }

        let tokens = normalized
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let tokenCount = tokens.count

        let hasConnectorWord = normalized.contains(" and ") || normalized.contains(" with ")
        let hasComplexSeparator = normalized.contains(",") || normalized.contains("/") || normalized.contains("+") || normalized.contains("&")
        if hasConnectorWord || hasComplexSeparator || tokenCount > 4 {
            return .ai
        }

        let hasLeadingQuantity = normalized.range(of: #"^\d+(?:[./]\d+)?"#, options: .regularExpression) != nil
        let unitKeywords: Set<String> = [
            "cup", "cups", "tbsp", "tsp", "oz", "ounce", "ounces", "g", "gram", "grams",
            "kg", "ml", "l", "slice", "slices", "piece", "pieces", "serving", "servings",
            "bottle", "bottles", "can", "cans", "bar", "bars"
        ]
        let hasUnitKeyword = tokens.contains { unitKeywords.contains($0) }
        if hasLeadingQuantity || hasUnitKeyword || tokenCount <= 3 {
            return .foodDatabase
        }

        return .unknown
    }
}

// MARK: - Quantity-only edit detection (fast path)

/// Result of a quantity-only detection: how much the quantity changed.
struct QuantityOnlyEdit {
    let oldQty: Double
    let newQty: Double
    var multiplier: Double { newQty / oldQty }
}

/// Pulls a leading numeric quantity out of raw row text. Supports integers,
/// decimals, and simple fractions ("1/2", "3/4"). Returns the remainder
/// (everything after the number, normalized) so it can be compared across
/// edits — if the remainder is identical, only the quantity changed.
///
/// Deliberately conservative: rejects ambiguous leading numbers like "2%"
/// (fat percentage) by requiring whitespace between the number and the
/// remainder.
func extractLeadingQuantity(from rawText: String) -> (value: Double, remainder: String)? {
    let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    // Leading integer / decimal / simple fraction, followed by whitespace,
    // followed by the rest.
    let pattern = #"^(\d+(?:\.\d+)?|\d+/\d+)\s+(.+)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(
              in: trimmed,
              range: NSRange(trimmed.startIndex..., in: trimmed)
          ),
          match.numberOfRanges >= 3,
          let numberRange = Range(match.range(at: 1), in: trimmed),
          let restRange = Range(match.range(at: 2), in: trimmed) else {
        return nil
    }

    let numberStr = String(trimmed[numberRange])
    let rest = String(trimmed[restRange])
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    let value: Double
    if numberStr.contains("/") {
        let parts = numberStr.split(separator: "/")
        guard parts.count == 2,
              let num = Double(parts[0]),
              let den = Double(parts[1]),
              den > 0 else { return nil }
        value = num / den
    } else {
        guard let parsed = Double(numberStr) else { return nil }
        value = parsed
    }

    guard value > 0, !rest.isEmpty else { return nil }
    return (value: value, remainder: rest)
}

/// Returns a `QuantityOnlyEdit` if the only difference between `oldText` and
/// `newText` is the leading quantity — same food words in the same order,
/// different number. Returns nil for any other kind of edit (adding a unit,
/// changing the food name, removing the quantity entirely, etc.) so the
/// caller can fall back to a full re-parse.
func detectQuantityOnlyEdit(oldText: String, newText: String) -> QuantityOnlyEdit? {
    guard let old = extractLeadingQuantity(from: oldText),
          let new = extractLeadingQuantity(from: newText),
          old.remainder == new.remainder,
          old.value != new.value else {
        return nil
    }
    return QuantityOnlyEdit(oldQty: old.value, newQty: new.value)
}

/// Rescale a `ParsedFoodItem` by a numeric multiplier. Nutrition-related
/// fields (grams, calories, macros, amount, quantity) scale linearly; all
/// other fields (name, unit, source, match confidence, serving options) are
/// preserved verbatim.
func scaleParsedFoodItem(_ item: ParsedFoodItem, by multiplier: Double) -> ParsedFoodItem {
    ParsedFoodItem(
        name: item.name,
        quantity: item.quantity * multiplier,
        unit: item.unit,
        grams: item.grams * multiplier,
        calories: item.calories * multiplier,
        protein: item.protein * multiplier,
        carbs: item.carbs * multiplier,
        fat: item.fat * multiplier,
        nutritionSourceId: item.nutritionSourceId,
        originalNutritionSourceId: item.originalNutritionSourceId,
        sourceFamily: item.sourceFamily,
        matchConfidence: item.matchConfidence,
        amount: (item.amount ?? item.quantity) * multiplier,
        unitNormalized: item.unitNormalized,
        gramsPerUnit: item.gramsPerUnit,  // per-unit values don't scale
        needsClarification: item.needsClarification,
        manualOverride: item.manualOverride,
        servingOptions: item.servingOptions,
        foodDescription: item.foodDescription,
        explanation: item.explanation
    )
}

/// Lowercased, whitespace-collapsed text used for parse-ownership comparison.
/// Duplicated here so the composer binding can normalize without importing
/// the view model; kept in sync with `MainLoggingShellView.normalizedRowText`.
func normalizedRowTextForComposer(_ text: String) -> String {
    text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

struct RollingNumberText: View {
    let value: Double
    var fractionDigits: Int = 0
    var suffix: String = ""
    var useGrouping: Bool = false

    var body: some View {
        Text(formattedValue)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.25), value: formattedValue)
    }

    private var formattedValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = useGrouping
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let base = formatter.string(from: NSNumber(value: value)) ?? "0"
        return suffix.isEmpty ? base : "\(base)\(suffix)"
    }
}

struct HM01LogComposerSection: View {
    @Binding var rows: [HomeLogRow]
    let focusBinding: FocusState<Bool>.Binding
    let mode: HomeInputMode
    let inlineEstimateText: String?
    let hasActiveParseRequest: Bool
    let minimalStyle: Bool
    let onInputTapped: () -> Void
    let onCaloriesTapped: (HomeLogRow) -> Void
    let onFocusedRowChanged: (UUID?) -> Void
    let onServerBackedRowCleared: (HomeLogRow) -> Void
    /// Fires after the client-side quantity fast path rescales a row's items
    /// (e.g. "3 chicken tenders" → "4 chicken tenders"). The parent view uses
    /// this to schedule persistence: PATCH for rows that already have a
    /// `serverLogId`, or to kick the regular auto-save for newly-composed
    /// rows.
    let onQuantityFastPathUpdated: (UUID) -> Void
    @State private var focusedMinimalRowID: UUID?

    init(
        rows: Binding<[HomeLogRow]>,
        focusBinding: FocusState<Bool>.Binding,
        mode: HomeInputMode,
        inlineEstimateText: String?,
        hasActiveParseRequest: Bool = false,
        minimalStyle: Bool = false,
        onInputTapped: @escaping () -> Void,
        onCaloriesTapped: @escaping (HomeLogRow) -> Void = { _ in },
        onFocusedRowChanged: @escaping (UUID?) -> Void = { _ in },
        onServerBackedRowCleared: @escaping (HomeLogRow) -> Void = { _ in },
        onQuantityFastPathUpdated: @escaping (UUID) -> Void = { _ in }
    ) {
        _rows = rows
        self.focusBinding = focusBinding
        self.mode = mode
        self.inlineEstimateText = inlineEstimateText
        self.hasActiveParseRequest = hasActiveParseRequest
        self.minimalStyle = minimalStyle
        self.onInputTapped = onInputTapped
        self.onCaloriesTapped = onCaloriesTapped
        self.onFocusedRowChanged = onFocusedRowChanged
        self.onServerBackedRowCleared = onServerBackedRowCleared
        self.onQuantityFastPathUpdated = onQuantityFastPathUpdated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !minimalStyle {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(L10n.foodInputPrompt)
                        .font(.headline)

                    Spacer()

                    if let inlineEstimateText {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                            Text(inlineEstimateText)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            if mode != .text && !minimalStyle {
                Text("Mode: \(mode.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if minimalStyle {
                let firstActiveRowID = rows.first(where: { !$0.isSaved })?.id
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 12) {
                            if row.isSaved {
                                Button {
                                    guard !row.isDeleting else { return }
                                    if let index = indexForRowID(row.id) {
                                        rows[index].isSaved = false
                                        rows[index].savedAt = nil
                                        onInputTapped()
                                        setFocusedMinimalRowID(row.id)
                                    }
                                } label: {
                                    Text(row.text)
                                        .font(.system(size: 18))
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .disabled(row.isDeleting)
                                .modifier(InsertShimmerModifier(isActive: row.showInsertShimmer, onComplete: {
                                    if let index = indexForRowID(row.id) {
                                        rows[index].showInsertShimmer = false
                                    }
                                }))
                            } else {
                                let isFirst = row.id == firstActiveRowID
                                let placeholder = isFirst ? "Type your food here" : "Add another item"

                                MinimalRowTextEditor(
                                    text: bindingForRowText(row.id),
                                    isFocused: focusedMinimalRowID == row.id,
                                    onFocusChanged: { isFocused in
                                        DispatchQueue.main.async {
                                            guard indexForRowID(row.id) != nil else { return }
                                            if isFocused {
                                                onInputTapped()
                                                setFocusedMinimalRowID(row.id)
                                            } else if focusedMinimalRowID == row.id {
                                                setFocusedMinimalRowID(nil)
                                            }
                                        }
                                    },
                                    onSubmit: {
                                        addMinimalRow(after: row.id)
                                    },
                                    onDeleteBackwardWhenEmpty: {
                                        deleteCurrentEmptyRowAndFocusPrevious(rowID: row.id)
                                    },
                                    placeholder: placeholder,
                                    showTypewriterPlaceholder: isFirst
                                )
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                                .accessibilityLabel(Text(L10n.foodInputPrompt))
                                .accessibilityHint(Text(L10n.foodInputHint))
                            }

                            trailingCaloriesView(for: row)
                                .frame(width: 150, alignment: .trailing)
                        }
                        .opacity(row.isDeleting ? 0.35 : 1)
                        .animation(.easeOut(duration: 0.12), value: row.isDeleting)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextEditor(text: rowTextBinding)
                    .focused(focusBinding)
                    .scrollDisabled(true)
                    .frame(minHeight: 160)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .accessibilityLabel(Text(L10n.foodInputPrompt))
                    .accessibilityHint(Text(L10n.foodInputHint))
                    .onTapGesture {
                        onInputTapped()
                        focusBinding.wrappedValue = true
                    }
            }
            if !minimalStyle {
                HStack(spacing: 0) {
                    RollingNumberText(
                        value: Double(joinedRowText.trimmingCharacters(in: .whitespacesAndNewlines).count),
                        fractionDigits: 0
                    )
                    Text("/500")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissKeyboardFromTabBar)) { _ in
            focusedMinimalRowID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusComposerInputFromBackgroundTap)) { _ in
            focusLastEditableRow()
        }
    }

    private var joinedRowText: String {
        rows.map(\.text).joined(separator: "\n")
    }

    private var rowTextBinding: Binding<String> {
        Binding(
            get: { joinedRowText },
            set: { newValue in
                rows = textToRows(newValue)
            }
        )
    }

    private func textToRows(_ value: String) -> [HomeLogRow] {
        let parts = value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let normalized = parts.isEmpty ? [""] : parts
        return normalized.map { part in
            HomeLogRow(
                id: UUID(),
                text: part,
                calories: nil,
                calorieRangeText: nil,
                isApproximate: false,
                parsePhase: .idle,
                parsedItem: nil,
                parsedItems: [],
                editableItemIndices: [],
                normalizedTextAtParse: nil,
                imagePreviewData: nil,
                imageRef: nil,
                isSaved: false,
                savedAt: nil
            )
        }
    }

    private func bindingForRowText(_ rowID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let index = indexForRowID(rowID), rows.indices.contains(index) else {
                    return ""
                }
                return rows[index].text
            },
            set: { newValue in
                guard let index = indexForRowID(rowID), rows.indices.contains(index) else {
                    return
                }
                guard rows[index].text != newValue else { return }

                let oldRow = rows[index]
                let oldText = oldRow.text
                let wasEmpty = oldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                rows[index].text = newValue
                let isEmpty = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                if isEmpty && !wasEmpty && oldRow.serverLogId != nil {
                    onServerBackedRowCleared(oldRow)
                    return
                }

                if isEmpty && !wasEmpty {
                    // Text just became empty — clear all parse state
                    rows[index].calories = nil
                    rows[index].calorieRangeText = nil
                    rows[index].isApproximate = false
                    rows[index].clearParsePhase()
                    rows[index].parsedItem = nil
                    rows[index].parsedItems = []
                    rows[index].editableItemIndices = []
                    rows[index].normalizedTextAtParse = nil
                    rows[index].imagePreviewData = nil
                    rows[index].imageRef = nil
                    return
                }

                // --- Quantity-only fast path ---------------------------------
                // If the row already has parsed items and the only change is
                // the leading quantity (e.g. "3 chicken tenders" → "4 chicken
                // tenders"), rescale calories/macros locally instead of
                // triggering a backend re-parse. Also updates
                // `normalizedTextAtParse` so `rowNeedsFreshParse()` returns
                // false for the new text, preventing the debounced parser
                // from undoing our work.
                if !isEmpty,
                   !wasEmpty,
                   !rows[index].parsedItems.isEmpty,
                   !rows[index].isLoading,
                   let edit = detectQuantityOnlyEdit(oldText: oldText, newText: newValue) {
                    let scaled = rows[index].parsedItems.map {
                        scaleParsedFoodItem($0, by: edit.multiplier)
                    }
                    rows[index].parsedItems = scaled
                    rows[index].parsedItem = scaled.first
                    if let existing = rows[index].calories {
                        let newCalories = Double(existing) * edit.multiplier
                        rows[index].calories = Int(newCalories.rounded())
                    } else if !scaled.isEmpty {
                        rows[index].calories = Int(
                            scaled.reduce(0.0) { $0 + $1.calories }.rounded()
                        )
                    }
                    // Mark as fresh against the new text so the debounced
                    // parser skips this row — we already have the right values.
                    rows[index].normalizedTextAtParse = normalizedRowTextForComposer(newValue)
                    // Kick the confirmation shimmer. The modifier clears this
                    // flag automatically when the animation finishes.
                    rows[index].showCalorieUpdateShimmer = true
                    // Notify the parent so it can schedule persistence (PATCH
                    // for saved rows, or let auto-save pick it up for new rows).
                    onQuantityFastPathUpdated(rowID)
                }
                // NOTE: Do NOT set parsePhase here. Creating a new Date() on every
                // keystroke forces SwiftUI to re-diff the row each character, causing
                // severe typing lag. The debounce timer in scheduleDebouncedParse
                // handles parse ownership via synchronizeParseOwnership() after the
                // user pauses typing.
            }
        )
    }

    private func indexForRowID(_ rowID: UUID) -> Int? {
        rows.firstIndex(where: { $0.id == rowID })
    }

    private func addMinimalRow(after rowID: UUID) {
        guard let index = indexForRowID(rowID) else { return }
        if index == rows.count - 1 {
            rows.append(.empty())
        }
        let nextIndex = min(index + 1, max(rows.count - 1, 0))
        setFocusedMinimalRowID(rows[nextIndex].id)
    }

    private func deleteCurrentEmptyRowAndFocusPrevious(rowID: UUID) {
        guard rows.count > 1 else { return }
        guard let index = indexForRowID(rowID), rows.indices.contains(index) else { return }
        let trimmed = rows[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return }

        rows.remove(at: index)
        if rows.isEmpty {
            rows = [.empty()]
        }

        let targetIndex = min(max(index - 1, 0), rows.count - 1)
        let targetRowID = rows[targetIndex].id
        DispatchQueue.main.async {
            setFocusedMinimalRowID(targetRowID)
        }
    }

    private func setFocusedMinimalRowID(_ rowID: UUID?) {
        guard focusedMinimalRowID != rowID else { return }
        focusedMinimalRowID = rowID
        onFocusedRowChanged(rowID)
    }

    private func focusLastEditableRow() {
        onInputTapped()

        if minimalStyle {
            if rows.allSatisfy(\.isSaved) {
                rows.append(.empty())
            }

            guard let targetRowID = rows.last(where: { !$0.isSaved && !$0.isDeleting })?.id else { return }
            setFocusedMinimalRowID(targetRowID)
            return
        }

        focusBinding.wrappedValue = true
    }

    @ViewBuilder
    private func trailingCaloriesView(for row: HomeLogRow) -> some View {
        let showCalories = !row.isLoading && !row.isQueued && !row.isUnresolved && !row.isFailed && row.calories != nil

        ZStack(alignment: .trailing) {
            if row.isLoading {
                RowThoughtProcessStatusView(
                    routeHint: row.loadingRouteHint ?? .unknown,
                    startedAt: row.loadingStatusStartedAt
                )
                .transition(.opacity)
            }

            QueuedRowStatusView()
                .opacity(row.isQueued ? 1 : 0)

            UnresolvedRowStatusView()
                .opacity(row.isUnresolved ? 1 : 0)

            FailedRowStatusView()
                .opacity(row.isFailed ? 1 : 0)

            if let calories = row.calories {
                Button {
                    onCaloriesTapped(row)
                } label: {
                    HStack(spacing: 6) {
                        // Red exclamation badge when one or more parsed items
                        // are placeholders. Tap routes to the same drawer as
                        // the calorie label, where the user can retry the
                        // unresolved segments.
                        if showCalories && row.hasUnresolvedItems {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.red)
                                .accessibilityLabel(
                                    Text("\(row.unresolvedItemCount) item\(row.unresolvedItemCount == 1 ? "" : "s") couldn't parse")
                                )
                        }

                        Group {
                            if row.isApproximate {
                                Text("~\(calories) cal")
                            } else {
                                RollingNumberText(value: Double(calories), suffix: " cal")
                            }
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .modifier(InsertShimmerModifier(isActive: row.showCalorieRevealShimmer, onComplete: {
                    if let index = indexForRowID(row.id) {
                        rows[index].showCalorieRevealShimmer = false
                    }
                }))
                .modifier(CalorieUpdateShimmerModifier(isActive: row.showCalorieUpdateShimmer, onComplete: {
                    if let index = indexForRowID(row.id) {
                        rows[index].showCalorieUpdateShimmer = false
                    }
                }))
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Open item details"))
                .opacity(showCalories ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: row.parsePhase)
        .animation(.easeInOut(duration: 0.2), value: row.calories)
    }
}

struct VoiceRecordingOverlay: View {
    let transcribedText: String
    let isListening: Bool
    let audioLevel: Float
    let onCancel: () -> Void
    /// Called when the user stays silent for too long after the overlay appears.
    var onSilenceTimeout: (() -> Void)? = nil

    @State private var labelOpacity: Double = 1.0
    @State private var gradientPhase: CGFloat = 0
    /// Smooth audio level with easing — avoids jittery gradient jumps.
    @State private var smoothLevel: CGFloat = 0
    /// Tracks seconds since last detected speech for auto-dismiss.
    @State private var silenceTimer: Task<Void, Never>?

    private let silenceTimeoutSeconds: UInt64 = 4

    private var level: CGFloat { smoothLevel }

    // MARK: - Mesh Gradient (expanded + dispersed)

    private var meshPoints: [SIMD2<Float>] {
        let phase = Float(gradientPhase)
        let l = Float(level)
        // Organic sway — points drift gently based on phase + audio
        let cx = 0.5 + phase * 0.2 + l * 0.08
        let cy = 0.35 + l * 0.15
        let bx = 0.5 - phase * 0.15
        let by = 0.85 + l * 0.1
        let tx = 0.5 + phase * 0.12
        return [
            [0, 0],    [tx, 0],  [1, 0],
            [0, 0.4],  [cx, cy], [1, 0.45],
            [0, 1],    [bx, by], [1, 1]
        ]
    }

    private var meshColors: [Color] {
        let l = Double(level)
        // Richer saturation + spread across the full gradient area
        return [
            Color(red: 0.45, green: 0.15, blue: 0.85).opacity(0.55 + l * 0.2),
            Color(red: 0.35, green: 0.40, blue: 0.95).opacity(0.50 + l * 0.25),
            Color(red: 0.20, green: 0.60, blue: 0.90).opacity(0.45 + l * 0.15),

            Color(red: 0.75, green: 0.20, blue: 0.65).opacity(0.50 + l * 0.3),
            Color(red: 0.55, green: 0.25, blue: 0.95).opacity(0.65 + l * 0.3),
            Color(red: 0.30, green: 0.50, blue: 0.90).opacity(0.50 + l * 0.2),

            Color(red: 0.40, green: 0.20, blue: 0.80).opacity(0.45 + l * 0.15),
            Color(red: 0.70, green: 0.25, blue: 0.70).opacity(0.55 + l * 0.25),
            Color(red: 0.45, green: 0.30, blue: 0.85).opacity(0.45 + l * 0.15)
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                // Gradient background — taller, fades from top
                MeshGradient(width: 3, height: 3, points: meshPoints, colors: meshColors)
                    .frame(height: 240)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.3), location: 0.25),
                                .init(color: .black, location: 0.55)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                VStack(spacing: 12) {
                    if transcribedText.isEmpty {
                        Text("Listening")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .opacity(labelOpacity)
                    } else {
                        Text(transcribedText)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 24)
                    }

                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.top, 50)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                labelOpacity = 0.4
            }
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                gradientPhase = 1
            }
            startSilenceTimer()
        }
        .onDisappear {
            silenceTimer?.cancel()
        }
        .onChange(of: audioLevel) { _, newLevel in
            // Smooth the audio level with a spring so the gradient flows naturally
            withAnimation(.interpolatingSpring(stiffness: 40, damping: 8)) {
                smoothLevel = CGFloat(newLevel)
            }
        }
        .onChange(of: transcribedText) { _, newText in
            // Any new speech resets the silence timer
            if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                silenceTimer?.cancel()
            }
        }
    }

    // MARK: - Silence Timeout

    private func startSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: silenceTimeoutSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            // Only auto-dismiss if user hasn't said anything
            if transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onSilenceTimeout?() ?? onCancel()
            }
        }
    }
}

private struct InsertShimmerModifier: ViewModifier {
    let isActive: Bool
    let onComplete: () -> Void
    @State private var shimmerOffset: CGFloat = -0.6

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let sweepWidth = w * 0.55

                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.85), location: 0.45),
                                .init(color: .white.opacity(0.95), location: 0.5),
                                .init(color: .white.opacity(0.85), location: 0.55),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: sweepWidth)
                        .offset(x: shimmerOffset * (w + sweepWidth) - sweepWidth)
                        .blendMode(.sourceAtop)
                    }
                    .clipped()
                    .allowsHitTesting(false)
                    .onAppear {
                        shimmerOffset = -0.6
                        withAnimation(.easeInOut(duration: 0.7)) {
                            shimmerOffset = 1.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                            onComplete()
                        }
                    }
                }
            }
            .compositingGroup()
    }
}

/// Fast one-shot shimmer used when the calorie pill updates via the
/// client-side quantity fast path. Distinct from `InsertShimmerModifier`:
/// - shorter (~450ms total vs ~750ms) so it doesn't drag on rapid edits
/// - uses the purple→pink AI gradient so it reads as "we recalculated"
///   rather than a plain reveal
/// - wider gradient taper so small pill widths still feel like a sweep
private struct CalorieUpdateShimmerModifier: ViewModifier {
    let isActive: Bool
    let onComplete: () -> Void
    @State private var sweepPhase: CGFloat = -0.8

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let sweepWidth = w * 0.7

                        aiShimmerGradient
                            .frame(width: sweepWidth)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .white.opacity(0.7), location: 0.4),
                                        .init(color: .white, location: 0.5),
                                        .init(color: .white.opacity(0.7), location: 0.6),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .offset(x: sweepPhase * (w + sweepWidth) - sweepWidth)
                            .blendMode(.plusLighter)
                    }
                    .clipped()
                    .allowsHitTesting(false)
                    .onAppear {
                        sweepPhase = -0.8
                        withAnimation(.easeOut(duration: 0.45)) {
                            sweepPhase = 1.1
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            onComplete()
                        }
                    }
                }
            }
            .compositingGroup()
    }
}

private struct UnresolvedRowStatusView: View {
    var body: some View {
        Text("Edit & Retry")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.orange.opacity(0.95))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct FailedRowStatusView: View {
    var body: some View {
        Text(L10n.parseRetryShortLabel)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.red.opacity(0.95))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct QueuedRowStatusView: View {
    var body: some View {
        Text(L10n.parseQueuedShortLabel)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.secondary.opacity(0.95))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct RowThoughtProcessStatusView: View {
    let routeHint: LoadingRouteHint
    let startedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15)) { context in
            let start = startedAt ?? context.date
            let elapsed = max(0, context.date.timeIntervalSince(start))
            let text = phaseText(elapsed: elapsed)
            let shimmer = shimmerProgress(elapsed: elapsed)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(aiShimmerGradient)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .overlay(alignment: .trailing) {
                    GeometryReader { geometry in
                        let width = max(geometry.size.width, 1)
                        let sweepWidth = width * 0.72
                        let xOffset = (width + sweepWidth) * shimmer - sweepWidth

                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.9),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: sweepWidth, height: 16)
                        .offset(x: xOffset)
                    }
                    .mask(
                        Text(text)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    )
                    .allowsHitTesting(false)
                }
        }
    }

    private func phaseText(elapsed: TimeInterval) -> String {
        let phrases: [String]
        switch routeHint {
        case .foodDatabase:
            phrases = [
                "Looking up food",
                "Finding best match",
                "Checking serving size",
                "Estimating calories"
            ]
        case .ai:
            phrases = [
                "Reading your note",
                "Cross-checking 3 sources",
                "Resolving serving assumptions",
                "Estimating calories"
            ]
        case .unknown:
            phrases = [
                "Analyzing entry",
                "Searching matches",
                "Estimating calories"
            ]
        }

        let phaseDuration = 1.05
        let index = Int(elapsed / phaseDuration) % phrases.count
        return phrases[index]
    }

    private func shimmerProgress(elapsed: TimeInterval) -> CGFloat {
        let cycle = 1.25
        let value = (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle
        return CGFloat(value)
    }
}

// MARK: - Backspace-Detecting UITextField

private class BackspaceDetectingTextField: UITextField {
    var onDeleteBackward: (() -> Void)?

    override func deleteBackward() {
        if text?.isEmpty == true || text == nil {
            onDeleteBackward?()
        }
        super.deleteBackward()
    }

    // iOS 26 applies a yellow "Writing Tools" highlight to text fields.
    // Disable it by opting out of the text interaction styling.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Remove any system-added highlight/interaction overlays
        let interactionsToRemove = interactions.filter {
            let typeName = String(describing: type(of: $0))
            return typeName.contains("Highlight") || typeName.contains("LookUp")
        }
        for interaction in interactionsToRemove {
            removeInteraction(interaction)
        }
        // Disable the Writing Tools highlight on iOS 18.2+ / iOS 26
        if #available(iOS 18.2, *) {
            self.writingToolsBehavior = .none
        }
    }
}

private struct BackspaceAwareTextFieldRepresentable: UIViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let onFocusChanged: (Bool) -> Void
    let onSubmit: () -> Void
    let onDeleteBackwardWhenEmpty: () -> Void
    var placeholder: String = ""

    func makeUIView(context: Context) -> BackspaceDetectingTextView {
        let tv = BackspaceDetectingTextView()
        tv.font = UIFont.systemFont(ofSize: 18)
        tv.backgroundColor = .clear
        tv.tintColor = .label
        tv.textColor = .label
        tv.delegate = context.coordinator
        tv.returnKeyType = .next
        tv.autocorrectionType = .no
        tv.spellCheckingType = .no
        tv.autocapitalizationType = .none
        if #available(iOS 17.0, *) {
            tv.inlinePredictionType = .no
        }
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        // Multi-line wrapping config
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)

        tv.onDeleteBackward = { [weak tv] in
            guard tv?.text.isEmpty == true else { return }
            onDeleteBackwardWhenEmpty()
        }

        // Placeholder label
        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = UIFont.systemFont(ofSize: 18)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.tag = 999
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: tv.leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: tv.topAnchor)
        ])
        placeholderLabel.isHidden = !text.isEmpty

        return tv
    }

    func updateUIView(_ uiView: BackspaceDetectingTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        // Update placeholder visibility
        if let placeholderLabel = uiView.viewWithTag(999) as? UILabel {
            placeholderLabel.isHidden = !text.isEmpty
        }
        if isFocused && !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isFocused && uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.resignFirstResponder() }
        }
        uiView.onDeleteBackward = { [weak uiView] in
            guard uiView?.text.isEmpty == true else { return }
            onDeleteBackwardWhenEmpty()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: BackspaceAwareTextFieldRepresentable

        init(_ parent: BackspaceAwareTextFieldRepresentable) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            if parent.text != newText {
                parent.text = newText
            }
            // Update placeholder
            if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
                placeholderLabel.isHidden = !newText.isEmpty
            }
            // Notify SwiftUI to resize the view
            textView.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Return key → submit (add new row), don't insert newline
            if text == "\n" {
                parent.onSubmit()
                return false
            }
            return true
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChanged(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChanged(false)
        }
    }
}

/// UITextView subclass that detects backspace on empty text and
/// reports its intrinsic height so SwiftUI wraps it to multiple lines.
private class BackspaceDetectingTextView: UITextView {
    var onDeleteBackward: (() -> Void)?

    override var intrinsicContentSize: CGSize {
        // Use current bounds width (or a fallback) to compute the height
        // needed for the text to wrap properly.
        let width = bounds.width > 0 ? bounds.width : 200
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: max(size.height, 26))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // When bounds change (rotation, layout pass), recalculate height
        // so SwiftUI gives us enough vertical space.
        let before = intrinsicContentSize.height
        invalidateIntrinsicContentSize()
        if intrinsicContentSize.height != before {
            superview?.setNeedsLayout()
        }
    }

    override func deleteBackward() {
        let wasEmpty = text.isEmpty
        super.deleteBackward()
        if wasEmpty {
            onDeleteBackward?()
        }
    }
}

private struct MinimalRowTextEditor: View {
    @Binding var text: String
    let isFocused: Bool
    let onFocusChanged: (Bool) -> Void
    let onSubmit: () -> Void
    let onDeleteBackwardWhenEmpty: () -> Void
    var placeholder: String = ""
    var showTypewriterPlaceholder: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            BackspaceAwareTextFieldRepresentable(
                text: $text,
                isFocused: isFocused,
                onFocusChanged: onFocusChanged,
                onSubmit: onSubmit,
                onDeleteBackwardWhenEmpty: onDeleteBackwardWhenEmpty,
                placeholder: showTypewriterPlaceholder ? "" : placeholder
            )
            .frame(minHeight: 26)

            if text.isEmpty && showTypewriterPlaceholder {
                TypewriterPlaceholder(text: placeholder)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct TypewriterPlaceholder: View {
    let text: String

    private let examples = [
        "Type your food here",
        "2 eggs and toast",
        "Greek yogurt with berries",
        "Chicken salad bowl",
        "Black coffee",
        "1 banana",
        "Oatmeal with honey"
    ]

    @State private var displayedText = ""
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        Text(displayedText)
            .font(.system(size: 18))
            .foregroundStyle(Color(.placeholderText))
            .onAppear { startLoop() }
            .onDisappear { animationTask?.cancel() }
    }

    private func startLoop() {
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)

            while !Task.isCancelled {
                for example in examples {
                    guard !Task.isCancelled else { return }

                    // Type in
                    for i in 1...example.count {
                        guard !Task.isCancelled else { return }
                        displayedText = String(example.prefix(i))
                        try? await Task.sleep(nanoseconds: 55_000_000)
                    }

                    // Pause to read
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    guard !Task.isCancelled else { return }

                    // Delete out
                    for i in stride(from: example.count, through: 0, by: -1) {
                        guard !Task.isCancelled else { return }
                        displayedText = String(example.prefix(i))
                        try? await Task.sleep(nanoseconds: 35_000_000)
                    }

                    // Brief pause before next
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
    }
}

struct HM00BottomActionDock: View {
    let selectedMode: HomeInputMode
    let needsClarification: Bool
    let onSelectMode: (HomeInputMode) -> Void
    let onOpenDetails: () -> Void

    init(
        selectedMode: HomeInputMode,
        needsClarification: Bool,
        onSelectMode: @escaping (HomeInputMode) -> Void,
        onOpenDetails: @escaping () -> Void
    ) {
        self.selectedMode = selectedMode
        self.needsClarification = needsClarification
        self.onSelectMode = onSelectMode
        self.onOpenDetails = onOpenDetails
    }

    var body: some View {
        HStack(spacing: 12) {
            dockButton(mode: .voice)
            dockButton(mode: .camera)
            dockButton(mode: .manualAdd)
            detailsButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private func dockButton(mode: HomeInputMode) -> some View {
        let isActive = selectedMode == mode

        return Button {
            onSelectMode(isActive ? .text : mode)
        } label: {
            Image(systemName: mode.icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .glassEffect(isActive ? .regular.tint(Color.accentColor).interactive() : .regular.interactive(), in: .rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(mode.title))
    }

    private var detailsButton: some View {
        Button {
            onOpenDetails()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "message")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.primary)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14, style: .continuous))

                if needsClarification {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .offset(x: -2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Open details"))
    }

}

struct HM03ParseSummarySection: View {
    let totals: NutritionTotals
    let hasEditedItems: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.estimatedTotalsTitle)
                .font(.headline)

            HStack(spacing: 10) {
                statPill(title: L10n.totalsCalories, value: totals.calories, fractionDigits: 0)
                statPill(title: L10n.totalsProtein, value: totals.protein, fractionDigits: 1, unit: "g")
            }
            HStack(spacing: 10) {
                statPill(title: L10n.totalsCarbs, value: totals.carbs, fractionDigits: 1, unit: "g")
                statPill(title: L10n.totalsFat, value: totals.fat, fractionDigits: 1, unit: "g")
            }

            if hasEditedItems {
                Text(L10n.totalsEditedHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.08))
        )
    }

    private func statPill(title: String, value: Double, fractionDigits: Int, unit: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                RollingNumberText(value: value, fractionDigits: fractionDigits)
                if !unit.isEmpty {
                    Text(unit)
                }
            }
                .font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.8))
        )
    }
}

struct HM02ParseAndSaveActionsSection: View {
    let isNetworkReachable: Bool
    let networkQualityHint: String
    let isParsing: Bool
    let isSaving: Bool
    let parseDisabled: Bool
    let openDetailsDisabled: Bool
    let saveDisabled: Bool
    let retryDisabled: Bool
    let showSaveDisabledHint: Bool
    let saveSuccessMessage: String?
    let lastTimeToLogLabel: String?
    let saveError: String?
    let idempotencyKeyLabel: String?
    let onParseNow: () -> Void
    let onOpenDetails: () -> Void
    let onSave: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isNetworkReachable {
                Text(L10n.offlineBanner)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if networkQualityHint != L10n.networkOnline {
                Text(networkQualityHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(L10n.parseNowButton) {
                    onParseNow()
                }
                .buttonStyle(.borderedProminent)
                .disabled(parseDisabled)
                .accessibilityLabel(Text(L10n.parseNowButton))
                .accessibilityHint(Text(L10n.parseNowHint))

                Button(L10n.openDetailsButton) {
                    onOpenDetails()
                }
                .buttonStyle(.bordered)
                .disabled(openDetailsDisabled)
                .accessibilityLabel(Text(L10n.openDetailsButton))
                .accessibilityHint(Text(L10n.openDetailsHint))

                if isParsing {
                    ProgressView()
                    Text(L10n.parseInProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button(L10n.saveLogButton) {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(saveDisabled)
                .accessibilityLabel(Text(L10n.saveLogButton))
                .accessibilityHint(Text(L10n.saveLogHint))

                Button(L10n.retryLastSaveButton) {
                    onRetry()
                }
                .buttonStyle(.bordered)
                .disabled(retryDisabled)
                .accessibilityLabel(Text(L10n.retryLastSaveButton))
                .accessibilityHint(Text(L10n.retryLastSaveHint))

                if isSaving {
                    ProgressView()
                    Text(L10n.saveInProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showSaveDisabledHint {
                Text(L10n.saveDisabledNeedsClarification)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let saveSuccessMessage {
                Text(saveSuccessMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }

            if let lastTimeToLogLabel {
                Text(lastTimeToLogLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let saveError {
                Text(saveError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let idempotencyKeyLabel {
                Text(idempotencyKeyLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

struct HM06DaySummarySection: View {
    @Binding var selectedDate: Date
    let maximumDate: Date
    let isLoading: Bool
    let daySummaryError: String?
    let daySummary: DaySummaryResponse?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.daySummaryTitle)
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }

            HStack {
                DatePicker(
                    L10n.daySummaryDateLabel,
                    selection: $selectedDate,
                    in: ...Calendar.current.startOfDay(for: maximumDate),
                    displayedComponents: .date
                )
                    .labelsHidden()
                Text(Self.summaryDisplayFormatter.string(from: selectedDate))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let daySummaryError {
                Text(daySummaryError)
                    .font(.footnote)
                    .foregroundStyle(.red)

                Button(L10n.retrySummaryButton) {
                    onRetry()
                }
                .buttonStyle(.bordered)
            } else if let daySummary {
                if isSummaryEmpty(daySummary) {
                    Text(L10n.daySummaryZeroTotals)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                summaryProgressRow(
                    title: L10n.totalsCalories,
                    consumed: daySummary.totals.calories,
                    target: daySummary.targets.calories,
                    remaining: daySummary.remaining.calories,
                    unit: "kcal"
                )

                summaryProgressRow(
                    title: L10n.totalsProtein,
                    consumed: daySummary.totals.protein,
                    target: daySummary.targets.protein,
                    remaining: daySummary.remaining.protein,
                    unit: "g"
                )

                summaryProgressRow(
                    title: L10n.totalsCarbs,
                    consumed: daySummary.totals.carbs,
                    target: daySummary.targets.carbs,
                    remaining: daySummary.remaining.carbs,
                    unit: "g"
                )

                summaryProgressRow(
                    title: L10n.totalsFat,
                    consumed: daySummary.totals.fat,
                    target: daySummary.targets.fat,
                    remaining: daySummary.remaining.fat,
                    unit: "g"
                )
            } else {
                Text(L10n.loadingDaySummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.08))
        )
    }

    private func summaryProgressRow(
        title: String,
        consumed: Double,
        target: Double,
        remaining: Double,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 0) {
                    RollingNumberText(value: consumed, fractionDigits: 1)
                    Text("/")
                    RollingNumberText(value: target, fractionDigits: 1)
                    Text(" \(unit)")
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressFraction(consumed: consumed, target: target))
                .tint(.green)

            Text(L10n.remainingLabel(max(remaining, 0), unit: unit))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.85))
        )
    }

    private func progressFraction(consumed: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(max(consumed / target, 0), 1)
    }

    private func isSummaryEmpty(_ summary: DaySummaryResponse) -> Bool {
        summary.totals.calories <= 0.05 &&
            summary.totals.protein <= 0.05 &&
            summary.totals.carbs <= 0.05 &&
            summary.totals.fat <= 0.05
    }

    private func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static let summaryDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct HM04ClarificationEscalationSection: View {
    let parseResult: ParseLogResponse
    let isEscalating: Bool
    let escalationInfoMessage: String?
    let escalationError: String?
    let disabledReason: String?
    let canEscalate: Bool
    let onEscalate: () -> Void

    var body: some View {
        if parseResult.needsClarification {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.clarificationNeededTitle)
                    .font(.headline)

                ForEach(Array(parseResult.clarificationQuestions.enumerated()), id: \.offset) { index, question in
                    Text("\(index + 1). \(question)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button(L10n.escalateParseButton) {
                    onEscalate()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!canEscalate)
                .accessibilityLabel(Text(L10n.escalateParseButton))
                .accessibilityHint(Text(L10n.escalateParseHint))

                if isEscalating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L10n.escalatingInProgress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let escalationInfoMessage {
                    Text(escalationInfoMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                if let escalationError {
                    Text(escalationError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let disabledReason {
                    Text(disabledReason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.08))
            )
        } else if let escalationInfoMessage {
            Text(escalationInfoMessage)
                .font(.footnote)
                .foregroundStyle(.green)
        }
    }
}

private enum HomeStreakDrawerRange: Int, CaseIterable, Identifiable {
    case days30 = 30
    case year = 365

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .days30: return "30 Days"
        case .year: return "This Year"
        }
    }
}

struct HomeStreakDrawerView: View {
    @EnvironmentObject private var appStore: AppStore

    @State private var selectedRange: HomeStreakDrawerRange = .days30
    @State private var response: StreakResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedDay: StreakDay?

    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: response?.timezone ?? "") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                Picker("Streak range", selection: $selectedRange) {
                    ForEach(HomeStreakDrawerRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                if !appStore.configuration.progressFeatureEnabled {
                    disabledCard
                } else if isLoading && response == nil {
                    loadingCard
                } else if let response {
                    Group {
                        switch selectedRange {
                        case .days30:
                            StreakContributionCalendarView(
                                days: Array(response.days.reversed()),
                                range: selectedRange,
                                todayKey: todayKey,
                                timezone: response.timezone,
                                selectedDay: $selectedDay
                            )
                        case .year:
                            StreakYearGridView(
                                days: Array(response.days.reversed()),
                                todayKey: todayKey,
                                timezone: response.timezone,
                                selectedDay: $selectedDay
                            )
                        }
                    }
                    .id(selectedRange.rawValue)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))

                    legend
                } else if let errorMessage {
                    errorCard(errorMessage)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .animation(.easeInOut(duration: 0.28), value: selectedRange)
            .animation(.easeInOut(duration: 0.28), value: response?.range)
        }
        .background(Color(.systemBackground))
        .task {
            await loadStreaks()
        }
        .onChange(of: selectedRange) { _, _ in
            selectedDay = nil
            Task { await loadStreaks() }
        }
        .refreshable {
            await loadStreaks()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(response?.currentDays ?? 0) day streak")
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()

            Text("LONGEST STREAK | \(response?.longestDays ?? 0) \(response?.longestDays == 1 ? "DAY" : "DAYS")")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.primary)
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading streak history...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var disabledCard: some View {
        Text("Streaks are temporarily disabled.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)

            Button("Retry") {
                Task { await loadStreaks() }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Text("Less")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)

            ForEach(0...3, id: \.self) { level in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(StreakContributionCalendarView.color(for: level))
                    .frame(width: 16, height: 16)
            }

            Text("High")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)

            Spacer()
        }
    }

    @MainActor
    private func loadStreaks() async {
        guard appStore.configuration.progressFeatureEnabled else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await appStore.apiClient.getStreaks(
                range: selectedRange.rawValue,
                timezone: TimeZone.current.identifier
            )
            withAnimation(.easeInOut(duration: 0.28)) {
                response = result
            }
        } catch let apiError as APIClientError {
            errorMessage = apiError.errorDescription ?? "Could not load streaks."
        } catch {
            errorMessage = "Could not load streaks."
        }
    }
}

private struct StreakContributionCalendarView: View {
    let days: [StreakDay]
    let range: HomeStreakDrawerRange
    let todayKey: String
    let timezone: String
    @Binding var selectedDay: StreakDay?

    var body: some View {
        let columnCount = range == .year ? 14 : 8
        let spacing: CGFloat = range == .year ? 6 : 10
        let cellRadius: CGFloat = range == .year ? 4 : 6

        let columns = Array(
            repeating: GridItem(.flexible(), spacing: spacing),
            count: columnCount
        )

        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(days, id: \.date) { day in
                StreakDayCell(
                    day: day,
                    cornerRadius: cellRadius,
                    isToday: day.date == todayKey,
                    timezone: timezone,
                    selectedDay: $selectedDay
                )
            }
        }
    }

    static func color(for level: Int) -> Color {
        switch level {
        case 1:
            // Light peach
            return Color(red: 0.99, green: 0.83, blue: 0.65)
        case 2:
            // Pumpkin orange
            return Color(red: 0.96, green: 0.58, blue: 0.20)
        case 3:
            // Burnt sienna
            return Color(red: 0.72, green: 0.36, blue: 0.08)
        default:
            // Neutral beige (no activity)
            return Color(red: 0.91, green: 0.90, blue: 0.86)
        }
    }
}

private struct StreakYearGridView: View {
    let days: [StreakDay]
    let todayKey: String
    let timezone: String
    @Binding var selectedDay: StreakDay?

    var body: some View {
        let groups = Self.groupByMonth(days: days)

        VStack(alignment: .leading, spacing: 20) {
            ForEach(groups, id: \.key) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.label)
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)

                    let columns = Array(
                        repeating: GridItem(.flexible(), spacing: 8),
                        count: 8
                    )
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(group.days, id: \.date) { day in
                            StreakDayCell(
                                day: day,
                                cornerRadius: 5,
                                isToday: day.date == todayKey,
                                timezone: timezone,
                                selectedDay: $selectedDay
                            )
                        }
                    }
                }
            }
        }
    }

    private struct MonthGroup {
        let key: String          // "2026-04"
        let label: String        // "APRIL 2026"
        let days: [StreakDay]    // already in display order (newest first)
    }

    /// Groups a reverse-chronological day list into month buckets, preserving order.
    /// First bucket is the most recent month; days within a bucket stay in input order.
    private static func groupByMonth(days: [StreakDay]) -> [MonthGroup] {
        var groups: [MonthGroup] = []
        var bucket: [StreakDay] = []
        var currentKey: String?

        func flush() {
            guard let key = currentKey, !bucket.isEmpty else { return }
            let label = monthLabel(forKey: key, fallback: bucket.first?.date ?? "")
            groups.append(MonthGroup(key: key, label: label, days: bucket))
            bucket = []
        }

        for day in days {
            let key = String(day.date.prefix(7)) // "yyyy-MM"
            if key != currentKey {
                flush()
                currentKey = key
            }
            bucket.append(day)
        }
        flush()
        return groups
    }

    private static func monthLabel(forKey key: String, fallback: String) -> String {
        if let date = monthKeyFormatter.date(from: key) {
            return monthDisplayFormatter.string(from: date).uppercased()
        }
        return fallback
    }

    private static let monthKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static let monthDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM yyyy"
        return f
    }()
}

private struct StreakDayCell: View {
    let day: StreakDay
    let cornerRadius: CGFloat
    let isToday: Bool
    let timezone: String
    @Binding var selectedDay: StreakDay?

    var body: some View {
        let isSelected = selectedDay?.date == day.date

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(StreakContributionCalendarView.color(for: day.level))
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary, lineWidth: 2)
                    .opacity(isToday ? 1 : 0)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectedDay = isSelected ? nil : day
            }
            .popover(isPresented: Binding(
                get: { isSelected },
                set: { newValue in
                    if !newValue { selectedDay = nil }
                }
            )) {
                StreakDayPopover(day: day, isToday: isToday, timezone: timezone)
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        let foods = day.foodsCount == 1 ? "1 food" : "\(day.foodsCount) foods"
        let suffix = isToday ? ", today" : ""
        return "\(day.date): \(foods)\(suffix)"
    }
}

private struct StreakDayPopover: View {
    let day: StreakDay
    let isToday: Bool
    let timezone: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(formattedDate)
                    .font(.headline)
                if isToday {
                    Text("TODAY")
                        .font(.caption2.weight(.bold))
                        .tracking(1.0)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color(red: 0.96, green: 0.58, blue: 0.20))
                        )
                }
            }

            if day.foodsCount == 0 {
                Text("No foods logged")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(day.foodsCount) \(day.foodsCount == 1 ? "food" : "foods") logged")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if day.logsCount > 1 {
                    Text("Across \(day.logsCount) entries")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 180, alignment: .leading)
    }

    private var formattedDate: String {
        Self.formatDate(day.date, timezone: timezone)
    }

    private static let dateDisplay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = .current
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private static func formatDate(_ value: String, timezone: String) -> String {
        let effectiveTimezone = TimeZone(identifier: timezone) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = effectiveTimezone
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return value }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = effectiveTimezone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let date = calendar.date(from: components) else { return value }
        dateDisplay.timeZone = effectiveTimezone
        return dateDisplay.string(from: date)
    }
}
