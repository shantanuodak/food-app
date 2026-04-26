import Foundation
import Combine
import SwiftUI

enum AppFlowRoute: Equatable {
    case onboarding
    case home
}

enum OnboardingRoute: Int, CaseIterable, Equatable, Hashable {
    case welcome = 1
    case goal = 2
    case age = 3
    case baseline = 4
    case activity = 5
    case pace = 6
    case preferencesOptional = 7
    case planPreview = 8
    case account = 9
    case permissions = 10
    case ready = 11
    case goalValidation = 12
    case socialProof = 13
    case challenge = 14
    case experience = 15
    case howItWorks = 16
    case challengeInsight = 17
    /// Notifications permission — split out from the original `.permissions`
    /// route (which is now Apple-Health-only). Sits immediately after it so
    /// the user is asked one decision per screen.
    case notificationsPermission = 18

    static let activeFlow: [OnboardingRoute] = [
        .welcome,
        .goal,
        .socialProof,
        .experience,
        .howItWorks,
        .challenge,
        .challengeInsight,
        .age,
        .baseline,
        .activity,
        .pace,
        // Preferences + allergies sit between pace and goalValidation:
        // they're the last bit of profile data we collect before showing
        // the user their plan, and the parse pipeline relies on the
        // allergies set to surface dietary-conflict flags.
        .preferencesOptional,
        .goalValidation,
        .account,
        // `.permissions` is Apple-Health-only; notifications are next.
        .permissions,
        .notificationsPermission,
        .ready
    ]

    static let debugRoutes: [OnboardingRoute] = activeFlow

    var frameID: String {
        switch self {
        case .welcome: return "Welcome"
        case .goal: return "Goal"
        case .age: return "Age"
        case .baseline: return "Baseline"
        case .activity: return "Activity"
        case .pace: return "Pace"
        case .goalValidation: return "Goal Validation"
        case .socialProof: return "Social Proof"
        case .challenge: return "Challenge"
        case .experience: return "Experience"
        case .howItWorks: return "How It Works"
        case .challengeInsight: return "Challenge Insight"
        case .preferencesOptional: return "Preferences"
        case .planPreview: return "Plan Preview"
        case .account: return "Account"
        case .permissions: return "Apple Health"
        case .notificationsPermission: return "Notifications"
        case .ready: return "Ready"
        }
    }

    var progressStep: Int? {
        switch self {
        case .goal: return 1
        case .age: return 2
        case .baseline: return 3
        case .activity: return 4
        case .pace: return 5
        case .goalValidation: return 6
        // .preferencesOptional intentionally has no progress step — the
        // redesigned screen is self-contained and doesn't render the
        // wrapper progress bar.
        default: return nil
        }
    }

    var hasBack: Bool {
        switch self {
        case .welcome:
            return false
        default:
            return true
        }
    }

    var previous: OnboardingRoute? {
        let flow = OnboardingRoute.activeFlow
        guard let index = flow.firstIndex(of: normalizedForActiveFlow),
              index > 0 else {
            return nil
        }
        return flow[index - 1]
    }

    var next: OnboardingRoute? {
        let flow = OnboardingRoute.activeFlow
        guard let index = flow.firstIndex(of: normalizedForActiveFlow),
              index < (flow.count - 1) else {
            return nil
        }
        return flow[index + 1]
    }

    var normalizedForActiveFlow: OnboardingRoute {
        // Was used to redirect away from `.preferencesOptional` when it was
        // pulled from the active flow. Now that the route is back, every
        // case maps to itself — the function is kept as a hook for future
        // route deprecations.
        return self
    }
}

@MainActor
final class AppFlowCoordinator: ObservableObject {
    @Published var route: AppFlowRoute = .onboarding
    @Published var onboardingRoute: OnboardingRoute = .welcome

    func sync(isOnboardingComplete: Bool) {
        if isOnboardingComplete {
            route = .home
            return
        }

        if route == .home {
            route = .onboarding
            onboardingRoute = .welcome
        }
    }

    func showHome() {
        route = .home
    }

    func startOnboardingFromBeginning() {
        route = .onboarding
        onboardingRoute = .welcome
    }

    func moveToOnboarding(_ route: OnboardingRoute) {
        self.route = .onboarding
        onboardingRoute = route.normalizedForActiveFlow
    }

    func moveNextOnboarding() {
        guard let next = onboardingRoute.next else { return }
        onboardingRoute = next
    }

    func moveBackOnboarding() {
        guard let previous = onboardingRoute.previous else { return }
        onboardingRoute = previous
    }
}
