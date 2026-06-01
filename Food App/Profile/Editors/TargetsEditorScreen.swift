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
    @State private var showExplainer = false

    var body: some View {
        Form {
            Section("Your Plan") {
                Picker(selection: draftStore.goalBinding) {
                    ForEach(GoalOption.allCases) { option in
                        Text(L10n.goalLabel(option)).tag(Optional(option))
                    }
                    Text("Not set").tag(Optional<GoalOption>.none)
                } label: {
                    Label("Goal", systemImage: "scope")
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
                Section {
                    calorieTargetRow(calorieTarget)
                    if let macros = draftStore.draft.savedMacroTargets {
                        targetMetricRow(
                            icon: "figure.strengthtraining.traditional",
                            title: "Protein",
                            value: "\(macros.protein)",
                            unit: "g",
                            color: Self.proteinColor
                        )
                        targetMetricRow(
                            icon: "leaf.fill",
                            title: "Carbs",
                            value: "\(macros.carbs)",
                            unit: "g",
                            color: Self.carbsColor
                        )
                        targetMetricRow(
                            icon: "drop.fill",
                            title: "Fat",
                            value: "\(macros.fat)",
                            unit: "g",
                            color: Self.fatColor
                        )
                    }

                    Button {
                        showExplainer = true
                    } label: {
                        HStack(spacing: 12) {
                            metricIcon("function", color: .accentColor)
                            Text("How we calculate this")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 12)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Calculated Targets")
                } footer: {
                    Text("Targets update automatically when your goal, activity, or pace changes.")
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
        .sheet(isPresented: $showExplainer) {
            CalculationExplainerView(breakdown: CalculationBreakdown.make(from: draftStore.draft))
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private static let calorieColor = Color.orange
    private static let proteinColor = Color(red: 0.420, green: 0.369, blue: 1.0)
    private static let carbsColor = Color(red: 0.106, green: 0.620, blue: 0.353)
    private static let fatColor = Color(red: 0.000, green: 0.478, blue: 1.0)

    private func calorieTargetRow(_ calories: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            metricIcon("flame.fill", color: Self.calorieColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Calorie base")
                    .font(.system(size: 16, weight: .semibold))
                Text("Daily target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(calories.formatted())
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("kcal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calorie base, \(calories) kilocalories")
    }

    private func targetMetricRow(
        icon: String,
        title: String,
        value: String,
        unit: String,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            metricIcon(icon, color: color)
            Text(title)
                .font(.system(size: 16, weight: .medium))
            Spacer(minLength: 12)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(unit)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value) \(unit)")
    }

    private func metricIcon(_ systemName: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 34, height: 34)
    }
}
