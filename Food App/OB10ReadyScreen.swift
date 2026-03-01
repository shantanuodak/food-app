import SwiftUI

struct OB10ReadyScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingValueCard(
                title: "Ready to log",
                bodyText: "Your onboarding setup is complete. Start with your first meal and adjust anytime."
            )

            VStack(alignment: .leading, spacing: 8) {
                readinessRow(icon: "checkmark.circle.fill", text: "Personalized daily targets are set")
                readinessRow(icon: "checkmark.circle.fill", text: "Home logging flow is ready")
                readinessRow(icon: "checkmark.circle.fill", text: "Preferences can be updated any time")
            }
            .padding(.horizontal, 4)

            Text("You can still change goals and preferences later in Settings.")
                .font(.footnote)
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    private func readinessRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(OnboardingGlassTheme.accentStart)
            Text(text)
                .font(.footnote)
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
        }
    }
}
