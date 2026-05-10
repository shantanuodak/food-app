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
