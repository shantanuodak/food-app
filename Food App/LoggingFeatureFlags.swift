import Foundation

enum LoggingFeatureFlags {
    private static let saveCoordinatorDefaultsKeys = [
        "feature.useSaveCoordinator",
        "use_save_coordinator"
    ]
    private static let parseCoordinatorDefaultsKeys = [
        "feature.useParseCoordinator",
        "use_parse_coordinator"
    ]
    private static let saveCoordinatorEnvKey = "USE_SAVE_COORDINATOR"
    private static let parseCoordinatorEnvKey = "USE_PARSE_COORDINATOR"

    static func useSaveCoordinator(
        defaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo
    ) -> Bool {
        if let override = processInfo.environment[saveCoordinatorEnvKey] {
            switch override.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                break
            }
        }
        for key in saveCoordinatorDefaultsKeys where defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return false
    }

    static func useParseCoordinator(
        defaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo
    ) -> Bool {
        if let override = processInfo.environment[parseCoordinatorEnvKey] {
            switch override.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                break
            }
        }
        for key in parseCoordinatorDefaultsKeys where defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return false
    }
}
