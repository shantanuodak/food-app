import SwiftUI

extension OnboardingView {
    func syncBaselineStepForCurrentDraft() {
        // Sub-step navigation is handled by the baseline continue/back handlers.
        // Route-change sync below decides whether baseline opens at the first or last step.
    }

    /// Called when the onboarding route changes to baseline.
    /// Coming back from activity should land on weight; coming forward from age starts at sex.
    func syncBaselineStepOnRouteChange(previousRoute: OnboardingRoute?) {
        if previousRoute == .activity {
            baselineStep = .weight
        } else {
            baselineStep = .sex
        }
    }

    func handleAgeContinue() {
        draft.ageValue = draft.ageValue
        draft.baselineTouchedAge = true
        flow.moveNextOnboarding()
    }

    func handleBaselineBack() {
        switch baselineStep {
        case .sex:
            flow.moveBackOnboarding()
        case .height:
            baselineStep = .sex
        case .weight:
            baselineStep = .height
        }
    }

    func handleBaselineContinue() {
        switch baselineStep {
        case .sex:
            guard draft.baselineTouchedSex, draft.sex != nil else { return }
            baselineStep = .height
        case .height:
            draft.baselineTouchedHeight = true
            baselineStep = .weight
        case .weight:
            draft.baselineTouchedWeight = true
            guard draft.isBaselineValid else { return }
            flow.moveNextOnboarding()
        }
    }
}
