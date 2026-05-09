import Foundation

struct QuickCameraPendingLog: Codable {
    let id: String
    let createdAt: Date
    let displayName: String
    let calories: Int
    let saveRequest: SaveLogRequest?
    let idempotencyKey: UUID?

    var canSaveDirectly: Bool {
        saveRequest != nil && idempotencyKey != nil
    }
}

enum QuickCameraPendingLogStore {
    private static let storageKey = "quickCamera.pendingLogs.v1"

    static func save(_ pendingLog: QuickCameraPendingLog) {
        var logs = loadAll()
        logs[pendingLog.id] = pendingLog
        persist(logs)
    }

    static func load(id: String) -> QuickCameraPendingLog? {
        loadAll()[id]
    }

    static func remove(id: String) {
        var logs = loadAll()
        logs.removeValue(forKey: id)
        persist(logs)
    }

    private static func loadAll() -> [String: QuickCameraPendingLog] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let logs = try? JSONDecoder().decode([String: QuickCameraPendingLog].self, from: data) else {
            return [:]
        }
        return logs
    }

    private static func persist(_ logs: [String: QuickCameraPendingLog]) {
        guard let data = try? JSONEncoder().encode(logs) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
