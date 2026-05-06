import SwiftUI
import Charts

struct HomeProgressScreen: View {
    var body: some View {
        NavigationStack {
            ProgressSectionView()
                .navigationTitle("Progress")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}


struct ProgressSectionView: View {
    @EnvironmentObject var appStore: AppStore
    @Environment(\.scenePhase) var scenePhase

    @State var selectedRange: ProgressRange = .week
    @State var progressResponse: ProgressResponse?
    @State var isLoadingProgress = false
    @State var progressError: String?

    @State var weightSamples: [BodyMassSample] = []
    @State var isLoadingWeight = false
    @State var weightError: String?
    @State var isRequestingHealthPermission = false

    @State var stepsSamples: [DailyStepCount] = []
    @State var isLoadingSteps = false
    @State var stepsError: String?

    @State var selectedCalorieDate: Date?
    @State var selectedWeightDate: Date?
    @State var selectedStepsDate: Date?
    @State var preferredUnits: UnitsOption = .imperial

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !appStore.configuration.progressFeatureEnabled {
                    disabledFeatureCard
                } else {
                    rangePicker
                    caloriesHeroCard
                    macroAdherenceCard
                    weightTrendCard
                    stepsCard
                }
            }
            .padding()
        }
        .task {
            preferredUnits = currentPreferredUnits()
            await refreshAllData(reason: "initial")
        }
        .onChange(of: selectedRange) { _, _ in
            Task { await refreshAllData(reason: "range_change") }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refreshAllData(reason: "foreground") }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionProgressDidChange)) { _ in
            Task { await refreshNutritionData() }
        }
    }

    /// horizontal room for the chosen widths.
}
