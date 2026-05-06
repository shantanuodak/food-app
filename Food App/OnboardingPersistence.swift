import Foundation

enum OnboardingPersistence {
    private static let draftKey = "app.onboarding.draft.v1"
    private static let routeKey = "app.onboarding.route.v1"

    static func save(draft: OnboardingDraft, route: OnboardingRoute, defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(draft) {
            defaults.set(data, forKey: draftKey)
        }
        defaults.set(route.rawValue, forKey: routeKey)
    }

    static func load(defaults: UserDefaults = .standard) -> (draft: OnboardingDraft, route: OnboardingRoute)? {
        let decoder = JSONDecoder()
        var draft: OnboardingDraft

        if let data = defaults.data(forKey: draftKey),
           let decoded = try? decoder.decode(OnboardingDraft.self, from: data) {
            draft = decoded
        } else {
            return nil
        }

        draft.migrateLegacyBaselineTouchStateIfNeeded()

        let routeRaw = defaults.integer(forKey: routeKey)
        let route = OnboardingRoute(rawValue: routeRaw) ?? .welcome
        return (draft, route)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: draftKey)
        defaults.removeObject(forKey: routeKey)
    }
}

