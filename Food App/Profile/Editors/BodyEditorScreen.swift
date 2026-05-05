import SwiftUI

/// Focused editor for body details (units, sex, age, height, weight).
/// Reachable from the bento dashboard's Body tile. Mirrors the contents
/// of `HomeProfileScreen.bodySection` but skips the surrounding hub —
/// the user is taken directly to the relevant fields.
///
/// Save behavior is identical to the legacy hub: 500 ms debounce,
/// auto-save on change, success state ticks back to idle after 2 s.
struct BodyEditorScreen: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var draftStore: ProfileDraftStore

    var body: some View {
        Form {
            Section("Body") {
                Picker("Units", selection: draftStore.unitsBinding) {
                    ForEach(UnitsOption.allCases) { opt in
                        Text(L10n.unitsLabel(opt)).tag(opt)
                    }
                }
                .pickerStyle(.segmented)

                Picker(selection: draftStore.sexBinding) {
                    ForEach(SexOption.allCases) { opt in
                        Text(opt.title).tag(Optional(opt))
                    }
                    Text("Not set").tag(Optional<SexOption>.none)
                } label: {
                    Label("Sex", systemImage: "person.fill")
                }
                .pickerStyle(.menu)

                Stepper(value: draftStore.ageIntBinding, in: OnboardingBaselineRange.age) {
                    LabeledContent {
                        Text("\(Int(draftStore.draft.ageValue))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } label: {
                        Label("Age", systemImage: "calendar")
                    }
                }

                NavigationLink {
                    HeightPickerView(draft: $draftStore.draft)
                } label: {
                    LabeledContent {
                        Text(draftStore.heightLabel).foregroundStyle(.secondary)
                    } label: {
                        Label("Height", systemImage: "ruler")
                    }
                }

                NavigationLink {
                    WeightPickerView(draft: $draftStore.draft)
                } label: {
                    LabeledContent {
                        Text(draftStore.weightLabel).foregroundStyle(.secondary)
                    } label: {
                        Label("Weight", systemImage: "scalemass.fill")
                    }
                }
            }
        }
        .navigationTitle("Body Details")
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
}
