import Foundation

struct ProfileDashboardSnapshot {
    let profile: OnboardingProfileResponse?
    let daySummary: DaySummaryResponse?
    let todayLogsCount: Int?
    let progress: ProgressResponse?
    let streaks: StreakResponse?
    let dateString: String
    let timezone: String
    let loadedAt: Date

    func isUsable(for dateString: String, timezone: String, maxAge: TimeInterval = 120) -> Bool {
        self.dateString == dateString &&
            self.timezone == timezone &&
            Date().timeIntervalSince(loadedAt) <= maxAge
    }
}

struct ProgressChartsSnapshot {
    let range: ProgressRange
    let progress: ProgressResponse?
    let weightSamples: [BodyMassSample]
    let stepsSamples: [DailyStepCount]
    let preferredUnits: UnitsOption
    let startDate: Date
    let endDate: Date
    let from: String
    let to: String
    let timezone: String
    let loadedAt: Date

    func isUsable(for range: ProgressRange, timezone: String, maxAge: TimeInterval = 120) -> Bool {
        guard self.range == range,
              self.timezone == timezone,
              Date().timeIntervalSince(loadedAt) <= maxAge
        else {
            return false
        }

        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.isDate(endDate, inSameDayAs: today)
    }
}
