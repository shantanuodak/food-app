import Foundation

enum HomeLoggingDisplayText {
    nonisolated static func sourceDisplayName(_ source: String) -> String {
        switch source.lowercased() {
        case "gemini":
            return "Gemini"
        case "cache":
            return "Cache"
        case "manual":
            return "Manual"
        default:
            return source
        }
    }

    nonisolated static func sourceReferenceLabel(for rawSourceID: String) -> String {
        let normalized = normalizedLookupValue(rawSourceID)
        if normalized.contains("gemini") {
            return "Gemini nutrition estimate"
        }
        if normalized.contains("cache") {
            return "Cached nutrition result"
        }
        if normalized.contains("manual") {
            return "Manual nutrition edit"
        }
        return rawSourceID
    }

    nonisolated static func sourceLabelForRowItems(
        _ items: [ParsedFoodItem],
        route: String?,
        routeDisplayName: String?
    ) -> String {
        guard !items.isEmpty else {
            return nutritionSourceDisplayName(nil, route: route, routeDisplayName: routeDisplayName)
        }

        let labels = Array(Set(items.map {
            nutritionSourceDisplayName($0.nutritionSourceId, route: route, routeDisplayName: routeDisplayName)
        })).sorted()
        if labels.count == 1, let label = labels.first {
            return label
        }
        return labels.joined(separator: ", ")
    }

    nonisolated static func nutritionSourceDisplayName(
        _ nutritionSourceId: String?,
        route: String?,
        routeDisplayName: String?
    ) -> String {
        let upstreamSource = upstreamNutritionSourceDisplayName(nutritionSourceId)

        guard let route else {
            return upstreamSource ?? "Estimate"
        }

        let normalizedRoute = route.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedRoute == "cache" {
            if let upstreamSource {
                return "Cache (\(upstreamSource))"
            }
            return "Cache"
        }

        return upstreamSource ?? routeDisplayName ?? route
    }

    nonisolated static func upstreamNutritionSourceDisplayName(_ nutritionSourceId: String?) -> String? {
        guard let nutritionSourceId else { return nil }
        let trimmed = nutritionSourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.lowercased()
        if normalized.contains("gemini") {
            return "Gemini"
        }
        if normalized.contains("manual") {
            return "Manual"
        }
        if normalized.contains("cache") {
            return "Cache"
        }
        return nil
    }

    nonisolated static func normalizedLookupValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated static func thoughtProcessText(
        for row: HomeLogRow,
        sourceLabel: String,
        items: [ParsedFoodItem],
        needsClarification: Bool
    ) -> String {
        let rowText = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if items.count > 1 {
            let itemNames = items.map(\.name)
            let previewNames: String
            if itemNames.count <= 3 {
                previewNames = itemNames.joined(separator: ", ")
            } else {
                previewNames = itemNames.prefix(3).joined(separator: ", ") + " +\(itemNames.count - 3) more"
            }
            let estimatedCalories = Int(items.reduce(0) { $0 + $1.calories }.rounded())
            var thought = "Interpreted “\(rowText)” as multiple items: \(previewNames). "
            thought += "Used \(sourceLabel) nutrition data to estimate \(estimatedCalories) kcal total."
            if row.isApproximate || needsClarification {
                thought += " This is marked as approximate because confidence is below the strict threshold."
            }
            return thought
        }

        if let item = items.first {
            if let explanation = item.explanation, !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return explanation
            }
            var thought = "Interpreted “\(rowText)” as “\(item.name)”. "
            thought += "Used \(formatOneDecimal(item.quantity)) \(item.unit) (~\(formatOneDecimal(item.grams)) g) "
            thought += "with \(sourceLabel) nutrition data to estimate \(Int(item.calories.rounded())) kcal and scale macros."
            if row.isApproximate || needsClarification {
                thought += " This is marked as approximate because confidence is below the strict threshold."
            }
            return thought
        }

        var fallback = "A calorie estimate is available for this row, but no fully matched nutrition item was retained."
        fallback += " Re-parse or open Parse Details to refine mapping and macro breakdown."
        return fallback
    }

    /// Produces a short, readable label from parsed food items for the home screen row.
    /// Example: "Chobani Complete 20g Protein Zero Added Sugar Mixed Berry..." becomes "Chobani Protein Drink".
    nonisolated static func shortenedFoodLabel(items: [ParsedFoodItem], extractedText: String?) -> String {
        if items.isEmpty {
            let fallback = (extractedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? "Photo meal" : truncateLabel(fallback, maxWords: 4)
        }

        if items.count == 1 {
            return truncateLabel(items[0].name, maxWords: 4)
        }

        let shortened = items.prefix(3).map { truncateLabel($0.name, maxWords: 3) }
        let label = shortened.joined(separator: ", ")
        if items.count > 3 {
            return "\(label) + \(items.count - 3) more"
        }
        return label
    }

    nonisolated static func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    nonisolated static func roundOneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    nonisolated private static func truncateLabel(_ text: String, maxWords: Int) -> String {
        let noise: Set<String> = ["g", "oz", "ml", "mg", "added", "zero", "sugar", "free", "with", "no", "of"]
        let words = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)

        var kept: [String] = []
        for word in words {
            let lowered = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if lowered.isEmpty { continue }
            let isNumericUnit = lowered.allSatisfy({ $0.isNumber || $0 == "." }) || noise.contains(lowered)
            if isNumericUnit && !kept.isEmpty { continue }

            kept.append(word)
            if kept.count >= maxWords { break }
        }

        return kept.isEmpty ? text.prefix(30).trimmingCharacters(in: .whitespacesAndNewlines) : kept.joined(separator: " ")
    }
}
