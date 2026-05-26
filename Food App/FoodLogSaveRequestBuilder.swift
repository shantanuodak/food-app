import Foundation

enum FoodLogSaveRequestBuilderError: LocalizedError {
    case noParsedItems
    case needsClarification

    var errorDescription: String? {
        switch self {
        case .noParsedItems:
            return "No food items were parsed."
        case .needsClarification:
            return "This food log needs clarification before it can be saved."
        }
    }
}

enum FoodLogSaveRequestBuilder {
    static func makeSaveRequest(
        rawText: String,
        loggedAt fallbackLoggedAt: String,
        parseResponse response: ParseLogResponse,
        inputKind: String = "text"
    ) throws -> SaveLogRequest {
        let items = try saveItems(from: response)
        let totals = NutritionTotals(
            calories: roundOneDecimal(items.reduce(0) { $0 + $1.calories }),
            protein: roundOneDecimal(items.reduce(0) { $0 + $1.protein }),
            carbs: roundOneDecimal(items.reduce(0) { $0 + $1.carbs }),
            fat: roundOneDecimal(items.reduce(0) { $0 + $1.fat })
        )

        return SaveLogRequest(
            parseRequestId: response.parseRequestId,
            parseVersion: response.parseVersion,
            parsedLog: SaveLogBody(
                rawText: rawText,
                loggedAt: response.loggedAt.isEmpty ? fallbackLoggedAt : response.loggedAt,
                mealType: FoodLogMealTag.inferred(
                    from: HomeLoggingDateUtils.date(fromLoggedAt: response.loggedAt.isEmpty ? fallbackLoggedAt : response.loggedAt) ?? Date()
                ).rawValue,
                inputKind: inputKind,
                imageRef: nil,
                confidence: response.confidence,
                totals: totals,
                sourcesUsed: response.sourcesUsed,
                assumptions: response.assumptions,
                items: items
            )
        )
    }

    private static func saveItems(from response: ParseLogResponse) throws -> [SaveParsedFoodItem] {
        guard !response.items.isEmpty else {
            throw FoodLogSaveRequestBuilderError.noParsedItems
        }

        let needsClarification = response.needsClarification || response.items.contains { item in
            item.needsClarification == true || item.isUnresolvedPlaceholder
        }
        if needsClarification {
            throw FoodLogSaveRequestBuilderError.needsClarification
        }

        return response.items.map { item in
            SaveParsedFoodItem(
                name: item.name,
                quantity: item.amount ?? item.quantity,
                amount: item.amount ?? item.quantity,
                unit: item.unitNormalized ?? item.unit,
                unitNormalized: item.unitNormalized ?? item.unit,
                grams: item.grams,
                gramsPerUnit: item.gramsPerUnit,
                calories: item.calories,
                protein: item.protein,
                carbs: item.carbs,
                fat: item.fat,
                nutritionSourceId: item.nutritionSourceId,
                originalNutritionSourceId: item.originalNutritionSourceId,
                sourceFamily: item.sourceFamily,
                matchConfidence: item.matchConfidence,
                needsClarification: false,
                manualOverride: nil
            )
        }
    }

    private static func roundOneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
