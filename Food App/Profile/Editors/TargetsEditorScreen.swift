import SwiftUI

/// Focused editor for plan-driven targets (goal, activity, pace).
/// Reachable from the bento dashboard's Daily Targets edit pencil.
/// Mirrors the contents of `HomeProfileScreen.planSection`.
///
/// Calorie + macro targets themselves are computed on the backend from
/// the goal/activity/pace combination — there's no direct override
/// surface today. Editing here triggers a re-computation on save and
/// the dashboard's ring/macros refresh on the `.profileDraftSaved`
/// notification.
struct TargetsEditorScreen: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var draftStore: ProfileDraftStore

    var body: some View {
        Form {
            Section("Your Plan") {
                Picker(selection: draftStore.goalBinding) {
                    ForEach(GoalOption.allCases) { option in
                        Text(L10n.goalLabel(option)).tag(Optional(option))
                    }
                    Text("Not set").tag(Optional<GoalOption>.none)
                } label: {
                    Label("Goal", systemImage: "target")
                }
                .pickerStyle(.menu)

                Picker(selection: draftStore.activityBinding) {
                    ForEach(ActivityChoice.allCases) { option in
                        Text(option.title).tag(Optional(option))
                    }
                    Text("Not set").tag(Optional<ActivityChoice>.none)
                } label: {
                    Label("Activity", systemImage: "figure.walk")
                }
                .pickerStyle(.menu)

                Picker(selection: draftStore.paceBinding) {
                    ForEach(PaceChoice.allCases) { option in
                        Text(option.title).tag(Optional(option))
                    }
                    Text("Not set").tag(Optional<PaceChoice>.none)
                } label: {
                    Label("Pace", systemImage: "speedometer")
                }
                .pickerStyle(.menu)
            }

            if let calorieTarget = draftStore.draft.savedCalorieTarget {
                Section("Calculated Targets") {
                    LabeledContent("Calories") {
                        Text("\(calorieTarget) kcal").foregroundStyle(.secondary)
                    }
                    if let macros = draftStore.draft.savedMacroTargets {
                        LabeledContent("Protein") {
                            Text("\(macros.protein) g").foregroundStyle(.secondary)
                        }
                        LabeledContent("Carbs") {
                            Text("\(macros.carbs) g").foregroundStyle(.secondary)
                        }
                        LabeledContent("Fat") {
                            Text("\(macros.fat) g").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Plan & Goals")
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
