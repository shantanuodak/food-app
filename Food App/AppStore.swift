import Foundation
import Combine
import UserNotifications
import UIKit

@MainActor
final class AppStore: ObservableObject {
    @Published var isOnboardingComplete: Bool
    @Published var lastAPIError: String?
    @Published var isNetworkReachable: Bool
    @Published var networkQualityHint: String
    @Published var isHealthSyncEnabled: Bool
    @Published private(set) var healthAuthorizationState: HealthAuthorizationState
    @Published private(set) var todaySteps: Double = 0
    @Published private(set) var todayActiveEnergy: Double = 0
    /// True once the stored session has been validated/refreshed (or confirmed absent).
    /// Data fetching that requires auth should wait for this before proceeding.
    @Published private(set) var isSessionRestored: Bool = false

    /// The "biggest challenge" the user picked in onboarding. Drives whether
    /// challenge-specific nudges (notifications) and in-app sheets fire.
    /// iOS-local only — not sent to backend in MVP.
    @Published private(set) var selectedChallenge: ChallengeChoice?

    /// Cached system notification authorization status. Used by the
    /// `NotificationScheduler` to short-circuit cleanly when permission isn't granted.
    @Published private(set) var notificationAuthState: UNAuthorizationStatus = .notDetermined
    @Published private(set) var mealReminderSettings: MealReminderSettings
    @Published private(set) var profileDashboardSnapshot: ProfileDashboardSnapshot? = nil
    @Published private(set) var progressChartsSnapshot: ProgressChartsSnapshot? = nil
    @Published private(set) var cachedFoodLogStreak: Int?

    let configuration: AppConfiguration
    let authSessionStore: AuthSessionStore
    let authService: AuthService
    let apiClient: APIClient
    let imageStorageService: ImageStorageService
    let healthKitService: HealthKitService
    let notificationScheduler: NotificationScheduler
    /// Persistent backup for photo bytes that couldn't be uploaded inline
    /// during save. Drained on launch and whenever auth becomes valid.
    /// Optional because instantiation can fail if the file system is
    /// unwritable; in that case we degrade to in-memory-only behavior.
    let deferredImageUploadStore: DeferredImageUploadStore?

    private let defaults: UserDefaults
    private let onboardingKey = "app.onboarding.completed"
    private let healthSyncKey = "app.health.sync.enabled.v1"
    private let challengeKey = "app.challenge.choice.v1"
    private let mealReminderSettingsKey = "app.meal.reminder.settings.v1"
    private let cachedFoodLogStreakKey = "app.rewards.current_food_log_streak.v1"
    private let todayHasLoggedFoodKey = "app.notifications.today.has_logged_food.v1"
    private let todayHasLoggedFoodDateKey = "app.notifications.today.has_logged_food.date.v1"
    private let apnsDeviceTokenKey = "app.notifications.apns_token.v1"
    private let networkMonitor: NetworkStatusMonitor
    private var onboardingProfileRefreshTask: Task<Void, Never>?
    private var profileDashboardPreloadTask: Task<Void, Never>?
    private var progressChartsPreloadTask: Task<Void, Never>?
    private var progressChartsPreloadRange: ProgressRange?
    private var progressChartsPreloadIncludesHealthSamples = false
    private var cancellables = Set<AnyCancellable>()

    init(
        configuration: AppConfiguration? = nil,
        defaults: UserDefaults = .standard
    ) {
        let resolvedConfiguration = configuration ?? AppConfiguration.live()
        // The live app uses the process-wide shared AuthService/AuthSessionStore
        // so the main app, Siri, notifications, and QuickCamera all share ONE
        // SupabaseClient and ONE in-memory session (see LiveAPIClientFactory).
        // Tests/previews that inject a custom configuration get isolated
        // instances so they never touch the real keychain session.
        let sessionStore: AuthSessionStore
        let authService: AuthService
        if configuration == nil {
            sessionStore = AuthSessionStore.shared
            authService = AuthService.shared
        } else {
            sessionStore = AuthSessionStore()
            authService = AuthService(
                sessionStore: sessionStore,
                fallbackToken: resolvedConfiguration.authToken,
                googleClientID: resolvedConfiguration.googleClientID,
                googleServerClientID: resolvedConfiguration.googleServerClientID,
                supabaseURL: resolvedConfiguration.supabaseURL,
                supabaseAnonKey: resolvedConfiguration.supabaseAnonKey
            )
        }
        self.configuration = resolvedConfiguration
        self.authSessionStore = sessionStore
        self.authService = authService
        self.apiClient = APIClient(
            configuration: resolvedConfiguration,
            authTokenProvider: {
                try await authService.validAccessToken()
            },
            authRecoveryHandler: {
                await authService.handleUnauthorizedAndAttemptRecovery()
            }
        )
        self.imageStorageService = ImageStorageService(
            configuration: resolvedConfiguration,
            authTokenProvider: {
                try await authService.validAccessToken()
            }
        )
        do {
            self.deferredImageUploadStore = try DeferredImageUploadStore()
        } catch {
            NSLog("[AppStore] DeferredImageUploadStore init failed; in-memory retries only: \(error)")
            self.deferredImageUploadStore = nil
        }
        let healthKitService = HealthKitService()
        self.healthKitService = healthKitService
        self.defaults = defaults
        self.networkMonitor = NetworkStatusMonitor()
        self.notificationScheduler = NotificationScheduler()
        self.isOnboardingComplete = defaults.bool(forKey: onboardingKey)
        self.isNetworkReachable = true
        self.networkQualityHint = L10n.networkOnline
        self.healthAuthorizationState = healthKitService.authorizationState
        self.mealReminderSettings = Self.loadMealReminderSettings(defaults: defaults, key: mealReminderSettingsKey)
        let cachedStreak = defaults.integer(forKey: cachedFoodLogStreakKey)
        self.cachedFoodLogStreak = defaults.object(forKey: cachedFoodLogStreakKey) == nil ? nil : cachedStreak
        self.isHealthSyncEnabled = defaults.bool(forKey: healthSyncKey)
        if healthAuthorizationState != .authorized && isHealthSyncEnabled {
            self.isHealthSyncEnabled = false
            defaults.set(false, forKey: healthSyncKey)
        }
        if let storedChallenge = defaults.string(forKey: challengeKey),
           let resolved = ChallengeChoice(rawValue: storedChallenge) {
            self.selectedChallenge = resolved
        }

        AuthDiagnosticTelemetry.shared.emit(
            eventName: "app_launch_auth_state",
            session: sessionStore.session,
            details: launchAuthDiagnosticDetails(sessionStore: sessionStore)
        )

        networkMonitor.$isReachable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reachable in
                guard let self else { return }
                self.isNetworkReachable = reachable
                if !reachable {
                    self.networkQualityHint = L10n.networkOffline
                } else if self.networkMonitor.isConstrained || self.networkMonitor.isExpensive {
                    self.networkQualityHint = L10n.networkLimited
                } else {
                    self.networkQualityHint = L10n.networkOnline
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .nutritionProgressDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recordTodayLogState(hasLogs: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .apnsDeviceTokenDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let token = notification.userInfo?["token"] as? String else { return }
                self?.recordAPNsDeviceToken(token)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recoverSessionAfterTransientKeychainLoad(reason: "didBecomeActive")
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recoverSessionAfterTransientKeychainLoad(reason: "protectedDataAvailable")
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(networkMonitor.$isConstrained, networkMonitor.$isExpensive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] constrained, expensive in
                guard let self else { return }
                guard self.isNetworkReachable else {
                    self.networkQualityHint = L10n.networkOffline
                    return
                }
                if constrained || expensive {
                    self.networkQualityHint = L10n.networkLimited
                } else {
                    self.networkQualityHint = L10n.networkOnline
                }
            }
            .store(in: &cancellables)

        healthKitService.$authorizationState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.healthAuthorizationState = state
                if state != .authorized, self.isHealthSyncEnabled {
                    self.setHealthSyncEnabled(false)
                }
            }
            .store(in: &cancellables)

        if sessionStore.session?.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            Task { [authService, weak self] in
                AuthDiagnosticTelemetry.shared.emit(
                    eventName: "session_restore_started",
                    session: self?.authSessionStore.session,
                    details: ["path": "refresh_or_set_session"]
                )
                await authService.restoreSessionIfPossible()
                await self?.repairOnboardingCompletionFromBackendIfNeeded()
                await MainActor.run {
                    self?.isSessionRestored = true
                    self?.scheduleLaunchOnboardingProfileRefreshIfNeeded()
                    self?.syncNotificationsWithBackend()
                }
                AuthDiagnosticTelemetry.shared.emit(
                    eventName: "session_restore_finished",
                    session: self?.authSessionStore.session,
                    details: ["hasStoredSessionAfter": String(self?.authSessionStore.session != nil)]
                )
                await self?.flushAuthDiagnostics()
            }
        } else {
            if sessionStore.session != nil {
                Task { [weak self] in
                    AuthDiagnosticTelemetry.shared.emit(
                        eventName: "session_restore_started",
                        session: self?.authSessionStore.session,
                        details: ["path": "stored_session_without_refresh_token"]
                    )
                    await self?.repairOnboardingCompletionFromBackendIfNeeded()
                    await MainActor.run {
                        self?.isSessionRestored = true
                        self?.scheduleLaunchOnboardingProfileRefreshIfNeeded()
                        self?.syncNotificationsWithBackend()
                    }
                    AuthDiagnosticTelemetry.shared.emit(
                        eventName: "session_restore_finished",
                        session: self?.authSessionStore.session,
                        details: ["hasStoredSessionAfter": String(self?.authSessionStore.session != nil)]
                    )
                    await self?.flushAuthDiagnostics()
                }
            } else {
                isSessionRestored = true
            }
        }
    }

    func markOnboardingComplete() {
        isOnboardingComplete = true
        defaults.set(true, forKey: onboardingKey)
    }

    func flushAuthDiagnostics() async {
        guard authSessionStore.session != nil else { return }
        await AuthDiagnosticTelemetry.shared.flush(apiClient: apiClient)
    }

    func resetOnboarding() {
        isOnboardingComplete = false
        defaults.set(false, forKey: onboardingKey)
        OnboardingPersistence.clear(defaults: defaults)
    }

    func signOut() {
        onboardingProfileRefreshTask?.cancel()
        onboardingProfileRefreshTask = nil
        profileDashboardPreloadTask?.cancel()
        profileDashboardPreloadTask = nil
        progressChartsPreloadTask?.cancel()
        progressChartsPreloadTask = nil
        progressChartsPreloadRange = nil
        progressChartsPreloadIncludesHealthSamples = false
        profileDashboardSnapshot = nil
        progressChartsSnapshot = nil
        authService.signOut()
        isOnboardingComplete = false
        defaults.set(false, forKey: onboardingKey)
        OnboardingPersistence.clear(defaults: defaults)
        HomePendingSaveStore.clear(defaults: defaults)
        notificationScheduler.cancelAll()
        selectedChallenge = nil
        defaults.removeObject(forKey: challengeKey)
        lastAPIError = nil
    }

    func refreshOnboardingCompletionFromBackend() async {
        do {
            let profile = try await apiClient.getOnboardingProfile()
            let draft = OnboardingDraft(profile: profile, accountProvider: authSessionStore.session?.provider)
            OnboardingPersistence.save(draft: draft, route: .ready, defaults: defaults)
            markOnboardingComplete()
        } catch {
            if Self.isNotFound(error) {
                // Only trust a backend 404 if this device has never marked
                // onboarding complete locally. For users who already finished
                // onboarding on this device, a 404 most likely means the
                // GET /v1/onboarding route isn't deployed yet — don't bounce
                // them back to the welcome screen.
                if !isOnboardingComplete {
                    defaults.set(false, forKey: onboardingKey)
                }
                return
            }
            // Do not sign the user out on a launch-time profile fetch.
            // Render cold-starts and transient network errors must not wipe
            // the session; real auth failures will surface on the next
            // user-driven request and be handled there.
        }
    }

    private func scheduleLaunchOnboardingProfileRefreshIfNeeded() {
        guard authSessionStore.session != nil else { return }

        onboardingProfileRefreshTask?.cancel()
        onboardingProfileRefreshTask = Task { [weak self] in
            guard let self else { return }

            // If this device already knows onboarding is complete, the
            // profile sync is useful but not urgent for first paint. Give
            // the home screen a short head start so sign-in feels faster.
            if self.isOnboardingComplete {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }

            guard !Task.isCancelled else { return }
            await self.refreshOnboardingCompletionFromBackend()
        }
    }

    private func launchAuthDiagnosticDetails(sessionStore: AuthSessionStore) -> [String: String] {
        let session = sessionStore.session
        return [
            "keychainLoadStatus": sessionStore.lastLoadStatus,
            "hasStoredSession": String(session != nil),
            "hasRefreshToken": String(session?.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false),
            "hasAccessToken": String(session?.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false),
            "localOnboardingComplete": String(isOnboardingComplete),
            "selectedChallengePresent": String(selectedChallenge != nil)
        ]
    }

    @discardableResult
    private func recoverSessionAfterTransientKeychainLoad(reason: String) -> Bool {
        guard authSessionStore.shouldRetryTransientLoadFailure else { return false }

        let previousLoadStatus = authSessionStore.lastLoadStatus
        guard authSessionStore.reloadSessionFromKeychain() != nil else {
            AuthDiagnosticTelemetry.shared.emit(
                eventName: "keychain_retry_failed",
                userIdHint: nil,
                provider: nil,
                details: [
                    "reason": reason,
                    "previousLoadStatus": previousLoadStatus,
                    "newLoadStatus": authSessionStore.lastLoadStatus,
                    "localOnboardingComplete": String(isOnboardingComplete)
                ]
            )
            return false
        }

        AuthDiagnosticTelemetry.shared.emit(
            eventName: "keychain_retry_recovered_session",
            session: authSessionStore.session,
            details: [
                "reason": reason,
                "previousLoadStatus": previousLoadStatus,
                "newLoadStatus": authSessionStore.lastLoadStatus,
                "localOnboardingComplete": String(isOnboardingComplete)
            ]
        )

        isSessionRestored = false
        Task { [authService, weak self] in
            AuthDiagnosticTelemetry.shared.emit(
                eventName: "session_restore_started",
                session: self?.authSessionStore.session,
                details: ["path": "keychain_retry_\(reason)"]
            )
            await authService.restoreSessionIfPossible()
            await self?.repairOnboardingCompletionFromBackendIfNeeded()
            await MainActor.run {
                self?.isSessionRestored = true
                self?.scheduleLaunchOnboardingProfileRefreshIfNeeded()
                self?.syncNotificationsWithBackend()
            }
            AuthDiagnosticTelemetry.shared.emit(
                eventName: "session_restore_finished",
                session: self?.authSessionStore.session,
                details: ["hasStoredSessionAfter": String(self?.authSessionStore.session != nil)]
            )
            await self?.flushAuthDiagnostics()
        }
        return true
    }

    private func repairOnboardingCompletionFromBackendIfNeeded() async {
        guard authSessionStore.session != nil, !isOnboardingComplete else { return }
        AuthDiagnosticTelemetry.shared.emit(
            eventName: "onboarding_completion_repair_started",
            session: authSessionStore.session,
            details: ["localOnboardingComplete": String(isOnboardingComplete)]
        )
        do {
            let profile = try await apiClient.getOnboardingProfile()
            let draft = OnboardingDraft(profile: profile, accountProvider: authSessionStore.session?.provider)
            OnboardingPersistence.save(draft: draft, route: .ready, defaults: defaults)
            markOnboardingComplete()
            AuthDiagnosticTelemetry.shared.emit(
                eventName: "onboarding_completion_repair_succeeded",
                session: authSessionStore.session,
                details: ["localOnboardingComplete": String(isOnboardingComplete)]
            )
        } catch {
            let outcome = Self.isNotFound(error) ? "not_found" : "failed"
            AuthDiagnosticTelemetry.shared.emit(
                eventName: "onboarding_completion_repair_\(outcome)",
                session: authSessionStore.session,
                details: [
                    "localOnboardingComplete": String(isOnboardingComplete),
                    "error": error.localizedDescription
                ]
            )
        }
    }

    func setError(_ message: String?) {
        lastAPIError = message
    }

    func handleAuthFailureIfNeeded(_ error: Error) -> Bool {
        guard let apiError = error as? APIClientError else {
            return false
        }
        if case .missingAuthToken = apiError, authSessionStore.session != nil {
            return false
        }
        guard apiError.isAuthTokenError() else {
            return false
        }

        // Do not let transient backend auth/JWKS/cold-start issues eject a
        // valid local session. AuthService clears the stored session only when
        // refresh recovery proves the token is invalid/revoked; until then,
        // keep the user in-app and let the next request retry recovery.
        if authSessionStore.session != nil {
            NSLog("[Auth] Suppressed sign-out for recoverable API auth error: \(apiError.localizedDescription)")
            return false
        }

        if authSessionStore.shouldRetryTransientLoadFailure {
            let recoveredSession = recoverSessionAfterTransientKeychainLoad(reason: "auth_failure")
            if recoveredSession || authSessionStore.shouldRetryTransientLoadFailure {
                NSLog("[Auth] Suppressed sign-out after transient keychain load failure.")
                return false
            }
        }

        if authSessionStore.session != nil {
            return false
        }

        signOut()
        return true
    }

    func warmBackend() {
        Task(priority: .background) { [apiClient] in
            await apiClient.warmHealth()
        }
    }

    func performBackgroundHomeRefresh() async -> Bool {
        guard isSessionRestored, isOnboardingComplete, authSessionStore.session != nil else { return false }
        guard isNetworkReachable else { return false }

        let calendar = Calendar.current
        let today = Date()
        let formatter = HomeLoggingDateUtils.summaryRequestFormatter
        let todayString = formatter.string(from: today)
        let fromDate = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        let fromString = formatter.string(from: fromDate)

        do {
            async let rangeTask = apiClient.getDayRange(from: fromString, to: todayString)
            async let notificationTask: Void = reconcileNotifications()
            async let uploadTask: Void = drainDeferredImageUploads()

            let range = try await rangeTask
            for summary in range.summaries {
                HomeDaySummaryDiskCache.persist(summary, date: summary.date, defaults: defaults)
                if summary.date == todayString {
                    WidgetDailyCaloriesStore.saveToday(summary: summary, dateString: summary.date)
                }
            }
            for logs in range.logs {
                HomeDayLogsDiskCache.persist(logs, date: logs.date, defaults: defaults)
                if logs.date == todayString {
                    recordTodayLogState(hasLogs: !logs.logs.isEmpty)
                }
            }

            _ = await (notificationTask, uploadTask)
            NSLog("[background_refresh] completed from=%@ to=%@", fromString, todayString)
            return true
        } catch {
            NSLog("[background_refresh] failed %@", error.localizedDescription)
            return false
        }
    }

    func preloadProfileDashboard(force: Bool = false) {
        guard isSessionRestored, isOnboardingComplete, authSessionStore.session != nil else { return }
        guard isNetworkReachable else { return }

        let today = Date()
        let dateString = HomeLoggingDateUtils.summaryRequestFormatter.string(from: today)
        let timezone = TimeZone.current.identifier

        if !force,
           let snapshot = profileDashboardSnapshot,
           snapshot.isUsable(for: dateString, timezone: timezone) {
            return
        }

        if profileDashboardPreloadTask != nil, !force {
            return
        }

        profileDashboardPreloadTask?.cancel()
        profileDashboardPreloadTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            await self.refreshProfileDashboardSnapshot(date: today, timezone: timezone)
            await MainActor.run {
                self.profileDashboardPreloadTask = nil
            }
        }
    }

    func refreshProfileDashboardSnapshot(date: Date = Date(), timezone: String = TimeZone.current.identifier) async {
        guard isSessionRestored, isOnboardingComplete, authSessionStore.session != nil else { return }
        guard isNetworkReachable else { return }

        let dateString = HomeLoggingDateUtils.summaryRequestFormatter.string(from: date)
        let weekStartDate = Calendar.current.date(byAdding: .day, value: -6, to: date) ?? date
        let weekStartString = HomeLoggingDateUtils.summaryRequestFormatter.string(from: weekStartDate)

        async let profileTask = apiClient.getOnboardingProfile()
        async let summaryTask = apiClient.getDaySummary(date: dateString, timezone: timezone)
        async let logsTask = apiClient.getDayLogs(date: dateString, timezone: timezone)
        async let progressTask = apiClient.getProgress(from: weekStartString, to: dateString, timezone: timezone)
        async let streaksTask = apiClient.getStreaks(range: 30, to: dateString, timezone: timezone)

        let profileResult = try? await profileTask
        let summaryResult = try? await summaryTask
        let logsResult = try? await logsTask
        let progressResult = try? await progressTask
        let streaksResult = try? await streaksTask

        if Task.isCancelled { return }
        if let streaksResult {
            recordFoodLogStreak(streaksResult.currentDays)
        }

        let previous = profileDashboardSnapshot
        profileDashboardSnapshot = ProfileDashboardSnapshot(
            profile: profileResult ?? previous?.profile,
            daySummary: summaryResult ?? previous?.daySummary,
            todayLogsCount: logsResult?.logs.count ?? previous?.todayLogsCount,
            progress: progressResult ?? previous?.progress,
            streaks: streaksResult ?? previous?.streaks,
            dateString: dateString,
            timezone: timezone,
            loadedAt: Date()
        )
    }

    func preloadProgressCharts(
        range: ProgressRange = .week,
        force: Bool = false,
        includeHealthSamples: Bool = true
    ) {
        guard configuration.progressFeatureEnabled else { return }
        guard isSessionRestored, isOnboardingComplete, authSessionStore.session != nil else { return }
        guard isNetworkReachable else { return }

        let timezone = TimeZone.current.identifier
        if !force,
           let snapshot = progressChartsSnapshot,
           snapshot.isUsable(
               for: range,
               timezone: timezone,
               requiringHealthSamples: includeHealthSamples
           ) {
            return
        }

        if let existingTask = progressChartsPreloadTask, !force {
            if progressChartsPreloadRange == range,
               progressChartsPreloadIncludesHealthSamples || !includeHealthSamples {
                return
            }
            existingTask.cancel()
            progressChartsPreloadTask = nil
            progressChartsPreloadRange = nil
            progressChartsPreloadIncludesHealthSamples = false
        }

        progressChartsPreloadTask?.cancel()
        progressChartsPreloadRange = range
        progressChartsPreloadIncludesHealthSamples = includeHealthSamples
        progressChartsPreloadTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            await self.refreshProgressChartsSnapshot(
                range: range,
                timezone: timezone,
                includeHealthSamples: includeHealthSamples
            )
            await MainActor.run {
                if self.progressChartsPreloadRange == range,
                   self.progressChartsPreloadIncludesHealthSamples == includeHealthSamples {
                    self.progressChartsPreloadTask = nil
                    self.progressChartsPreloadRange = nil
                    self.progressChartsPreloadIncludesHealthSamples = false
                }
            }
        }
    }

    func waitForProgressChartsPreload(range: ProgressRange) async {
        guard progressChartsPreloadRange == range,
              let task = progressChartsPreloadTask
        else {
            return
        }
        await task.value
    }

    func refreshProgressChartsSnapshot(
        range: ProgressRange = .week,
        timezone: String = TimeZone.current.identifier,
        includeHealthSamples: Bool = true
    ) async {
        guard configuration.progressFeatureEnabled else { return }
        guard isSessionRestored, isOnboardingComplete, authSessionStore.session != nil else { return }
        guard isNetworkReachable else { return }

        let bounds = Self.progressChartDateBounds(for: range)
        let progressResult = try? await apiClient.getProgress(
            from: bounds.from,
            to: bounds.to,
            timezone: timezone
        )

        var weightSamples: [BodyMassSample] = []
        var stepsSamples: [DailyStepCount] = []
        if includeHealthSamples, healthAuthorizationState == .authorized && isHealthSyncEnabled {
            weightSamples = (try? await fetchBodyMassSamples(from: bounds.startDate, to: bounds.endDate.addingTimeInterval(86_399))) ?? []
            stepsSamples = (try? await fetchStepCountsByDay(from: bounds.startDate, to: bounds.endDate.addingTimeInterval(86_399))) ?? []
        }

        if Task.isCancelled { return }

        let fallbackProgress = progressChartsSnapshot?.range == range ? progressChartsSnapshot?.progress : nil
        progressChartsSnapshot = ProgressChartsSnapshot(
            range: range,
            progress: progressResult ?? fallbackProgress,
            weightSamples: weightSamples,
            stepsSamples: stepsSamples,
            includesHealthSamples: includeHealthSamples,
            preferredUnits: OnboardingPersistence.load(defaults: defaults)?.draft.units ?? .imperial,
            startDate: bounds.startDate,
            endDate: bounds.endDate,
            from: bounds.from,
            to: bounds.to,
            timezone: timezone,
            loadedAt: Date()
        )
    }

    private static func progressChartDateBounds(for range: ProgressRange, date: Date = Date()) -> (startDate: Date, endDate: Date, from: String, to: String) {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: date)
        let offset = max(0, range.rawValue - 1)
        let startDate = calendar.date(byAdding: .day, value: -offset, to: endDate) ?? endDate
        return (
            startDate: startDate,
            endDate: endDate,
            from: HomeLoggingDateUtils.summaryRequestFormatter.string(from: startDate),
            to: HomeLoggingDateUtils.summaryRequestFormatter.string(from: endDate)
        )
    }

    func refreshHealthAuthorizationState() {
        healthKitService.refreshAuthorizationState()
    }

    func requestAppleHealthAccess() async throws -> Bool {
        let granted = try await healthKitService.requestNutritionAuthorization()
        healthAuthorizationState = healthKitService.authorizationState
        setHealthSyncEnabled(granted)
        return granted
    }

    func disconnectAppleHealth() {
        setHealthSyncEnabled(false)
    }

    func setHealthSyncEnabled(_ enabled: Bool) {
        let effective = enabled && healthAuthorizationState == .authorized
        isHealthSyncEnabled = effective
        defaults.set(effective, forKey: healthSyncKey)
    }

    /// Persists the user's challenge choice and re-runs notification scheduling.
    /// Call from onboarding completion, profile edits, etc.
    func setSelectedChallenge(_ challenge: ChallengeChoice?) {
        selectedChallenge = challenge
        if let raw = challenge?.rawValue {
            defaults.set(raw, forKey: challengeKey)
        } else {
            defaults.removeObject(forKey: challengeKey)
        }
        Task { await reconcileNotifications() }
    }

    func setMealReminderSettings(_ settings: MealReminderSettings) {
        mealReminderSettings = settings
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: mealReminderSettingsKey)
        }
        Task {
            await reconcileNotifications()
            await syncNotificationPreferencesToBackend()
        }
    }

    func setMealRemindersEnabled(_ enabled: Bool) {
        var settings = mealReminderSettings
        settings.remindersEnabled = enabled

        if enabled,
           !settings.breakfastEnabled,
           !settings.lunchEnabled,
           !settings.dinnerEnabled {
            settings.breakfastEnabled = true
            settings.lunchEnabled = true
            settings.dinnerEnabled = true
        }

        setMealReminderSettings(settings)
    }

    /// Refresh the cached system notification authorization status from the OS.
    /// Cheap; safe to call on app launch and after the user toggles
    /// notifications inside iOS Settings.
    func refreshNotificationAuthState() async {
        notificationAuthState = await notificationScheduler.currentAuthorizationStatus()
        if notificationAuthState == .authorized || notificationAuthState == .provisional || notificationAuthState == .ephemeral {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Ask the user for notification permission via the system prompt.
    /// Returns the resolved status.
    @discardableResult
    func requestNotificationAuthorization() async -> UNAuthorizationStatus {
        let status = await notificationScheduler.requestAuthorization()
        notificationAuthState = status
        if status == .authorized || status == .provisional || status == .ephemeral {
            UIApplication.shared.registerForRemoteNotifications()
        }
        await reconcileNotifications()
        await syncNotificationPreferencesToBackend()
        return status
    }

    /// Drain any photo uploads that were stashed to disk by the
    /// "decoupled image upload" save path but never finished — e.g.
    /// because the user force-quit the app between save success and the
    /// background upload firing. Each entry's food_log row is already
    /// saved on the server; we just need to attach the photo via the
    /// lightweight `PATCH /v1/logs/:id/image-ref` route.
    ///
    /// Safe to call repeatedly: `drain()` is destructive and entries
    /// only re-enqueue if a new save's inline upload also fails. Bails
    /// early if there's no auth — no point trying without a Supabase
    /// session, and the entries stay on disk for the next attempt.
    func drainDeferredImageUploads() async {
        guard let store = deferredImageUploadStore else { return }
        guard authSessionStore.session != nil else { return }
        let pendingCount = await store.pendingCount()
        guard pendingCount > 0 else { return }
        if pendingCount > 3, networkMonitor.isExpensive || networkMonitor.isConstrained {
            NSLog("[AppStore] Skipping \(pendingCount) deferred image upload(s) on constrained/expensive network")
            return
        }

        let startedAt = Date()
        let entries = await store.drain()
        guard !entries.isEmpty else {
            NSLog("[AppStore] Deferred image upload drain empty in \(Int(Date().timeIntervalSince(startedAt) * 1000))ms")
            return
        }
        NSLog("[AppStore] Draining \(entries.count) deferred image upload(s)")

        let storage = imageStorageService
        let api = apiClient
        let userIDHint = authSessionStore.session?.userID

        // Re-enqueue helper closure that goes through the actor — needed
        // when a single drained entry's retry fails so it survives to the
        // next launch.
        let reenqueue: (String, Data) async -> Void = { logId, data in
            await store.enqueue(logId: logId, imageData: data)
        }

        for (offset, entry) in entries.enumerated() {
            do {
                let imageRef = try await storage.uploadJPEG(entry.imageData, userIdentifierHint: userIDHint)
                _ = try await api.updateLogImageRef(id: entry.logId, imageRef: imageRef)
                NSLog("[AppStore] Drained deferred image upload for log \(entry.logId)")
            } catch {
                NSLog("[AppStore] Drain retry failed for log \(entry.logId); re-enqueueing remaining \(entries.count - offset): \(error)")
                // Drain is destructive — disk store is empty now. Put
                // every still-unprocessed entry back so they survive to
                // the next launch. Stop trying further uploads in this
                // pass: if storage is broken, the rest will fail too and
                // burn battery / data for nothing.
                for unprocessed in entries[offset...] {
                    await reenqueue(unprocessed.logId, unprocessed.imageData)
                }
                break
            }
        }
        NSLog("[AppStore] Deferred image upload drain finished in \(Int(Date().timeIntervalSince(startedAt) * 1000))ms")
    }

    /// Idempotent — cancels stale requests, schedules per-challenge nudges
    /// based on current state.
    func reconcileNotifications() async {
        await notificationScheduler.reconcile(
            challenge: selectedChallenge,
            authState: notificationAuthState,
            mealReminders: mealReminderSettings,
            hasLoggedToday: todayHasLoggedFood
        )
    }

    func syncNotificationsWithBackend() {
        Task {
            await syncNotificationDeviceToBackend()
            await syncNotificationPreferencesToBackend()
        }
    }

    private func recordAPNsDeviceToken(_ token: String) {
        defaults.set(token, forKey: apnsDeviceTokenKey)
        Task { await syncNotificationDeviceToBackend() }
    }

    private func syncNotificationDeviceToBackend() async {
        guard authSessionStore.session != nil else { return }
        guard let token = defaults.string(forKey: apnsDeviceTokenKey), !token.isEmpty else { return }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let body = RegisterNotificationDeviceRequest(
            token: token,
            platform: "ios",
            environment: Self.apnsEnvironment,
            appVersion: appVersion,
            buildNumber: buildNumber,
            deviceModel: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion,
            locale: Locale.current.identifier
        )
        _ = try? await apiClient.registerNotificationDevice(body)
    }

    private func syncNotificationPreferencesToBackend() async {
        guard authSessionStore.session != nil else { return }
        let settings = mealReminderSettings
        let body = NotificationPreferencesRequest(
            timezone: TimeZone.current.identifier,
            remindersEnabled: settings.remindersEnabled,
            breakfastEnabled: settings.breakfastEnabled,
            lunchEnabled: settings.lunchEnabled,
            dinnerEnabled: settings.dinnerEnabled,
            breakfastStart: Self.apiTime(settings.breakfastStart),
            breakfastEnd: Self.apiTime(settings.breakfast),
            lunchStart: Self.apiTime(settings.lunchStart),
            lunchEnd: Self.apiTime(settings.lunch),
            dinnerStart: Self.apiTime(settings.dinnerStart),
            dinnerEnd: Self.apiTime(settings.dinner),
            eatingWindowEnabled: settings.eatingWindowEnabled,
            eatingWindowStart: Self.apiTime(settings.eatingWindowStart),
            eatingWindowEnd: Self.apiTime(settings.eatingWindowEnd),
            engagementEnabled: true,
            discoveryEnabled: true
        )
        _ = try? await apiClient.updateNotificationPreferences(body)
    }

    private static var apnsEnvironment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    private static func apiTime(_ time: MealReminderTime) -> String {
        "\(String(format: "%02d", time.hour)):\(String(format: "%02d", time.minute))"
    }

    func recordTodayLogState(hasLogs: Bool) {
        defaults.set(todayDateString, forKey: todayHasLoggedFoodDateKey)
        defaults.set(hasLogs, forKey: todayHasLoggedFoodKey)
        Task { await reconcileNotifications() }
    }

    func recordFoodLogStreak(_ days: Int) {
        let normalized = max(0, days)
        cachedFoodLogStreak = normalized
        defaults.set(normalized, forKey: cachedFoodLogStreakKey)
    }

    private var todayHasLoggedFood: Bool {
        guard defaults.string(forKey: todayHasLoggedFoodDateKey) == todayDateString else {
            return false
        }
        return defaults.bool(forKey: todayHasLoggedFoodKey)
    }

    private var todayDateString: String {
        HomeLoggingDateUtils.summaryRequestFormatter.string(from: Date())
    }

    func syncNutritionToAppleHealth(totals: NutritionTotals, loggedAt: Date, logId: String, healthWriteKey: String) async throws -> Bool {
        guard isHealthSyncEnabled else {
            return false
        }
        return try await healthKitService.writeNutritionTotals(
            totals,
            loggedAt: loggedAt,
            logId: logId,
            healthWriteKey: healthWriteKey
        )
    }

    func deleteNutritionFromAppleHealth(totals: NutritionTotals, loggedAt: Date, logId: String, healthWriteKey: String) async throws -> Bool {
        guard isHealthSyncEnabled else {
            return false
        }
        return try await healthKitService.deleteNutritionTotals(
            totals,
            loggedAt: loggedAt,
            logId: logId,
            healthWriteKey: healthWriteKey
        )
    }

    func fetchBodyMassSamples(from startDate: Date, to endDate: Date) async throws -> [BodyMassSample] {
        try await healthKitService.fetchBodyMassSamples(from: startDate, to: endDate)
    }

    func fetchStepCountsByDay(from startDate: Date, to endDate: Date) async throws -> [DailyStepCount] {
        try await healthKitService.fetchStepCountsByDay(from: startDate, to: endDate)
    }

    @discardableResult
    func refreshHealthActivity() async -> Bool {
        await syncRecentHealthActivitySnapshots(days: 1)
    }

    @discardableResult
    func syncRecentHealthActivitySnapshots(days: Int = 30) async -> Bool {
        guard isHealthSyncEnabled,
              healthAuthorizationState == .authorized,
              isSessionRestored,
              isNetworkReachable else { return false }

        do {
            let calendar = Calendar.current
            let dayCount = max(1, days)
            let today = Date()
            let endDate = today
            let startDate = calendar.date(
                byAdding: .day,
                value: -(dayCount - 1),
                to: calendar.startOfDay(for: today)
            ) ?? calendar.startOfDay(for: today)
            let stepSamples = try await healthKitService.fetchStepCountsByDay(from: startDate, to: endDate)
            let todayEnergy = try? await healthKitService.fetchTodayActiveEnergy()

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            var syncedAnyActiveDay = false

            for sample in stepSamples {
                let isToday = calendar.isDate(sample.date, inSameDayAs: today)
                let activeEnergy = isToday ? (todayEnergy ?? 0) : 0

                if isToday {
                    todaySteps = sample.steps
                    todayActiveEnergy = activeEnergy
                }

                guard sample.steps > 0 || activeEnergy > 0 else { continue }

                do {
                    let request = HealthActivityRequest(
                        date: formatter.string(from: sample.date),
                        steps: sample.steps,
                        activeEnergyKcal: activeEnergy
                    )
                    let snapshot = try await apiClient.postHealthActivity(request)
                    if snapshot.steps > 0 || snapshot.activeEnergyKcal > 0 {
                        syncedAnyActiveDay = true
                    }
                } catch is CancellationError {
                    return syncedAnyActiveDay
                } catch {
                    continue
                }
            }

            return syncedAnyActiveDay
        } catch {
            // Silently ignore read failures — card will show stale or zero values
            return false
        }
    }

    private static func isNotFound(_ error: Error) -> Bool {
        guard let apiError = error as? APIClientError else { return false }
        if case let .server(statusCode, payload) = apiError {
            return statusCode == 404 || payload.code == "ONBOARDING_NOT_FOUND"
        }
        return false
    }

    private static func loadMealReminderSettings(defaults: UserDefaults, key: String) -> MealReminderSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(MealReminderSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

}
