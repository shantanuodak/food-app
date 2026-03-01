import SwiftUI

struct OB06PreferencesOptionalScreen: View {
    @Binding var preferences: Set<PreferenceChoice>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select all that apply. You can update these later in Settings.")
                .font(.footnote)
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .padding(.horizontal, 4)

            OnboardingChipSelector(options: PreferenceChoice.allCases, selected: $preferences)

            if !preferences.isEmpty {
                let count = preferences.contains(.noPreference) ? 0 : preferences.count
                OnboardingValueCard(
                    title: "Preference profile",
                    bodyText: preferences.contains(.noPreference)
                        ? "No strict filters yet. You’ll keep broader food suggestions."
                        : "\(count) preference\(count == 1 ? "" : "s") selected for better recommendations.",
                    isSuccess: !preferences.contains(.noPreference)
                )
            }
        }
    }
}
