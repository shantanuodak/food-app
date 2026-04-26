import Foundation

/// Disk-backed stale-while-revalidate cache for home day logs.
enum HomeDayLogsDiskCache {
    private static let keyPrefix = "app.daylogs.cache.v1."

    static func persist(_ response: DayLogsResponse, date: String, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        defaults.set(data, forKey: keyPrefix + date)
    }

    static func load(date: String, defaults: UserDefaults = .standard) -> DayLogsResponse? {
        guard let data = defaults.data(forKey: keyPrefix + date) else { return nil }
        return try? JSONDecoder().decode(DayLogsResponse.self, from: data)
    }

    static func remove(date: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: keyPrefix + date)
    }
}
