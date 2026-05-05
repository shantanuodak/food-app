import SwiftUI

/// Focused editor for dietary preferences and allergies. Reachable from
/// the bento dashboard's Diet tile. Mirrors the contents of
/// `HomeProfileScreen.dietSection` + `allergiesSection`.
struct DietEditorScreen: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var draftStore: ProfileDraftStore

    var body: some View {
        Form {
            preferencesSection
            allergiesSection
        }
        .navigationTitle("Food Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ProfileSaveStatusIndicator(status: draftStore.saveStatus) {
                    draftStore.triggerDebouncedSave(immediate: true, appStore: appStore)
                }
            }
        }
        .onChange(of: draftStore.draft) { _, _ in
            draftStore.triggerDebouncedSave(appStore: appStore)
        }
        .task {
            await draftStore.loadIfNeeded(appStore: appStore)
        }
    }

    @ViewBuilder
    private var preferencesSection: some View {
        let activePrefs = draftStore.draft.preferences.filter { $0 != .noPreference }
        Section {
            ForEach(PreferenceChoice.allCases.filter { $0 != .noPreference }) { pref in
                Toggle(isOn: draftStore.preferenceToggleBinding(pref)) {
                    Label(pref.title, systemImage: preferenceSymbol(for: pref))
                }
            }
        } header: {
            Text("Dietary Preferences")
        } footer: {
            if activePrefs.isEmpty {
                Text("Select any that apply.")
            }
        }
    }

    @ViewBuilder
    private var allergiesSection: some View {
        Section {
            ForEach(AllergyChoice.allCases) { allergy in
                Toggle(isOn: draftStore.allergyToggleBinding(allergy)) {
                    Label(allergy.title, systemImage: allergy.systemImage)
                }
            }
        } header: {
            Text("Allergies")
        } footer: {
            if draftStore.draft.allergies.isEmpty {
                Text("We'll flag foods that conflict with these in your daily log.")
            }
        }
    }

    private func preferenceSymbol(for preference: PreferenceChoice) -> String {
        switch preference {
        case .highProtein:   return "bolt.fill"
        case .vegetarian:    return "leaf"
        case .vegan:         return "leaf.fill"
        case .pescatarian:   return "fish"
        case .lowCarb:       return "minus.circle.fill"
        case .keto:          return "bolt.circle.fill"
        case .glutenFree:    return "checkmark.circle.fill"
        case .dairyFree:     return "drop.fill"
        case .halal:         return "moon.fill"
        case .lowSodium:     return "heart.text.square.fill"
        case .mediterranean: return "sun.max.fill"
        case .noPreference:  return "fork.knife"
        }
    }
}
