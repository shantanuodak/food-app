import Foundation

extension MainLoggingShellView {
    func scheduleBadgeCelebrationCheckAfterSave(
        preferredCategory: BadgeDefinition.Category? = nil,
        delayNanoseconds: UInt64 = 700_000_000,
        retryCount: Int = 0
    ) {
        guard appStore.configuration.progressFeatureEnabled else { return }

        badgeCelebrationCheckTask?.cancel()
        badgeCelebrationCheckTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await runBadgeCelebrationCheckAfterSave(
                preferredCategory: preferredCategory,
                retryCount: retryCount
            )
        }
    }

    func scheduleBadgeCelebrationCheckAfterHydrationSave(delayNanoseconds: UInt64 = 900_000_000) {
        scheduleBadgeCelebrationCheckAfterSave(
            preferredCategory: .hydration,
            delayNanoseconds: delayNanoseconds
        )
    }

    func syncHealthActivityForBadgesIfNeeded(force: Bool = false) {
        guard appStore.configuration.progressFeatureEnabled else { return }
        guard appStore.isSessionRestored,
              appStore.isOnboardingComplete,
              appStore.authSessionStore.session != nil,
              appStore.isNetworkReachable,
              appStore.isHealthSyncEnabled,
              appStore.healthAuthorizationState == .authorized else { return }

        if !force,
           let lastHealthActivityBadgeSyncAt,
           Date().timeIntervalSince(lastHealthActivityBadgeSyncAt) < 3_600 {
            return
        }
        lastHealthActivityBadgeSyncAt = Date()

        Task { @MainActor in
            let syncedAnyActiveDay = await appStore.syncRecentHealthActivitySnapshots(days: 30)
            guard syncedAnyActiveDay else { return }
            scheduleBadgeCelebrationCheckAfterSave(
                preferredCategory: .health,
                delayNanoseconds: 900_000_000
            )
        }
    }

    func runBadgeCelebrationCheckAfterSave(
        preferredCategory: BadgeDefinition.Category? = nil,
        retryCount: Int = 0
    ) async {
        guard appStore.configuration.progressFeatureEnabled else { return }
        guard triggeredBadgeAchievement == nil else { return }

        if badgeCelebrationPresentationIsBlocked {
            guard retryCount < 20 else { return }
            scheduleBadgeCelebrationCheckAfterSave(
                preferredCategory: preferredCategory,
                delayNanoseconds: 1_500_000_000,
                retryCount: retryCount + 1
            )
            return
        }

        if let lastBadgeCelebrationCheckAt,
           Date().timeIntervalSince(lastBadgeCelebrationCheckAt) < 2 {
            guard retryCount < 20 else { return }
            scheduleBadgeCelebrationCheckAfterSave(
                preferredCategory: preferredCategory,
                delayNanoseconds: 1_000_000_000,
                retryCount: retryCount + 1
            )
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
                currentStreakDays: streakResponse.currentDays,
                preferredCategory: preferredCategory
            ) {
                triggeredBadgeAchievement = badge
            }
        } catch {
            // Badge celebrations are non-critical. Logging must never feel
            // slower or broken because this lightweight reward check failed.
        }
    }

    private var badgeCelebrationPresentationIsBlocked: Bool {
        hydrationAmountPrompt != nil ||
            isHydrationGoalPromptPresented ||
            isDetailsDrawerPresented ||
            selectedRowDetails != nil ||
            isStreakDrawerPresented ||
            isBadgesTrophyCasePresented ||
            saveMealDraft != nil ||
            isProfilePresented ||
            isNutritionSummaryPresented ||
            isProgressChartsPresented ||
            isSavedMealsPresented ||
            isRecipesPresented ||
            isFoodStoryPresented ||
            isLoggingTipsPresented ||
            isLoggingTipsPromptPresented ||
            isHomeTutorialPresented ||
            isDaySwipeTutorialPresented ||
            isCalendarPresented ||
            isImagePickerPresented ||
            isCustomCameraPresented ||
            isCameraAnalysisSheetPresented ||
            isCameraAnalysisSheetPresentedOverCover
    }
}
