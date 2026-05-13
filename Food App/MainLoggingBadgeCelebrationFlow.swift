import Foundation

extension MainLoggingShellView {
    func scheduleBadgeCelebrationCheckAfterSave() {
        guard appStore.configuration.progressFeatureEnabled else { return }

        badgeCelebrationCheckTask?.cancel()
        badgeCelebrationCheckTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await runBadgeCelebrationCheckAfterSave()
        }
    }

    func runBadgeCelebrationCheckAfterSave() async {
        guard appStore.configuration.progressFeatureEnabled else { return }
        guard triggeredBadgeAchievement == nil else { return }

        if let lastBadgeCelebrationCheckAt,
           Date().timeIntervalSince(lastBadgeCelebrationCheckAt) < 2 {
            return
        }
        lastBadgeCelebrationCheckAt = Date()

        do {
            let timezone = TimeZone.current.identifier
            let today = HomeStreakDrawerView.dateKey(for: Date(), timezoneID: timezone)
            async let summary = appStore.apiClient.getBadgesSummary(timezone: timezone)
            async let streaks = appStore.apiClient.getStreaks(range: 30, to: today, timezone: timezone)
            let (badgesSummary, streakResponse) = try await (summary, streaks)

            if let badge = BadgeCelebrationState.badgeToCelebrate(
                totals: badgesSummary.totals,
                currentStreakDays: streakResponse.currentDays
            ) {
                triggeredBadgeAchievement = badge
            }
        } catch {
            // Badge celebrations are non-critical. Logging must never feel
            // slower or broken because this lightweight reward check failed.
        }
    }
}
