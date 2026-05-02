import Foundation

enum HomeLoggingRowFactory {
    nonisolated static func normalizedInputKind(_ rawValue: String?, fallback: String = "text") -> String {
        let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch normalized {
        case "text", "image", "voice", "manual":
            return normalized
        default:
            return fallback
        }
    }

    nonisolated static func pendingSaveItem(_ item: PendingSaveQueueItem, matchesServerLog log: DayLogEntry) -> Bool {
        let pending = item.request.parsedLog
        guard HomeLoggingTextMatch.normalizedRowText(pending.rawText) == HomeLoggingTextMatch.normalizedRowText(log.rawText) else {
            return false
        }
        guard normalizedInputKind(pending.inputKind, fallback: "text") == normalizedInputKind(log.inputKind, fallback: "text") else {
            return false
        }
        guard pending.loggedAt == log.loggedAt else { return false }
        return abs(pending.totals.calories - log.totals.calories) <= 0.5
    }

    nonisolated static func makePendingSaveRow(from item: PendingSaveQueueItem) -> HomeLogRow {
        let body = item.request.parsedLog
        let parsedItems = body.items.map(parsedFoodItem(from:))
        let displayText: String
        if normalizedInputKind(body.inputKind, fallback: "text") == "image" &&
            body.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            displayText = "Photo meal"
        } else {
            displayText = body.rawText
        }
        let stableID = item.rowID ?? UUID(uuid: stableUUID(from: item.idempotencyKey))
        return HomeLogRow(
            id: stableID,
            text: displayText,
            calories: Int(body.totals.calories.rounded()),
            calorieRangeText: nil,
            isApproximate: false,
            parsePhase: .idle,
            parsedItem: parsedItems.first,
            parsedItems: parsedItems,
            editableItemIndices: [],
            normalizedTextAtParse: HomeLoggingTextMatch.normalizedRowText(displayText),
            imagePreviewData: item.imagePreviewData,
            imageRef: body.imageRef,
            isSaved: item.serverLogId != nil,
            savedAt: nil,
            serverLogId: item.serverLogId,
            serverLoggedAt: body.loggedAt
        )
    }

    nonisolated static func makeSavedRow(from entry: DayLogEntry) -> HomeLogRow {
        let items = entry.items.map(parsedFoodItem(from:))
        let stableID = UUID(uuidString: entry.id) ?? UUID(uuid: stableUUID(from: entry.id))
        let displayText: String
        if entry.inputKind == "image" && entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            displayText = "Photo meal"
        } else {
            displayText = entry.rawText
        }
        return HomeLogRow(
            id: stableID,
            text: displayText,
            calories: Int(entry.totals.calories.rounded()),
            calorieRangeText: nil,
            isApproximate: false,
            parsePhase: .idle,
            parsedItem: items.first,
            parsedItems: items,
            editableItemIndices: [],
            // Stamp with the server's rawText so quantity-only edits can use
            // the fast path instead of triggering a fresh parse.
            normalizedTextAtParse: HomeLoggingTextMatch.normalizedRowText(displayText),
            imagePreviewData: nil,
            imageRef: entry.imageRef,
            isSaved: true,
            savedAt: nil,
            serverLogId: entry.id,
            serverLoggedAt: entry.loggedAt
        )
    }

    nonisolated static func parsedFoodItem(from item: SaveParsedFoodItem) -> ParsedFoodItem {
        ParsedFoodItem(
            name: item.name,
            quantity: item.amount ?? item.quantity,
            unit: item.unit,
            grams: item.grams,
            calories: item.calories,
            protein: item.protein,
            carbs: item.carbs,
            fat: item.fat,
            nutritionSourceId: item.nutritionSourceId,
            originalNutritionSourceId: item.originalNutritionSourceId,
            sourceFamily: item.sourceFamily,
            matchConfidence: item.matchConfidence,
            amount: item.amount,
            unitNormalized: item.unitNormalized,
            gramsPerUnit: item.gramsPerUnit,
            needsClarification: item.needsClarification,
            manualOverride: item.manualOverride?.enabled
        )
    }

    nonisolated private static func parsedFoodItem(from item: DayLogItem) -> ParsedFoodItem {
        ParsedFoodItem(
            name: item.foodName,
            quantity: item.quantity,
            unit: item.unit,
            grams: item.grams,
            calories: item.calories,
            protein: item.protein,
            carbs: item.carbs,
            fat: item.fat,
            nutritionSourceId: item.nutritionSourceId,
            sourceFamily: item.sourceFamily,
            matchConfidence: item.matchConfidence,
            unitNormalized: item.unitNormalized
        )
    }

    nonisolated private static func stableUUID(from string: String) -> uuid_t {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        let h1 = hash

        var hash2: UInt64 = 0x517cc1b727220a95
        for byte in string.utf8 {
            hash2 = hash2 &* 0x100000001b3
            hash2 ^= UInt64(byte)
        }
        let h2 = hash2

        return (
            UInt8(truncatingIfNeeded: h1), UInt8(truncatingIfNeeded: h1 >> 8),
            UInt8(truncatingIfNeeded: h1 >> 16), UInt8(truncatingIfNeeded: h1 >> 24),
            UInt8(truncatingIfNeeded: h1 >> 32), UInt8(truncatingIfNeeded: h1 >> 40),
            UInt8(truncatingIfNeeded: h1 >> 48), UInt8(truncatingIfNeeded: h1 >> 56),
            UInt8(truncatingIfNeeded: h2), UInt8(truncatingIfNeeded: h2 >> 8),
            UInt8(truncatingIfNeeded: h2 >> 16), UInt8(truncatingIfNeeded: h2 >> 24),
            UInt8(truncatingIfNeeded: h2 >> 32), UInt8(truncatingIfNeeded: h2 >> 40),
            UInt8(truncatingIfNeeded: h2 >> 48), UInt8(truncatingIfNeeded: h2 >> 56)
        )
    }
}
