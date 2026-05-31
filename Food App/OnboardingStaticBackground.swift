import SwiftUI

/// Static gradient-only background for non-welcome onboarding screens.
/// 2026-05-24: routed through `AppColor.shellBackground` so onboarding
/// and the home shell share the same subtle top-to-bottom darkening in
/// dark mode and the same flat systemBackground in light mode.
struct OnboardingStaticBackground: View {
    var body: some View {
        AppColor.shellBackground
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
