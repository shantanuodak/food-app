import Foundation

enum AppEnvironment: String {
    case local
    case staging
    case production

    static func from(_ raw: String?) -> AppEnvironment {
        guard let raw else { return .local }
        return AppEnvironment(rawValue: raw.lowercased()) ?? .local
    }
}

struct AppConfiguration {
    let environment: AppEnvironment
    let baseURL: URL
    let authToken: String
    let googleClientID: String?
    let googleServerClientID: String?
    let supabaseURL: URL?
    let supabaseAnonKey: String?
    let supabaseStorageBucket: String
    let progressFeatureEnabled: Bool

    static func live(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> AppConfiguration {
        let bundleEnvironment = AppEnvironment.from(bundle.object(forInfoDictionaryKey: "APIEnvironment") as? String)
        let environmentOverride = AppEnvironment.from(processInfo.environment["APP_ENV"])
        let environment: AppEnvironment = processInfo.environment["APP_ENV"] == nil ? bundleEnvironment : environmentOverride

        let bundleBaseURL = (bundle.object(forInfoDictionaryKey: "APIBaseURL") as? String) ?? "http://localhost:8080"
        let overrideKey: String
        switch environment {
        case .local:
            overrideKey = "API_BASE_URL_LOCAL"
        case .staging:
            overrideKey = "API_BASE_URL_STAGING"
        case .production:
            overrideKey = "API_BASE_URL_PROD"
        }

        let resolvedBaseURL = processInfo.environment[overrideKey] ?? bundleBaseURL
        let baseURL = resolveBaseURL(from: resolvedBaseURL, environment: environment, processInfo: processInfo)

        let defaultToken = "dev-11111111-1111-1111-1111-111111111111"
        let authToken = processInfo.environment["API_AUTH_TOKEN"] ?? defaultToken

        let googleClientID = processInfo.environment["GOOGLE_CLIENT_ID"] ??
            (bundle.object(forInfoDictionaryKey: "GIDClientID") as? String)
        let googleServerClientID = processInfo.environment["GOOGLE_SERVER_CLIENT_ID"] ??
            (bundle.object(forInfoDictionaryKey: "GIDServerClientID") as? String)

        let supabaseURLString = processInfo.environment["SUPABASE_URL"] ??
            (bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String)
        let supabaseURL = supabaseURLString.flatMap(URL.init(string:))
        let supabaseAnonKey = processInfo.environment["SUPABASE_ANON_KEY"] ??
            (bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String)
        let supabaseStorageBucket =
            processInfo.environment["SUPABASE_STORAGE_BUCKET"] ??
            (bundle.object(forInfoDictionaryKey: "SupabaseStorageBucket") as? String) ??
            "food-images"
        let progressFeatureEnabled = resolveFeatureFlag(
            processOverride: processInfo.environment["PROGRESS_FEATURE_ENABLED"],
            bundleValue: bundle.object(forInfoDictionaryKey: "ProgressFeatureEnabled")
        )

        return AppConfiguration(
            environment: environment,
            baseURL: baseURL,
            authToken: authToken,
            googleClientID: googleClientID,
            googleServerClientID: googleServerClientID,
            supabaseURL: supabaseURL,
            supabaseAnonKey: supabaseAnonKey,
            supabaseStorageBucket: supabaseStorageBucket,
            progressFeatureEnabled: progressFeatureEnabled
        )
    }

    private static func resolveFeatureFlag(processOverride: String?, bundleValue: Any?) -> Bool {
        if let processOverride {
            switch processOverride.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                break
            }
        }

        if let bundleBool = bundleValue as? Bool {
            return bundleBool
        }
        if let bundleString = bundleValue as? String {
            switch bundleString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                break
            }
        }
        return true
    }

    private static func resolveBaseURL(from rawValue: String, environment: AppEnvironment, processInfo: ProcessInfo) -> URL {
        let fallbackURL = URL(string: "http://localhost:8080")!
        let resolved = URL(string: rawValue) ?? fallbackURL

#if targetEnvironment(simulator)
        if environment == .local {
            if let simulatorOverride = processInfo.environment["API_BASE_URL_SIMULATOR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !simulatorOverride.isEmpty,
               let simulatorURL = URL(string: simulatorOverride) {
                return simulatorURL
            }

            if shouldRewriteSimulatorHostToLocalhost(resolved.host),
               var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) {
                components.host = "localhost"
                return components.url ?? resolved
            }
        }
#endif

        return resolved
    }

    private static func shouldRewriteSimulatorHostToLocalhost(_ host: String?) -> Bool {
        guard let host else { return false }
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1" {
            return false
        }
        return isPrivateIPv4Host(normalized)
    }

    private static func isPrivateIPv4Host(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }

        var octets: [Int] = []
        octets.reserveCapacity(4)
        for part in parts {
            guard let value = Int(part), (0 ... 255).contains(value) else {
                return false
            }
            octets.append(value)
        }

        if octets[0] == 10 {
            return true
        }
        if octets[0] == 172, (16 ... 31).contains(octets[1]) {
            return true
        }
        if octets[0] == 192, octets[1] == 168 {
            return true
        }
        if octets[0] == 169, octets[1] == 254 {
            return true
        }
        return false
    }
}
