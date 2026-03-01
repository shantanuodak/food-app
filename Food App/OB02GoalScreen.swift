import SwiftUI

struct OB02GoalScreen: View {
    @Binding var selectedGoal: GoalOption?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick the direction first. We’ll tune calories and macros around this.")
                .font(.footnote)
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .padding(.horizontal, 4)

            OnboardingSelectableTiles(
                options: GoalOption.allCases,
                selected: selectedGoal,
                label: { L10n.goalLabel($0) },
                onSelect: { selectedGoal = $0 }
            )

            if let selectedGoal {
                OnboardingValueCard(
                    title: "Selected goal",
                    bodyText: "Great choice. Your plan is now centered on \(L10n.goalLabel(selectedGoal)).",
                    isSuccess: true
                )
            }
        }
    }
}
