import SwiftUI

struct OB05PaceScreen: View {
    @Binding var selectedPace: PaceChoice?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Consistency beats speed. Pick a pace you can sustain.")
                .font(.footnote)
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .padding(.horizontal, 4)

            OnboardingSelectableTiles(
                options: PaceChoice.allCases,
                selected: selectedPace,
                label: { $0.title },
                onSelect: { selectedPace = $0 }
            )

            if let selectedPace {
                OnboardingValueCard(
                    title: "Pace selected",
                    bodyText: paceDescription(selectedPace),
                    isSuccess: true
                )
            }
        }
    }

    private func paceDescription(_ pace: PaceChoice) -> String {
        switch pace {
        case .conservative:
            return "Easier to sustain long-term with smaller daily changes."
        case .balanced:
            return "A practical middle ground for most people."
        case .aggressive:
            return "Faster progress, but requires tighter day-to-day consistency."
        }
    }
}
