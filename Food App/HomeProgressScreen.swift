import SwiftUI
import Charts

struct HomeProgressScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            AppDrawerHeader(onClose: { dismiss() }) {
                Text("Progress")
                    .font(.custom("InstrumentSerif-Regular", size: 31))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.988, green: 0.545, blue: 0.196),
                                Color(red: 0.902, green: 0.361, blue: 0.102)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            ProgressSectionView()
        }
        .background(AppDrawerSurface.gradient)
        .presentationBackground(AppDrawerSurface.gradient)
    }
}


struct ProgressSectionView: View {
    @EnvironmentObject var appStore: AppStore
    @Environment(\.scenePhase) var scenePhase

    @State var selectedRange: ProgressRange = .week
    @State var progressResponse: ProgressResponse?
    @State var isLoadingProgress = false
    @State var progressError: String?
    @State var hydrationProgressResponse: HydrationProgressResponse?
    @State var isLoadingHydrationProgress = false
    @State var hydrationProgressError: String?

    @State var weightSamples: [BodyMassSample] = []
    @State var isLoadingWeight = false
    @State var weightError: String?
    @State var isRequestingHealthPermission = false

    @State var stepsSamples: [DailyStepCount] = []
    @State var isLoadingSteps = false
    @State var stepsError: String?

    @State var selectedCalorieDate: Date?
    @State var selectedHydrationDate: Date?
    @State var selectedWeightDate: Date?
    @State var selectedStepsDate: Date?
    @State var preferredUnits: UnitsOption = .imperial
    @State var lastHapticRange: ProgressRange = .week

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !appStore.configuration.progressFeatureEnabled {
                    disabledFeatureCard
                } else {
                    // 2026-05-22 (Phase F, Item 7): Today's calorie ring
                    // now lives at the top of Insights so the daily-targets
                    // story is the first thing users see. The segmented
                    // range picker sits below it and controls only the
                    // historical charts that follow.
                    CalorieHeroTile(
                        data: CalorieHeroTile.Data.from(
                            snapshot: appStore.profileDashboardSnapshot,
                            isInitialLoad: progressResponse == nil && isLoadingProgress
                        )
                    )

                    rangePicker
                    caloriesHeroCard
                    hydrationCard
                    macroAdherenceCard
                    weightTrendCard
                    stepsCard
                }
            }
            .padding()
        }
        .task {
            preferredUnits = currentPreferredUnits()
            if !hydrateFromCachedProgressSnapshot() {
                appStore.preloadProgressCharts(range: selectedRange)
                await appStore.waitForProgressChartsPreload(range: selectedRange)
                if !hydrateFromCachedProgressSnapshot() {
                    await refreshAllData(reason: "initial")
                } else {
                    await refreshHydrationData()
                }
            } else {
                await refreshHydrationData()
            }
        }
        .onChange(of: selectedRange) { _, _ in
            Task {
                if !hydrateFromCachedProgressSnapshot() {
                    appStore.preloadProgressCharts(range: selectedRange, force: true)
                    await appStore.waitForProgressChartsPreload(range: selectedRange)
                    if !hydrateFromCachedProgressSnapshot() {
                        await refreshAllData(reason: "range_change")
                    } else {
                        await refreshHydrationData()
                    }
                } else {
                    await refreshHydrationData()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    if !hydrateFromCachedProgressSnapshot() {
                        await refreshAllData(reason: "foreground")
                    } else {
                        await refreshHydrationData()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionProgressDidChange)) { _ in
            Task {
                await refreshNutritionData()
                await refreshHydrationData()
            }
        }
    }

    /// horizontal room for the chosen widths.
}
