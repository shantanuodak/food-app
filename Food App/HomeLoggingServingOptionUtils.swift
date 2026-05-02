import Foundation

enum HomeLoggingServingOptionUtils {
    nonisolated static func isGeminiParsedItem(_ item: ParsedFoodItem) -> Bool {
        let source = HomeLoggingDisplayText.normalizedLookupValue(item.nutritionSourceId)
        let family = HomeLoggingDisplayText.normalizedLookupValue(item.sourceFamily ?? "")
        return source.contains("gemini") || family == "gemini"
    }

    nonisolated static func selectedServingOptionOffset(
        rowItem: ParsedFoodItem,
        servingOptions: [ParsedServingOption]
    ) -> Int? {
        servingOptions.firstIndex { option in
            isServingOptionSelected(rowItem: rowItem, option: option)
        }
    }

    nonisolated static func isServingOptionSelected(
        rowItem: ParsedFoodItem,
        option: ParsedServingOption
    ) -> Bool {
        let rowSource = HomeLoggingDisplayText.normalizedLookupValue(rowItem.nutritionSourceId)
        let optionSource = HomeLoggingDisplayText.normalizedLookupValue(option.nutritionSourceId)
        if !rowSource.isEmpty, !optionSource.isEmpty, rowSource != optionSource {
            return false
        }

        let rowQuantity = max(rowItem.quantity, 0.0001)
        let optionUsesServingBasis = servingOptionUsesServingBasis(option)
        let optionQuantity = optionUsesServingBasis ? 1.0 : max(option.quantity, 0.0001)
        let rowGramsPerUnit = rowItem.gramsPerUnit ?? (rowItem.grams / rowQuantity)
        let optionGramsPerUnit = optionUsesServingBasis
            ? option.grams
            : (option.grams / optionQuantity)
        let rowCaloriesPerUnit = rowItem.calories / rowQuantity
        let optionCaloriesPerUnit = optionUsesServingBasis
            ? option.calories
            : (option.calories / optionQuantity)
        let rowProteinPerUnit = rowItem.protein / rowQuantity
        let optionProteinPerUnit = optionUsesServingBasis
            ? option.protein
            : (option.protein / optionQuantity)
        let rowCarbsPerUnit = rowItem.carbs / rowQuantity
        let optionCarbsPerUnit = optionUsesServingBasis
            ? option.carbs
            : (option.carbs / optionQuantity)
        let rowFatPerUnit = rowItem.fat / rowQuantity
        let optionFatPerUnit = optionUsesServingBasis
            ? option.fat
            : (option.fat / optionQuantity)

        return nearlyEqual(rowGramsPerUnit, optionGramsPerUnit, tolerance: 0.2) &&
            nearlyEqual(rowCaloriesPerUnit, optionCaloriesPerUnit, tolerance: 0.2) &&
            nearlyEqual(rowProteinPerUnit, optionProteinPerUnit, tolerance: 0.2) &&
            nearlyEqual(rowCarbsPerUnit, optionCarbsPerUnit, tolerance: 0.2) &&
            nearlyEqual(rowFatPerUnit, optionFatPerUnit, tolerance: 0.2)
    }

    nonisolated static func servingOptionUsesServingBasis(_ option: ParsedServingOption) -> Bool {
        if abs(option.quantity - 1) > 0.0001 {
            return true
        }
        return isWeightOrVolumeServingUnit(option.unit)
    }

    nonisolated static func isWeightOrVolumeServingUnit(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "g" || normalized == "gram" || normalized == "grams" ||
            normalized == "ml" || normalized == "milliliter" || normalized == "milliliters" ||
            normalized == "oz" || normalized == "ounce" || normalized == "ounces"
    }

    nonisolated static func nearlyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
