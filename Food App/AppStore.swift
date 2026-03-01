import Foundation
import Combine

@MainActor
final class AppStore: ObservableObject {
    @Published var isOnboardingComplete: Bool
    @Published var lastAPIError: String?
    @Published var isNetworkReachable: Bool
    @Published var networkQualityHint: String
    @Published var isHealthSyncEnabled: Bool
    @Published private(set) var healthAuthorizationState: HealthAuthorizationState

    let configuration: AppConfiguration
    let authSessionStore: AuthSessionStore
    let authService: AuthService
    let apiClient: APIClient
    let healthKitService: HealthKitService

    private let defaults: UserDefaults
    private let onboardingKey = "app.onboarding.completed"
    private let healthSyncKey = "app.health.sync.enabled.v1"
    private let networkMonitor: NetworkStatusMonitor
    private var cancellables = Set<AnyCancellable>()

    init(
        configuration: AppConfiguration? = nil,
        defaults: UserDefaults = .standard
    ) {
        let resolvedConfiguration = configuration ?? AppConfiguration.live()
        let sessionStore = AuthSessionStore()
        self.configuration = resolvedConfiguration
        self.authSessionStore = sessionStore
        self.authService = AuthService(
            sessionStore: sessionStore,
            fallbackToken: resolvedConfiguration.authToken,
            googleClientID: resolvedConfiguration.googleClientID,
            googleServerClientID: resolvedConfiguration.googleServerClientID,
            supabaseURL: resolvedConfiguration.supabaseURL,
            supabaseAnonKey: resolvedConfiguration.supabaseAnonKey
        )
        self.apiClient = APIClient(
            configuration: resolvedConfiguration,
            authTokenProvider: {
                let hasSupabaseConfig =
                    resolvedConfiguration.supabaseURL != nil &&
                    !(resolvedConfiguration.supabaseAnonKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

                if let rawAccessToken = sessionStore.session?.accessToken {
                    let accessToken = rawAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !accessToken.isEmpty {
                        if Self.isExpiredJWT(accessToken) {
                            sessionStore.clear()
                        } else if hasSupabaseConfig && accessToken.lowercased().hasPrefix("dev-") {
                            // In Supabase mode, ignore persisted dev placeholder tokens.
                        } else {
                            return accessToken
                        }
                    }
                }

                if hasSupabaseConfig {
                    return nil
                }

                return resolvedConfiguration.authToken
            }
        )
        let healthKitService = HealthKitService()
        self.healthKitService = healthKitService
        self.defaults = defaults
        self.networkMonitor = NetworkStatusMonitor()
        self.isOnboardingComplete = defaults.bool(forKey: onboardingKey)
        self.isNetworkReachable = true
        self.networkQualityHint = L10n.networkOnline
        self.healthAuthorizationState = healthKitService.authorizationState
        self.isHealthSyncEnabled = defaults.bool(forKey: healthSyncKey)
        if healthAuthorizationState != .authorized && isHealthSyncEnabled {
            self.isHealthSyncEnabled = false
            defaults.set(false, forKey: healthSyncKey)
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

    func setError(_ message: String?) {
        lastAPIError = message
    }

    func handleAuthFailureIfNeeded(_ error: Error) -> Bool {
        guard let apiError = error as? APIClientError else {
            return false
        }
        guard Self.isAuthTokenError(apiError) else {
            return false
        }
        authService.signOut()
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

    func syncNutritionToAppleHealth(totals: NutritionTotals, loggedAt: Date) async throws -> Bool {
        guard isHealthSyncEnabled else {
            return false
        }
        return try await healthKitService.writeNutritionTotals(totals, loggedAt: loggedAt)
    }

    func fetchBodyMassSamples(from startDate: Date, to endDate: Date) async throws -> [BodyMassSample] {
        try await healthKitService.fetchBodyMassSamples(from: startDate, to: endDate)
    }

    private static func isExpiredJWT(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            return false
        }

        guard let payloadData = decodeBase64URL(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: payloadData),
              let claims = object as? [String: Any],
              let exp = jwtExpiration(from: claims) else {
            // Malformed JWT payload should be treated as expired.
            return true
        }

        return Date().timeIntervalSince1970 >= exp
    }

    private static func jwtExpiration(from claims: [String: Any]) -> TimeInterval? {
        guard let rawExp = claims["exp"] else {
            return nil
        }

        if let number = rawExp as? NSNumber {
            return number.doubleValue
        }
        if let double = rawExp as? Double {
            return double
        }
        if let int = rawExp as? Int {
            return TimeInterval(int)
        }
        if let string = rawExp as? String {
            return Double(string)
        }
        return nil
    }

    private static func isAuthTokenError(_ apiError: APIClientError) -> Bool {
        switch apiError {
        case .missingAuthToken:
            return true
        case let .server(statusCode, payload):
            if statusCode == 401 || statusCode == 403 {
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

    private static func decodeBase64URL(_ input: String) -> Data? {
        let normalized = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingLength = (4 - normalized.count % 4) % 4
        let padded = normalized + String(repeating: "=", count: paddingLength)
        return Data(base64Encoded: padded)
    }
}
