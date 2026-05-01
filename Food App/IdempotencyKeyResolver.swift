import Foundation

struct IdempotencyKeyResolver {
    /// Reuses the existing idempotency key for a row (if present in queue),
    /// otherwise mints a new UUID.
    static func resolve(
        rowID: UUID,
        queue: [PendingSaveQueueItem],
        requiresUnsavedRow: Bool = true
    ) -> UUID {
        let existing = queue.first { item in
            guard item.rowID == rowID else { return false }
            if requiresUnsavedRow {
                return item.serverLogId == nil
            }
            return true
        }?.idempotencyKey
        return existing.flatMap(UUID.init(uuidString:)) ?? UUID()
    }

    static func resolve(
        rowID: UUID?,
        queue: [PendingSaveQueueItem],
        requiresUnsavedRow: Bool = true
    ) -> UUID {
        guard let rowID else { return UUID() }
        return resolve(rowID: rowID, queue: queue, requiresUnsavedRow: requiresUnsavedRow)
    }
}
