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

private struct ChartScale {
    let minY: Double
    let maxY: Double

    func clamp(_ value: Double) -> Double {
        min(max(value, minY), maxY)
    }
}

private enum ProgressRange: Int, CaseIterable, Identifiable {
    case days7 = 7
    case days14 = 14
    case days30 = 30
    case days90 = 90

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .days7: return "7D"
        case .days14: return "14D"
        case .days30: return "30D"
        case .days90: return "90D"
        }
    }
}

private enum MacroMetric: String, CaseIterable {
    case protein
    case carbs
    case fat

    var title: String {
        switch self {
        case .protein: return "Protein"
        case .carbs: return "Carbs"
        case .fat: return "Fat"
        }
    }

    var color: Color {
        switch self {
        case .protein: return Color(red: 0.19, green: 0.72, blue: 0.98)
        case .carbs: return Color(red: 0.99, green: 0.64, blue: 0.22)
        case .fat: return Color(red: 0.98, green: 0.38, blue: 0.36)
        }
    }
}

private struct NutritionChartPoint: Identifiable {
    let date: Date
    let consumed: Double
    let target: Double
    let hasLogs: Bool

    var id: Date { date }
}

private struct NutritionChartSegment: Identifiable {
    let id: String
    let points: [NutritionChartPoint]
}

private struct WeightChartPoint: Identifiable {
    let date: Date
    let value: Double
    let smoothedValue: Double

    var id: Date { date }
}

struct ProgressSectionView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedRange: ProgressRange = .days30
    @State private var progressResponse: ProgressResponse?
    @State private var isLoadingProgress = false
    @State private var progressError: String?

    @State private var weightSamples: [BodyMassSample] = []
    @State private var isLoadingWeight = false
    @State private var weightError: String?
    @State private var isRequestingHealthPermission = false

    @State private var selectedCalorieDate: Date?
    @State private var selectedWeightDate: Date?
    @State private var preferredUnits: UnitsOption = .imperial

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !appStore.configuration.progressFeatureEnabled {
                    disabledFeatureCard
                } else {
                    rangePicker
                    caloriesHeroCard
                    macroCards
                    streakTimelineCard
                    weeklyDeltaCard
                    weightTrendCard
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

    private var disabledFeatureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Progress is currently disabled.")
                .font(.headline)
            Text("Enable `PROGRESS_FEATURE_ENABLED` to turn on charts and trends.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.gray.opacity(0.12))
        )
    }

    private var rangePicker: some View {
        HStack(spacing: 8) {
            ForEach(ProgressRange.allCases) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedRange = range
                    }
                } label: {
                    Text(range.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selectedRange == range ? Color.white : Color.primary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedRange == range ? Color.green : Color.gray.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var caloriesHeroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Calorie Adherence")
                    .font(.headline)
                Spacer()
                if isLoadingProgress {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let progressError {
                Text(progressError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if caloriePoints.isEmpty {
                Text("No progress data for this range yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let scale = calorieScale
                let consumedSegments = segmentedLoggedPoints(from: caloriePoints)
                Chart {
                    ForEach(consumedSegments) { segment in
                        ForEach(segment.points) { point in
                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value("Calories", scale.clamp(point.consumed))
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.35), Color.green.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Calories", scale.clamp(point.consumed))
                            )
                            .foregroundStyle(Color.green)
                            .lineStyle(StrokeStyle(lineWidth: 2.2))
                            .interpolationMethod(.linear)
                        }
                    }

                    ForEach(caloriePoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Target", scale.clamp(point.target))
                        )
                        .foregroundStyle(Color.gray.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                        .interpolationMethod(.linear)
                    }

                    if let selected = selectedCaloriePoint {
                        RuleMark(x: .value("Selected", selected.date))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .annotation(position: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.dayLabelFormatter.string(from: selected.date))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(Int(selected.consumed.rounded())) / \(Int(selected.target.rounded())) kcal")
                                        .font(.caption.weight(.semibold))
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.black.opacity(0.7))
                                )
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: axisStrideCount)) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisTick().foregroundStyle(Color.white.opacity(0.2))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(Self.shortDayFormatter.string(from: date))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartYScale(domain: scale.minY ... scale.maxY)
                .frame(height: 220)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        selectClosestDate(
                                            from: value.location,
                                            proxy: proxy,
                                            geometry: geometry,
                                            sourceDates: caloriePoints.map(\.date),
                                            selectedDate: &selectedCalorieDate
                                        )
                                    }
                            )
                    }
                }

                if calorieChartHasClampedValues {
                    Text("Large outlier days are compressed for readability.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.green.opacity(0.2), Color.green.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var macroCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Macro Adherence")
                .font(.headline)

            ForEach(MacroMetric.allCases, id: \.rawValue) { metric in
                macroCard(for: metric)
            }
        }
    }

    private func macroCard(for metric: MacroMetric) -> some View {
        let points = macroPoints(for: metric)
        let scale = macroScale(for: points)
        let targetAverage = points.isEmpty ? 0 : points.reduce(0) { $0 + $1.target } / Double(points.count)
        let consumedAverage = points.isEmpty ? 0 : points.reduce(0) { $0 + $1.consumed } / Double(points.count)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(metric.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(formatOneDecimal(consumedAverage))/\(formatOneDecimal(targetAverage)) g avg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if points.isEmpty {
                Text("No data yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let consumedSegments = segmentedLoggedPoints(from: points)
                Chart {
                    ForEach(consumedSegments) { segment in
                        ForEach(segment.points) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Consumed", scale.clamp(point.consumed))
                            )
                            .foregroundStyle(metric.color)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.linear)
                        }
                    }

                    ForEach(points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Target", scale.clamp(point.target))
                        )
                        .foregroundStyle(Color.gray.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .interpolationMethod(.linear)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: scale.minY ... scale.maxY)
                .frame(height: 92)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var streakTimelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Streak")
                .font(.headline)

            if let progressResponse {
                HStack(spacing: 12) {
                    statPill(title: "Current", value: "\(progressResponse.streaks.currentDays)d")
                    statPill(title: "Longest", value: "\(progressResponse.streaks.longestDays)d")
                }

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(caloriePoints) { point in
                        Capsule(style: .continuous)
                            .fill(point.hasLogs ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 7, height: point.hasLogs ? 26 : 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No streak data yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var weeklyDeltaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weekly Delta")
                .font(.headline)

            if let delta = progressResponse?.weeklyDelta {
                deltaRow(title: "Calories", delta: delta.calories.delta, suffix: "kcal")
                deltaRow(title: "Protein", delta: delta.protein.delta, suffix: "g")
                deltaRow(title: "Carbs", delta: delta.carbs.delta, suffix: "g")
                deltaRow(title: "Fat", delta: delta.fat.delta, suffix: "g")
            } else {
                Text("Weekly delta becomes available as data accumulates.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var weightTrendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Weight Trend")
                    .font(.headline)
                Spacer()
                if isLoadingWeight {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !canReadWeight {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect Apple Health to view weight trends.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        requestAppleHealthFromProgress()
                    } label: {
                        if isRequestingHealthPermission {
                            ProgressView()
                        } else {
                            Text("Connect Apple Health")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if let weightError {
                Text(weightError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if weightDisplayPoints.isEmpty {
                Text("No weight entries found in Apple Health yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let unitLabel = HealthKitService.weightUnitLabel(for: preferredUnits)
                Chart {
                    ForEach(weightDisplayPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Trend", point.smoothedValue)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.cyan, Color.blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2.2))

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.value)
                        )
                        .foregroundStyle(Color.white.opacity(0.9))
                        .symbolSize(24)
                    }

                    if let selected = selectedWeightPoint {
                        RuleMark(x: .value("Selected", selected.date))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .annotation(position: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.dayLabelFormatter.string(from: selected.date))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(formatOneDecimal(selected.value)) \(unitLabel)")
                                        .font(.caption.weight(.semibold))
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.black.opacity(0.7))
                                )
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: axisStrideCount)) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisTick().foregroundStyle(Color.white.opacity(0.2))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(Self.shortDayFormatter.string(from: date))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisTick().foregroundStyle(Color.white.opacity(0.2))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text("\(formatOneDecimal(number))")
                            }
                        }
                    }
                }
                .chartYScale(domain: weightYAxisDomain)
                .frame(height: 210)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        selectClosestDate(
                                            from: value.location,
                                            proxy: proxy,
                                            geometry: geometry,
                                            sourceDates: weightDisplayPoints.map(\.date),
                                            selectedDate: &selectedWeightDate
                                        )
                                    }
                            )
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.18), Color.blue.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var axisStrideCount: Int {
        switch selectedRange {
        case .days7:
            return 1
        case .days14:
            return 2
        case .days30:
            return 5
        case .days90:
            return 12
        }
    }

    private var caloriePoints: [NutritionChartPoint] {
        guard let progressResponse else { return [] }
        return progressResponse.days.compactMap { day in
            guard let date = Self.apiDayFormatter.date(from: day.date) else {
                return nil
            }
            return NutritionChartPoint(
                date: date,
                consumed: day.totals.calories,
                target: day.targets.calories,
                hasLogs: day.hasLogs
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var selectedCaloriePoint: NutritionChartPoint? {
        guard let selectedCalorieDate else { return nil }
        return nearestPoint(for: selectedCalorieDate, in: caloriePoints)
    }

    private func macroPoints(for metric: MacroMetric) -> [NutritionChartPoint] {
        guard let progressResponse else { return [] }
        return progressResponse.days.compactMap { day in
            guard let date = Self.apiDayFormatter.date(from: day.date) else {
                return nil
            }
            switch metric {
            case .protein:
                return NutritionChartPoint(date: date, consumed: day.totals.protein, target: day.targets.protein, hasLogs: day.hasLogs)
            case .carbs:
                return NutritionChartPoint(date: date, consumed: day.totals.carbs, target: day.targets.carbs, hasLogs: day.hasLogs)
            case .fat:
                return NutritionChartPoint(date: date, consumed: day.totals.fat, target: day.targets.fat, hasLogs: day.hasLogs)
            }
        }
        .sorted { $0.date < $1.date }
    }

    private var canReadWeight: Bool {
        appStore.healthAuthorizationState == .authorized && appStore.isHealthSyncEnabled
    }

    private var weightDisplayPoints: [WeightChartPoint] {
        let daily = dailyWeightSamples()
        guard !daily.isEmpty else { return [] }

        return daily.map { point in
            WeightChartPoint(
                date: point.date,
                value: HealthKitService.displayWeightValue(kilograms: point.kilograms, units: preferredUnits),
                smoothedValue: HealthKitService.displayWeightValue(
                    kilograms: smoothedKilograms(for: point.date, in: daily),
                    units: preferredUnits
                )
            )
        }
    }

    private var calorieScale: ChartScale {
        makePositiveScale(
            values: caloriePoints.flatMap { [max(0, $0.consumed), max(0, $0.target)] },
            minimumUpperBound: 400
        )
    }

    private var calorieChartHasClampedValues: Bool {
        let maxY = calorieScale.maxY
        return caloriePoints.contains { $0.consumed > maxY || $0.target > maxY }
    }

    private func macroScale(for points: [NutritionChartPoint]) -> ChartScale {
        makePositiveScale(
            values: points.flatMap { [max(0, $0.consumed), max(0, $0.target)] },
            minimumUpperBound: 30
        )
    }

    private var weightYAxisDomain: ClosedRange<Double> {
        let values = weightDisplayPoints.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0 ... 1
        }
        if abs(maxValue - minValue) < 0.01 {
            return (minValue - 1) ... (maxValue + 1)
        }
        let padding = (maxValue - minValue) * 0.15
        return (minValue - padding) ... (maxValue + padding)
    }

    private var selectedWeightPoint: WeightChartPoint? {
        guard let selectedWeightDate else { return nil }
        return nearestPoint(for: selectedWeightDate, in: weightDisplayPoints)
    }

    private func dailyWeightSamples() -> [(date: Date, kilograms: Double)] {
        let calendar = Calendar.current
        var latestByDay: [Date: BodyMassSample] = [:]

        for sample in weightSamples {
            let day = calendar.startOfDay(for: sample.date)
            if let existing = latestByDay[day] {
                if sample.date > existing.date {
                    latestByDay[day] = sample
                }
            } else {
                latestByDay[day] = sample
            }
        }

        return latestByDay
            .map { (key: Date, value: BodyMassSample) in
                (date: key, kilograms: value.kilograms)
            }
            .sorted { $0.date < $1.date }
    }

    private func smoothedKilograms(for date: Date, in points: [(date: Date, kilograms: Double)]) -> Double {
        let calendar = Calendar.current
        guard let windowStart = calendar.date(byAdding: .day, value: -6, to: date) else {
            return points.first(where: { $0.date == date })?.kilograms ?? 0
        }

        let inWindow = points.filter { $0.date >= windowStart && $0.date <= date }
        guard !inWindow.isEmpty else {
            return points.first(where: { $0.date == date })?.kilograms ?? 0
        }
        let sum = inWindow.reduce(0.0) { $0 + $1.kilograms }
        return sum / Double(inWindow.count)
    }

    @MainActor
    private func refreshAllData(reason _: String) async {
        preferredUnits = currentPreferredUnits()
        await refreshNutritionData()
        await refreshWeightData()
    }

    @MainActor
    private func refreshNutritionData() async {
        guard appStore.configuration.progressFeatureEnabled else { return }

        isLoadingProgress = true
        progressError = nil
        defer { isLoadingProgress = false }

        do {
            let bounds = selectedDateBounds()
            let response = try await appStore.apiClient.getProgress(
                from: bounds.from,
                to: bounds.to,
                timezone: TimeZone.current.identifier
            )
            progressResponse = response
            if let last = caloriePoints.last {
                selectedCalorieDate = last.date
            } else {
                selectedCalorieDate = nil
            }
        } catch {
            progressResponse = nil
            progressError = userFriendlyProgressError(error)
        }
    }

    @MainActor
    private func refreshWeightData() async {
        guard appStore.configuration.progressFeatureEnabled else { return }

        guard canReadWeight else {
            weightSamples = []
            weightError = nil
            selectedWeightDate = nil
            return
        }

        isLoadingWeight = true
        weightError = nil
        defer { isLoadingWeight = false }

        do {
            let bounds = selectedDateBounds()
            let samples = try await appStore.fetchBodyMassSamples(from: bounds.startDate, to: bounds.endDate.addingTimeInterval(86_399))
            weightSamples = samples
            if let last = weightDisplayPoints.last {
                selectedWeightDate = last.date
            } else {
                selectedWeightDate = nil
            }
        } catch {
            weightSamples = []
            selectedWeightDate = nil
            if let healthError = error as? HealthKitServiceError {
                switch healthError {
                case .notAuthorized:
                    weightError = "Connect Apple Health to view weight trends."
                case .unavailable:
                    weightError = "Apple Health is unavailable on this device."
                default:
                    weightError = healthError.errorDescription ?? "Unable to load weight trends."
                }
            } else {
                weightError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func requestAppleHealthFromProgress() {
        guard !isRequestingHealthPermission else { return }
        isRequestingHealthPermission = true
        Task {
            defer { isRequestingHealthPermission = false }
            _ = try? await appStore.requestAppleHealthAccess()
            await refreshWeightData()
        }
    }

    private func selectedDateBounds() -> (startDate: Date, endDate: Date, from: String, to: String) {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        let offset = max(0, selectedRange.rawValue - 1)
        let startDate = calendar.date(byAdding: .day, value: -offset, to: endDate) ?? endDate
        return (
            startDate: startDate,
            endDate: endDate,
            from: Self.apiDayFormatter.string(from: startDate),
            to: Self.apiDayFormatter.string(from: endDate)
        )
    }

    private func currentPreferredUnits() -> UnitsOption {
        OnboardingPersistence.load()?.draft.units ?? .imperial
    }

    private func userFriendlyProgressError(_ error: Error) -> String {
        guard let apiError = error as? APIClientError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        switch apiError {
        case let .server(_, payload):
            switch payload.code {
            case "PROFILE_NOT_FOUND":
                return "Complete onboarding first to view progress."
            case "FEATURE_DISABLED":
                return "Progress is temporarily disabled."
            case "INVALID_INPUT":
                return "The selected range is invalid."
            default:
                return payload.message
            }
        case .networkFailure:
            return "Network issue while loading progress."
        default:
            return apiError.errorDescription ?? "Failed to load progress."
        }
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func deltaRow(title: String, delta: Double, suffix: String) -> some View {
        let isUp = delta > 0
        let isFlat = abs(delta) < 0.05
        let symbol = isFlat ? "minus" : (isUp ? "arrow.up.right" : "arrow.down.right")
        let tint: Color = isFlat ? .secondary : (isUp ? .orange : .green)

        return HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text("\(delta >= 0 ? "+" : "")\(formatOneDecimal(delta)) \(suffix)")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
        }
    }

    private func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func makePositiveScale(values: [Double], minimumUpperBound: Double) -> ChartScale {
        let sanitized = values
            .filter { $0.isFinite && $0 >= 0 }
            .sorted()

        guard let maxValue = sanitized.last else {
            return ChartScale(minY: 0, maxY: minimumUpperBound)
        }

        let p85 = percentile(ofSorted: sanitized, p: 0.85)
        let p95 = percentile(ofSorted: sanitized, p: 0.95)
        let robustCeiling = max(p95, p85 * 1.25)
        let paddedRobustCeiling = max(robustCeiling * 1.12, minimumUpperBound)
        let hardCeiling = max(maxValue * 1.1, minimumUpperBound)
        let cappedCeiling = min(hardCeiling, paddedRobustCeiling * 2.25)
        let upperBound = max(minimumUpperBound, max(cappedCeiling, p85))
        return ChartScale(minY: 0, maxY: upperBound)
    }

    private func segmentedLoggedPoints(from points: [NutritionChartPoint]) -> [NutritionChartSegment] {
        var segments: [NutritionChartSegment] = []
        var current: [NutritionChartPoint] = []

        for point in points {
            if point.hasLogs {
                current.append(point)
                continue
            }

            if !current.isEmpty {
                segments.append(
                    NutritionChartSegment(
                        id: String(segments.count),
                        points: current
                    )
                )
                current.removeAll(keepingCapacity: true)
            }
        }

        if !current.isEmpty {
            segments.append(
                NutritionChartSegment(
                    id: String(segments.count),
                    points: current
                )
            )
        }

        return segments
    }

    private func percentile(ofSorted sortedValues: [Double], p: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let clampedP = min(max(p, 0), 1)
        let position = clampedP * Double(sortedValues.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))

        if lowerIndex == upperIndex {
            return sortedValues[lowerIndex]
        }

        let fraction = position - Double(lowerIndex)
        let lower = sortedValues[lowerIndex]
        let upper = sortedValues[upperIndex]
        return lower + (upper - lower) * fraction
    }

    private func nearestPoint<T: Identifiable>(for date: Date, in points: [T]) -> T? where T.ID == Date {
        points.min(by: { abs($0.id.timeIntervalSince(date)) < abs($1.id.timeIntervalSince(date)) })
    }

    private func selectClosestDate(
        from location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        sourceDates: [Date],
        selectedDate: inout Date?
    ) {
        guard let plotFrame = proxy.plotFrame else { return }
        let plotRect = geometry[plotFrame]
        let xPosition = location.x - plotRect.origin.x
        guard xPosition >= 0, xPosition <= plotRect.size.width else { return }
        guard let hoveredDate: Date = proxy.value(atX: xPosition) else { return }
        guard let closest = sourceDates.min(by: { abs($0.timeIntervalSince(hoveredDate)) < abs($1.timeIntervalSince(hoveredDate)) }) else {
            return
        }
        selectedDate = closest
    }

    private static let apiDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let dayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
