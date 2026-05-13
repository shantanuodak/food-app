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

/// Disk-backed cache for daily summary totals/targets. Kept separate from
/// `HomeDayLogsDiskCache` so older installs with only log cache keep working.
enum HomeDaySummaryDiskCache {
    private static let keyPrefix = "app.daysummary.cache.v1."

    static func persist(_ response: DaySummaryResponse, date: String, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        defaults.set(data, forKey: keyPrefix + date)
    }

    static func load(date: String, defaults: UserDefaults = .standard) -> DaySummaryResponse? {
        guard let data = defaults.data(forKey: keyPrefix + date) else { return nil }
        return try? JSONDecoder().decode(DaySummaryResponse.self, from: data)
    }

    static func remove(date: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: keyPrefix + date)
    }
}
