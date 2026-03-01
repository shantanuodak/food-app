import Foundation
import Combine

enum AppFlowRoute: Equatable {
    case onboarding
    case home
}

enum OnboardingRoute: Int, CaseIterable, Equatable, Hashable {
    case welcome = 1
    case goal = 2
    case baseline = 3
    case activity = 4
    case pace = 5
    case preferencesOptional = 6
    case planPreview = 7
    case account = 8
    case permissions = 9
    case ready = 10

    var frameID: String {
        switch self {
        case .welcome: return "Welcome"
        case .goal: return "Goal"
        case .baseline: return "Baseline"
        case .activity: return "Activity"
        case .pace: return "Pace"
        case .preferencesOptional: return "Preferences"
        case .planPreview: return "Plan Preview"
        case .account: return "Account"
        case .permissions: return "Permissions"
        case .ready: return "Ready"
        }
    }

    var progressStep: Int? {
        switch self {
        case .goal: return 1
        case .baseline: return 2
        case .activity: return 3
        case .pace: return 4
        case .preferencesOptional: return 5
        case .planPreview: return 6
        default: return nil
        }
    }

    var hasBack: Bool {
        switch self {
        case .welcome, .ready:
            return false
        default:
            return true
        }
    }

    var previous: OnboardingRoute? {
        guard let previous = OnboardingRoute(rawValue: rawValue - 1) else {
            return nil
        }
        return previous
    }

    var next: OnboardingRoute? {
        guard let next = OnboardingRoute(rawValue: rawValue + 1) else {
            return nil
        }
        return next
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
        onboardingRoute = route
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
