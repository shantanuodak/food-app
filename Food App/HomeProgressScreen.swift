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

/// Mode-aware color tokens for the progress charts. Replaces the
/// `Color.white.opacity(...)` / `Color.black.opacity(...)` literals
/// that assumed a dark canvas — every value here adapts to light
/// mode automatically. When a real design system lands, swap these
/// statics for tokens without touching the chart bodies.
private enum ChartPalette {
    // Surfaces
    static let cardBackground: Color = Color(.tertiarySystemBackground)
    static let pointFill: Color      = Color(.systemBackground)

    // Lines & ticks
    static let gridLine: Color   = Color(.separator)
    static let scrubLine: Color  = Color.primary.opacity(0.4)
    static let targetLine: Color = Color.secondary.opacity(0.7)

    // Macros
    static let protein = Color(red: 0.19, green: 0.72, blue: 0.98)
    static let carbs   = Color(red: 0.99, green: 0.64, blue: 0.22)
    static let fat     = Color(red: 0.98, green: 0.38, blue: 0.36)

    // Hero card accents (used as 1pt strokes over Material)
    static let calorieAccent: Color = Color.green
    static let weightAccent: Color  = Color.blue
}

private enum ProgressRange: Int, CaseIterable, Identifiable, Hashable {
    case week       = 7
    case month      = 30
    case sixMonths  = 180
    case year       = 365

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .week:      return "W"
        case .month:     return "M"
        case .sixMonths: return "6M"
        case .year:      return "Y"
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
        case .protein: return ChartPalette.protein
        case .carbs:   return ChartPalette.carbs
        case .fat:     return ChartPalette.fat
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

private struct WeightChartPoint: Identifiable {
    let date: Date
    let value: Double
    let smoothedValue: Double

    var id: Date { date }
}

struct ProgressSectionView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedRange: ProgressRange = .week
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
                    macroAdherenceCard
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
        VStack(alignment: .leading, spacing: 8) {
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
                .fill(ChartPalette.cardBackground)
        )
    }

    private var rangePicker: some View {
        Picker("Range", selection: $selectedRange) {
            ForEach(ProgressRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    private var caloriesHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                // Apple Health style header: DAILY AVERAGE + big number + range
                VStack(alignment: .leading, spacing: 4) {
                    Text("DAILY AVERAGE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(dailyAverageCalories)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("kcal")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Text(dateRangeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let displayedPoints = aggregateForRange(caloriePoints)
                let bars = displayedPoints.filter { $0.hasLogs }
                let scale = makePositiveScale(
                    values: displayedPoints.flatMap { [max(0, $0.consumed), max(0, $0.target)] },
                    minimumUpperBound: 400
                )

                if bars.isEmpty {
                    HStack {
                        Spacer()
                        Text("No logs in this range")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 220)
                } else {
                Chart {
                    ForEach(displayedPoints.filter { $0.hasLogs }) { point in
                        BarMark(
                            x: .value("Date", point.date),
                            y: .value("Calories", scale.clamp(point.consumed)),
                            width: .fixed(calorieBarWidth)
                        )
                        .foregroundStyle(ChartPalette.calorieAccent.gradient)
                        .cornerRadius(2)
                    }

                    ForEach(displayedPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Target", scale.clamp(point.target))
                        )
                        .foregroundStyle(ChartPalette.targetLine)
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                        .interpolationMethod(.linear)
                    }

                    if let selected = selectedCaloriePoint {
                        RuleMark(x: .value("Selected", selected.date))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .foregroundStyle(ChartPalette.scrubLine)
                            .annotation(
                                position: .top,
                                spacing: 12,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                            ) {
                                tooltipBubble(
                                    title: Self.dayLabelFormatter.string(from: selected.date),
                                    value: "\(Int(selected.consumed.rounded())) / \(Int(selected.target.rounded())) kcal"
                                )
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: chartXAxisStride) { value in
                        AxisGridLine().foregroundStyle(ChartPalette.gridLine)
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(chartXAxisLabel(for: date))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { _ in
                        AxisGridLine().foregroundStyle(ChartPalette.gridLine)
                        AxisValueLabel()
                    }
                }
                .chartYScale(domain: scale.minY ... scale.maxY)
                .chartXScale(domain: chartXDomain(dates: displayedPoints.map(\.date)) ?? Date()...Date())
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
                                            sourceDates: aggregateForRange(caloriePoints).map(\.date),
                                            selectedDate: &selectedCalorieDate
                                        )
                                    }
                            )
                    }
                }
                }

            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(ChartPalette.calorieAccent.opacity(0.25), lineWidth: 0.5)
                )
        )
    }

    /// Apple Health "Activity" style — single card that stacks Protein,
    /// Carbs, Fat as three small bar charts. Each row pairs a colored
    /// metric label with a right-aligned "consumed of target g" summary
    /// and a thin bar trace below. Replaces the old three-card macro
    /// stack and the standalone Streak / Weekly Delta cards.
    private var macroAdherenceCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Macro Adherence")
                .font(.headline)

            ForEach(MacroMetric.allCases, id: \.rawValue) { metric in
                macroSubChart(for: metric)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
        )
    }

    private func macroSubChart(for metric: MacroMetric) -> some View {
        let points = macroPoints(for: metric)
        // Headlines (consumed / target avg) are computed from raw daily
        // data so they don't shift when the user changes range — same
        // convention Apple Health uses.
        let logged = points.filter { $0.hasLogs }
        let consumedAverage = logged.isEmpty ? 0 : logged.reduce(0) { $0 + $1.consumed } / Double(logged.count)
        let targetAverage = points.isEmpty ? 0 : points.reduce(0) { $0 + $1.target } / Double(points.count)

        // Bars use range-aware aggregation so 6M/Y don't render sub-pixel.
        let displayedPoints = aggregateForRange(points)
        let scale = macroScale(for: displayedPoints)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(metric.color)
                Spacer()
                Text("\(formatOneDecimal(consumedAverage)) of \(formatOneDecimal(targetAverage)) g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let bars = displayedPoints.filter { $0.hasLogs }
            if points.isEmpty {
                Text("No data yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 80, alignment: .leading)
            } else if bars.isEmpty {
                HStack {
                    Spacer()
                    Text("No logs in this range")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(height: 80)
            } else {
                Chart {
                    ForEach(bars) { point in
                        BarMark(
                            x: .value("Date", point.date),
                            y: .value("Consumed", scale.clamp(point.consumed)),
                            width: .fixed(calorieBarWidth)
                        )
                        .foregroundStyle(metric.color.gradient)
                        .cornerRadius(2)
                    }

                    ForEach(displayedPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Target", scale.clamp(point.target))
                        )
                        .foregroundStyle(ChartPalette.targetLine)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .interpolationMethod(.linear)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    // Visible baseline at 0 — bars now sit on a line instead
                    // of floating in midair. Single value [0] means only the
                    // baseline grid renders, no other y-ticks crowd the
                    // small sub-chart.
                    AxisMarks(position: .trailing, values: [0]) { _ in
                        AxisGridLine()
                            .foregroundStyle(Color(.separator))
                        AxisValueLabel("0g")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYScale(domain: scale.minY ... scale.maxY)
                .chartXScale(domain: chartXDomain(dates: displayedPoints.map(\.date)) ?? Date()...Date())
                .frame(height: 80)
            }
        }
    }

    private var weightTrendCard: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                        .foregroundStyle(ChartPalette.pointFill)
                        .symbolSize(24)
                    }

                    if let selected = selectedWeightPoint {
                        RuleMark(x: .value("Selected", selected.date))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .foregroundStyle(ChartPalette.scrubLine)
                            .annotation(
                                position: .top,
                                spacing: 12,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                            ) {
                                tooltipBubble(
                                    title: Self.dayLabelFormatter.string(from: selected.date),
                                    value: "\(formatOneDecimal(selected.value)) \(unitLabel)"
                                )
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: chartXAxisStride) { value in
                        AxisGridLine().foregroundStyle(ChartPalette.gridLine)
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(chartXAxisLabel(for: date))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine().foregroundStyle(ChartPalette.gridLine)
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text("\(formatOneDecimal(number))")
                            }
                        }
                    }
                }
                .chartYScale(domain: weightYAxisDomain)
                .chartXScale(domain: chartXDomain(dates: weightDisplayPoints.map(\.date)) ?? Date()...Date())
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
                                            sourceDates: weightDisplayPoints.map(\.date),
                                            selectedDate: &selectedWeightDate
                                        )
                                    }
                            )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(ChartPalette.weightAccent.opacity(0.25), lineWidth: 0.5)
                )
        )
    }

    /// Selection-tooltip bubble shared by the calorie + weight charts.
    /// Solid dark-on-light (or light-on-dark in dark mode) for guaranteed
    /// contrast against bars + Material card. Larger than a typical
    /// chart annotation so the value is glanceable.
    private func tooltipBubble(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color(.systemBackground).opacity(0.7))
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color(.systemBackground))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.label))
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
        )
    }

    /// Per-range fixed bar width. `.ratio(0.6)` produced sub-5pt bars at
    /// M (30 daily slots / ~280pt chart width) which were nearly
    /// invisible against the Material card background. Fixed widths
    /// keep bars readable at every zoom; the chart always has enough
    /// horizontal room for the chosen widths.
    private var calorieBarWidth: CGFloat {
        switch selectedRange {
        case .week:      return 22
        case .month:     return 8
        case .sixMonths: return 8   // ~26 weekly buckets after aggregation
        case .year:      return 18  // ~12 monthly buckets after aggregation
        }
    }

    /// Pad the X-axis domain by a fraction of a bucket on each side so
    /// bars don't hug the chart frame edges. Without this, the leftmost
    /// bar sits flush against the plot area's left wall while the
    /// trailing Y-axis labels create implicit right-padding — visually
    /// left-biased. Apple Health charts extend the domain similarly.
    private func chartXDomain(dates: [Date]) -> ClosedRange<Date>? {
        guard let first = dates.first, let last = dates.last else { return nil }
        let calendar = Calendar.current
        let (component, amount): (Calendar.Component, Int) = {
            switch selectedRange {
            case .week, .month: return (.hour, 18)   // ~¾ day on each side at daily resolution
            case .sixMonths:    return (.day, 4)     // ~½ week on each side at weekly buckets
            case .year:         return (.day, 14)    // ~½ month on each side at monthly buckets
            }
        }()
        guard
            let lower = calendar.date(byAdding: component, value: -amount, to: first),
            let upper = calendar.date(byAdding: component, value: amount, to: last)
        else { return first ... last }
        return lower ... upper
    }

    /// X-axis tick stride per range. Short windows tick by day; longer
    /// windows (6M, Y) tick by month so the labels don't collide.
    private var chartXAxisStride: AxisMarkValues {
        switch selectedRange {
        case .week:      return .stride(by: .day, count: 1)
        case .month:     return .stride(by: .day, count: 5)
        case .sixMonths: return .stride(by: .month, count: 1)
        case .year:      return .stride(by: .month, count: 2)
        }
    }

    /// Format a date according to the resolution we're showing.
    private func chartXAxisLabel(for date: Date) -> String {
        switch selectedRange {
        case .sixMonths, .year:
            return Self.monthOnlyFormatter.string(from: date)
        case .week, .month:
            return Self.shortDayFormatter.string(from: date)
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
        return nearestPoint(for: selectedCalorieDate, in: aggregateForRange(caloriePoints))
    }

    /// Bucket raw daily points into the resolution that fits the
    /// selected range. Without this, 6M (180 daily bars across ~280pt)
    /// renders sub-pixel-thin bars that disappear, and Y (365 bars) is
    /// even worse. Apple Health solves the same problem with weekly
    /// buckets at 6M and monthly buckets at Y — we mirror that.
    ///
    /// Aggregation rules:
    /// - D / W / M: pass through, daily resolution.
    /// - 6M: weekly buckets (Sunday-start by Calendar default).
    /// - Y:  monthly buckets.
    /// - `consumed` is averaged across logged days only.
    /// - `target` is averaged across all days in the bucket.
    /// - `hasLogs` is true if any day in the bucket was logged.
    private func aggregateForRange(_ points: [NutritionChartPoint]) -> [NutritionChartPoint] {
        let bucketComponent: Calendar.Component? = {
            switch selectedRange {
            case .week, .month: return nil
            case .sixMonths:    return .weekOfYear
            case .year:         return .month
            }
        }()

        guard let component = bucketComponent else { return points }

        let calendar = Calendar.current
        let groups = Dictionary(grouping: points) { point -> Date in
            calendar.dateInterval(of: component, for: point.date)?.start ?? point.date
        }

        return groups.map { bucketStart, group -> NutritionChartPoint in
            let logged = group.filter { $0.hasLogs }
            let avgConsumed = logged.isEmpty ? 0 : logged.reduce(0.0) { $0 + $1.consumed } / Double(logged.count)
            let avgTarget = group.isEmpty ? 0 : group.reduce(0.0) { $0 + $1.target } / Double(group.count)
            return NutritionChartPoint(
                date: bucketStart,
                consumed: avgConsumed,
                target: avgTarget,
                hasLogs: !logged.isEmpty
            )
        }
        .sorted { $0.date < $1.date }
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

    /// Mean of consumed calories across days that actually have logs in
    /// the selected range. Apple Health uses the same convention — empty
    /// days don't count against the average.
    private var dailyAverageCalories: String {
        let logged = caloriePoints.filter { $0.hasLogs }
        guard !logged.isEmpty else { return "—" }
        let avg = logged.reduce(0.0) { $0 + $1.consumed } / Double(logged.count)
        return Self.calorieAverageFormatter.string(from: NSNumber(value: avg)) ?? "\(Int(avg))"
    }

    private var dateRangeText: String {
        let bounds = selectedDateBounds()
        return "\(Self.rangeBoundFormatter.string(from: bounds.startDate)) – \(Self.rangeBoundFormatter.string(from: bounds.endDate))"
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

    private static let rangeBoundFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static let monthOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let calorieAverageFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
