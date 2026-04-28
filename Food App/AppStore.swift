import Foundation
import Combine
import UserNotifications

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

    let configuration: AppConfiguration
    let authSessionStore: AuthSessionStore
    let authService: AuthService
    let apiClient: APIClient
    let imageStorageService: ImageStorageService
    let healthKitService: HealthKitService
    let notificationScheduler: NotificationScheduler

    private let defaults: UserDefaults
    private let onboardingKey = "app.onboarding.completed"
    private let healthSyncKey = "app.health.sync.enabled.v1"
    private let challengeKey = "app.challenge.choice.v1"
    private let mealReminderSettingsKey = "app.meal.reminder.settings.v1"
    private let networkMonitor: NetworkStatusMonitor
    private var cancellables = Set<AnyCancellable>()

    init(
        configuration: AppConfiguration? = nil,
        defaults: UserDefaults = .standard
    ) {
        let resolvedConfiguration = configuration ?? AppConfiguration.live()
        let sessionStore = AuthSessionStore()
        let authService = AuthService(
            sessionStore: sessionStore,
            fallbackToken: resolvedConfiguration.authToken,
            googleClientID: resolvedConfiguration.googleClientID,
            googleServerClientID: resolvedConfiguration.googleServerClientID,
            supabaseURL: resolvedConfiguration.supabaseURL,
            supabaseAnonKey: resolvedConfiguration.supabaseAnonKey
        )
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
        self.isHealthSyncEnabled = defaults.bool(forKey: healthSyncKey)
        if healthAuthorizationState != .authorized && isHealthSyncEnabled {
            self.isHealthSyncEnabled = false
            defaults.set(false, forKey: healthSyncKey)
        }
        if let storedChallenge = defaults.string(forKey: challengeKey),
           let resolved = ChallengeChoice(rawValue: storedChallenge) {
            self.selectedChallenge = resolved
        }

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
                await authService.restoreSessionIfPossible()
                await MainActor.run {
                    self?.isSessionRestored = true
                    Task { await self?.refreshOnboardingCompletionFromBackend() }
                }
            }
        } else {
            isSessionRestored = true
            if sessionStore.session != nil {
                Task { await refreshOnboardingCompletionFromBackend() }
            }
        }
    }

    func markOnboardingComplete() {
        isOnboardingComplete = true
        defaults.set(true, forKey: onboardingKey)
    }

    func resetOnboarding() {
        isOnboardingComplete = false
        defaults.set(false, forKey: onboardingKey)
        OnboardingPersistence.clear(defaults: defaults)
    }

    func signOut() {
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
        guard Self.isAuthTokenError(apiError) else {
            return false
        }
        signOut()
        return true
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
        Task { await reconcileNotifications() }
    }

    /// Refresh the cached system notification authorization status from the OS.
    /// Cheap; safe to call on app launch and after the user toggles
    /// notifications inside iOS Settings.
    func refreshNotificationAuthState() async {
        notificationAuthState = await notificationScheduler.currentAuthorizationStatus()
    }

    /// Ask the user for notification permission via the system prompt.
    /// Returns the resolved status.
    @discardableResult
    func requestNotificationAuthorization() async -> UNAuthorizationStatus {
        let status = await notificationScheduler.requestAuthorization()
        notificationAuthState = status
        await reconcileNotifications()
        return status
    }

    /// Idempotent — cancels stale requests, schedules per-challenge nudges
    /// based on current state.
    func reconcileNotifications() async {
        await notificationScheduler.reconcile(
            challenge: selectedChallenge,
            authState: notificationAuthState,
            mealReminders: mealReminderSettings
        )
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

    func refreshHealthActivity() async {
        guard isHealthSyncEnabled else { return }
        do {
            let steps = try await healthKitService.fetchTodayStepCount()
            let energy = try await healthKitService.fetchTodayActiveEnergy()
            todaySteps = steps
            todayActiveEnergy = energy

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let todayString = formatter.string(from: Date())
            let request = HealthActivityRequest(date: todayString, steps: steps, activeEnergyKcal: energy)
            _ = try? await apiClient.postHealthActivity(request)
        } catch {
            // Silently ignore read failures — card will show stale or zero values
        }
    }

    private static func isAuthTokenError(_ apiError: APIClientError) -> Bool {
        switch apiError {
        case .missingAuthToken:
            return true
        case let .server(statusCode, payload):
            if statusCode == 401 {
                return true
            }

            let code = payload.code.uppercased()
            if code == "UNAUTHORIZED" || code.contains("TOKEN") || code.contains("AUTH") {
                return true
            }

            let message = payload.message.lowercased()
            return message.contains("invalid token") ||
                message.contains("missing bearer token") ||
                message.contains("jwt") ||
                message.contains("unauthorized") ||
                message.contains("session expired")
        default:
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
