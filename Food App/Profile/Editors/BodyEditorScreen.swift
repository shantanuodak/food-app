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
    @State private var bodyMetricEditorSheet: BodyMetricEditorSheet?

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

                bodyEditorRow(
                    title: "Age",
                    value: "\(Int(draftStore.draft.ageValue))",
                    systemImage: "calendar",
                    editor: .age
                )

                bodyEditorRow(
                    title: "Height",
                    value: draftStore.heightLabel,
                    systemImage: "ruler",
                    editor: .height
                )

                bodyEditorRow(
                    title: "Weight",
                    value: draftStore.weightLabel,
                    systemImage: "scalemass.fill",
                    editor: .weight
                )
            }
        }
        .navigationTitle("Body Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $bodyMetricEditorSheet) { editor in
            bodyMetricEditorSheetView(editor)
        }
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

    private func bodyEditorRow(
        title: String,
        value: String,
        systemImage: String,
        editor: BodyMetricEditorSheet
    ) -> some View {
        Button {
            bodyMetricEditorSheet = editor
        } label: {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)

                Spacer(minLength: 16)

                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func bodyMetricEditorSheetView(_ editor: BodyMetricEditorSheet) -> some View {
        NavigationStack {
            Group {
                switch editor {
                case .age:
                    AgePickerView(draft: $draftStore.draft)
                case .height:
                    HeightPickerView(draft: $draftStore.draft)
                case .weight:
                    WeightPickerView(draft: $draftStore.draft)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        bodyMetricEditorSheet = nil
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
