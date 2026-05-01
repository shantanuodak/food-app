import Foundation

/// Single source of truth for whether a parsed row should be sent to save now.
struct SaveEligibility {
    static func isRowEligible(
        row: HomeLogRow?,
        snapshot: ParseSnapshot,
        autoSavedParseIDs: Set<String>
    ) -> Bool {
        guard !autoSavedParseIDs.contains(snapshot.parseRequestId) else { return false }

        if let row {
            // Product rule: if calories are visible, persist the row.
            if row.calories != nil {
                return true
            }
            return !row.parsedItems.isEmpty || row.parsedItem != nil
        }

        // Fallback for rows no longer mounted in `inputRows`.
        if !snapshot.rowItems.isEmpty { return true }
        if !snapshot.response.items.isEmpty { return true }
        return snapshot.response.totals.calories > 0
    }
}
