import Foundation

/// Persists the in-flight auto-save draft so a quit/relaunch does not lose a parsed row.
enum HomePendingSaveStore {
    private static let defaultsKey = "app.pendingSaveDraft.v1"

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
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
}
