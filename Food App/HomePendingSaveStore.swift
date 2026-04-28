import Foundation

/// Persists the in-flight auto-save draft so a quit/relaunch does not lose a parsed row.
enum HomePendingSaveStore {
    private static let defaultsKey = "app.pendingSaveDraft.v1"
    private static let queueKey = "app.pendingSaveQueue.v1"

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
        defaults.removeObject(forKey: queueKey)
    }

    static func save(_ draft: PendingSaveDraft, defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(draft) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    static func load(defaults: UserDefaults = .standard) -> PendingSaveDraft? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(PendingSaveDraft.self, from: data)
    }

    static func saveQueue(_ items: [PendingSaveQueueItem], defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(items) else { return }
        defaults.set(data, forKey: queueKey)
    }

    static func loadQueue(defaults: UserDefaults = .standard) -> [PendingSaveQueueItem] {
        var items: [PendingSaveQueueItem] = []
        if let data = defaults.data(forKey: queueKey),
           let decoded = try? JSONDecoder().decode([PendingSaveQueueItem].self, from: data) {
            items = decoded
        }

        if let legacy = load(defaults: defaults),
           !items.contains(where: { $0.idempotencyKey == legacy.idempotencyKey }) {
            let legacyItem = PendingSaveQueueItem(
                id: UUID(),
                rowID: nil,
                request: legacy.request,
                fingerprint: legacy.fingerprint,
                idempotencyKey: legacy.idempotencyKey,
                dateString: String(legacy.request.parsedLog.loggedAt.prefix(10)),
                createdAt: Date(),
                imageUploadData: nil,
                imagePreviewData: nil,
                imageMimeType: nil,
                serverLogId: nil
            )
            items.append(legacyItem)
            saveQueue(items, defaults: defaults)
        }

        defaults.removeObject(forKey: defaultsKey)
        return items
    }
}
