import Foundation

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
    case primed(startedAt: Date)
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
    /// Deterministic hydration parse data. Hydration rows intentionally do not
    /// carry food parser items or calories; they are persisted to hydration_logs.
    var hydrationAmountMl: Double? = nil
    var hydrationInputAmount: Double? = nil
    var hydrationInputUnit: String? = nil
    var hydrationConfidence: Double? = nil
    var hydrationLogId: String? = nil
    /// Server-side `food_logs.id` for rows that were loaded from the backend.
    /// Used to branch the save path between POST (new) and PATCH (edit) so
    /// editing a saved row doesn't create a duplicate entry.
    var serverLogId: String? = nil
    /// ISO-8601 `logged_at` stamp for server-backed rows. Preserved across
    /// un-save → edit → PATCH so cache invalidation targets the correct day
    /// (not the day the user happens to be viewing now).
    var serverLoggedAt: String? = nil
    /// Saved-meal provenance for logs created via the Saved Meals surface.
    /// This drives the selected "Saved" state in row details so the user
    /// can't accidentally save the same logged saved meal again.
    var savedMealId: String? = nil
    var savedMealName: String? = nil
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
            hydrationAmountMl: nil,
            hydrationInputAmount: nil,
            hydrationInputUnit: nil,
            hydrationConfidence: nil,
            hydrationLogId: nil,
            serverLogId: nil
        )
    }

    var isHydration: Bool {
        hydrationAmountMl != nil
    }

    var hydrationDisplayLabel: String? {
        guard let amountMl = hydrationAmountMl else { return nil }
        return HydrationDisplayText.shortLabel(
            amountMl: amountMl,
            inputAmount: hydrationInputAmount,
            inputUnit: hydrationInputUnit
        )
    }

    var isLoading: Bool {
        if case .active = parsePhase {
            return true
        }
        return false
    }

    var isPrimed: Bool {
        if case .primed = parsePhase {
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
        if case let .primed(startedAt) = parsePhase {
            return startedAt
        }
        if case let .active(_, startedAt) = parsePhase {
            return startedAt
        }
        return nil
    }

    mutating func setParsePrimed(startedAt: Date = Date()) {
        parsePhase = .primed(startedAt: startedAt)
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

struct LoggedSavedMealMarker: Codable, Equatable, Sendable {
    let savedMealId: String
    let savedMealName: String
}

enum LoggedSavedMealStore {
    nonisolated private static let key = "app.saved_meal.logged_markers.v1"

    nonisolated static func marker(for logId: String, defaults: UserDefaults = .standard) -> LoggedSavedMealMarker? {
        load(defaults: defaults)[logId]
    }

    nonisolated static func save(logId: String, meal: SavedMeal, defaults: UserDefaults = .standard) {
        save(logId: logId, savedMealId: meal.id, savedMealName: meal.name, defaults: defaults)
    }

    nonisolated static func save(
        logId: String,
        savedMealId: String,
        savedMealName: String,
        defaults: UserDefaults = .standard
    ) {
        var markers = load(defaults: defaults)
        markers[logId] = LoggedSavedMealMarker(savedMealId: savedMealId, savedMealName: savedMealName)
        persist(markers, defaults: defaults)
    }

    nonisolated static func remove(logId: String, defaults: UserDefaults = .standard) {
        var markers = load(defaults: defaults)
        markers.removeValue(forKey: logId)
        persist(markers, defaults: defaults)
    }

    nonisolated private static func load(defaults: UserDefaults) -> [String: LoggedSavedMealMarker] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: LoggedSavedMealMarker].self, from: data) else {
            return [:]
        }
        return decoded
    }

    nonisolated private static func persist(_ markers: [String: LoggedSavedMealMarker], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(markers) else { return }
        defaults.set(data, forKey: key)
    }
}

enum HydrationDisplayText {
    nonisolated static func shortLabel(
        amountMl: Double,
        inputAmount: Double? = nil,
        inputUnit: String? = nil
    ) -> String {
        if let inputAmount, let unit = normalizedUnitLabel(inputUnit), inputAmount > 0 {
            return "\(formatAmount(inputAmount)) \(unit)"
        }

        if amountMl >= 1000 {
            let liters = amountMl / 1000
            return "\(formatAmount(liters)) L"
        }
        return "\(Int(amountMl.rounded())) ml"
    }

    nonisolated static func longLabel(
        amountMl: Double,
        inputAmount: Double? = nil,
        inputUnit: String? = nil
    ) -> String {
        "\(shortLabel(amountMl: amountMl, inputAmount: inputAmount, inputUnit: inputUnit)) water"
    }

    nonisolated private static func normalizedUnitLabel(_ rawUnit: String?) -> String? {
        guard let rawUnit else { return nil }
        let normalized = rawUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres":
            return "ml"
        case "l", "liter", "liters", "litre", "litres":
            return "L"
        case "oz", "fl oz", "fluid ounce", "fluid ounces", "ounce", "ounces":
            return "oz"
        case "cup", "cups":
            return inputCupLabel(rawUnit: normalized)
        default:
            return nil
        }
    }

    nonisolated private static func inputCupLabel(rawUnit: String) -> String {
        rawUnit == "cup" ? "cup" : "cups"
    }

    nonisolated private static func formatAmount(_ amount: Double) -> String {
        if abs(amount.rounded() - amount) < 0.01 {
            return "\(Int(amount.rounded()))"
        }
        return String(format: "%.1f", amount)
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
