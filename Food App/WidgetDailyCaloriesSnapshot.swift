import Foundation
import WidgetKit

struct WidgetDailyCaloriesSnapshot: Codable, Equatable {
    let date: String
    let consumedCalories: Double
    let targetCalories: Double
    let consumedProtein: Double
    let consumedCarbs: Double
    let consumedFat: Double
    let updatedAt: Date
}

enum WidgetDailyCaloriesStore {
    static let appGroupID = "group.com.shantanu.foodapp"
    static let snapshotKey = "widget.dailyCaloriesSnapshot"
    static let widgetKind = "FoodCameraWidget"

    static func saveToday(summary: DaySummaryResponse, dateString: String) {
        guard summary.date == dateString else { return }
        guard dateString == HomeLoggingDateUtils.summaryRequestFormatter.string(from: Date()) else { return }

        let snapshot = WidgetDailyCaloriesSnapshot(
            date: summary.date,
            consumedCalories: max(0, summary.totals.calories),
            targetCalories: max(0, summary.targets.calories),
            consumedProtein: max(0, summary.totals.protein),
            consumedCarbs: max(0, summary.totals.carbs),
            consumedFat: max(0, summary.totals.fat),
            updatedAt: Date()
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroupID)?.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Reads the most recent snapshot the main app pushed to the shared
    /// app-group store. Used by in-app surfaces (e.g., the widget setup
    /// guide preview) so they render the same data the live widget shows.
    /// Returns nil when no snapshot has been written yet.
    static func loadCurrent() -> WidgetDailyCaloriesSnapshot? {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetDailyCaloriesSnapshot.self, from: data)
    }
}
