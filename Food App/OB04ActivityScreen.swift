import SwiftUI

struct OB04ActivityScreen: View {
    @Binding var selectedActivity: ActivityChoice?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose your usual week, not your best week.")
                .font(.footnote)
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .padding(.horizontal, 4)

            OnboardingSelectableTiles(
                options: ActivityChoice.allCases,
                selected: selectedActivity,
                label: { $0.title },
                onSelect: { selectedActivity = $0 }
            )

            if let selectedActivity {
                OnboardingValueCard(
                    title: "Activity selected",
                    bodyText: activityDescription(selectedActivity)
                )
            }
        }
    }

    private func activityDescription(_ activity: ActivityChoice) -> String {
        switch activity {
        case .mostlySitting:
            return "Mostly desk and low movement days. We’ll keep targets conservative."
        case .lightlyActive:
            return "Some movement during the day. Targets stay balanced."
        case .moderatelyActive:
            return "Regular walks or training. Targets increase moderately."
        case .veryActive:
            return "Frequent intense activity. Targets increase to support recovery."
        }
    }
}
