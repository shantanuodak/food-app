import SwiftUI
import Charts

extension ProgressSectionView {
    var calorieBarWidth: CGFloat {
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
    func chartXDomain(dates: [Date]) -> ClosedRange<Date>? {
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
    var chartXAxisStride: AxisMarkValues {
        switch selectedRange {
        case .week:      return .stride(by: .day, count: 1)
        case .month:     return .stride(by: .day, count: 5)
        case .sixMonths: return .stride(by: .month, count: 1)
        case .year:      return .stride(by: .month, count: 2)
        }
    }

    /// Format a date according to the resolution we're showing.
    func chartXAxisLabel(for date: Date) -> String {
        switch selectedRange {
        case .sixMonths, .year:
            return Self.monthOnlyFormatter.string(from: date)
        case .week, .month:
            return Self.shortDayFormatter.string(from: date)
        }
    }

    var caloriePoints: [NutritionChartPoint] {
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

    var selectedCaloriePoint: NutritionChartPoint? {
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
    func aggregateForRange(_ points: [NutritionChartPoint]) -> [NutritionChartPoint] {
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

    func macroPoints(for metric: MacroMetric) -> [NutritionChartPoint] {
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

    var canReadWeight: Bool {
        appStore.healthAuthorizationState == .authorized && appStore.isHealthSyncEnabled
    }

    var weightDisplayPoints: [WeightChartPoint] {
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

    func macroScale(for points: [NutritionChartPoint]) -> ChartScale {
        makePositiveScale(
            values: points.flatMap { [max(0, $0.consumed), max(0, $0.target)] },
            minimumUpperBound: 30
        )
    }

    var weightYAxisDomain: ClosedRange<Double> {
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

    var selectedWeightPoint: WeightChartPoint? {
        guard let selectedWeightDate else { return nil }
        return nearestPoint(for: selectedWeightDate, in: weightDisplayPoints)
    }

    func dailyWeightSamples() -> [(date: Date, kilograms: Double)] {
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

    func smoothedKilograms(for date: Date, in points: [(date: Date, kilograms: Double)]) -> Double {
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

    // MARK: - Steps helpers

    /// Days that actually have step data (> 0). Used both as the chart
    /// rendering source and for computing the daily average — a value
    /// of 0 typically means HealthKit didn't record anything for that
    /// day (no Apple Watch worn / iPhone not in pocket), which would
    /// otherwise drag the average down misleadingly.
    var loggedStepDays: [DailyStepCount] {
        stepsSamples.filter { $0.steps > 0 }
    }

    /// Average of `loggedStepDays` formatted with thousands separators.
    var averageStepsLabel: String {
        guard !loggedStepDays.isEmpty else { return "—" }
        let avg = loggedStepDays.reduce(0.0) { $0 + $1.steps } / Double(loggedStepDays.count)
        return Self.calorieAverageFormatter.string(from: NSNumber(value: avg)) ?? "\(Int(avg))"
    }

    var selectedStepsPoint: DailyStepCount? {
        guard let selectedStepsDate else { return nil }
        return aggregateStepsForRange(stepsSamples)
            .min { abs($0.date.timeIntervalSince(selectedStepsDate)) < abs($1.date.timeIntervalSince(selectedStepsDate)) }
    }

    /// Per-range fixed bar width — same scheme as `calorieBarWidth`.
    var stepsBarWidth: CGFloat {
        switch selectedRange {
        case .week:      return 22
        case .month:     return 8
        case .sixMonths: return 8
        case .year:      return 18
        }
    }

    /// Bucket daily step counts into weekly (6M) or monthly (Y) groups
    /// so bars don't render sub-pixel at long ranges. Mirrors
    /// `aggregateForRange` for nutrition points but operates on
    /// `DailyStepCount` and uses `sum` rather than average — total
    /// steps in a week/month is the meaningful aggregate, unlike
    /// "average calories per day" where averaging makes more sense.
    func aggregateStepsForRange(_ samples: [DailyStepCount]) -> [DailyStepCount] {
        let bucketComponent: Calendar.Component? = {
            switch selectedRange {
            case .week, .month: return nil
            case .sixMonths:    return .weekOfYear
            case .year:         return .month
            }
        }()
        guard let component = bucketComponent else { return samples }

        let calendar = Calendar.current
        let groups = Dictionary(grouping: samples) { sample -> Date in
            calendar.dateInterval(of: component, for: sample.date)?.start ?? sample.date
        }
        return groups.map { bucketStart, group -> DailyStepCount in
            let total = group.reduce(0.0) { $0 + $1.steps }
            return DailyStepCount(date: bucketStart, steps: total)
        }
        .sorted { $0.date < $1.date }
    }

    func stepsScale(for samples: [DailyStepCount]) -> ChartScale {
        makePositiveScale(
            values: samples.map { $0.steps },
            minimumUpperBound: 5_000
        )
    }

    @MainActor
    func refreshAllData(reason _: String) async {
        preferredUnits = currentPreferredUnits()
        await refreshNutritionData()
        await refreshWeightData()
        await refreshStepsData()
    }

    @MainActor
    func refreshNutritionData() async {
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
    func refreshWeightData() async {
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

    func requestAppleHealthFromProgress() {
        guard !isRequestingHealthPermission else { return }
        isRequestingHealthPermission = true
        Task {
            defer { isRequestingHealthPermission = false }
            _ = try? await appStore.requestAppleHealthAccess()
            await refreshWeightData()
            await refreshStepsData()
        }
    }

    @MainActor
    func refreshStepsData() async {
        guard appStore.configuration.progressFeatureEnabled else { return }

        guard canReadWeight else {
            stepsSamples = []
            stepsError = nil
            selectedStepsDate = nil
            return
        }

        isLoadingSteps = true
        stepsError = nil
        defer { isLoadingSteps = false }

        do {
            let bounds = selectedDateBounds()
            let samples = try await appStore.fetchStepCountsByDay(
                from: bounds.startDate,
                to: bounds.endDate.addingTimeInterval(86_399)
            )
            stepsSamples = samples
            // Default selection: most recent day with logged steps.
            if let last = samples.filter({ $0.steps > 0 }).last {
                selectedStepsDate = last.date
            } else {
                selectedStepsDate = nil
            }
        } catch {
            stepsSamples = []
            selectedStepsDate = nil
            if let healthError = error as? HealthKitServiceError {
                switch healthError {
                case .notAuthorized:
                    stepsError = "Connect Apple Health to view step counts."
                case .unavailable:
                    stepsError = "Apple Health is unavailable on this device."
                default:
                    stepsError = healthError.errorDescription ?? "Unable to load step counts."
                }
            } else {
                stepsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func selectedDateBounds() -> (startDate: Date, endDate: Date, from: String, to: String) {
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

    func currentPreferredUnits() -> UnitsOption {
        OnboardingPersistence.load()?.draft.units ?? .imperial
    }

    func userFriendlyProgressError(_ error: Error) -> String {
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
    var dailyAverageCalories: String {
        let logged = caloriePoints.filter { $0.hasLogs }
        guard !logged.isEmpty else { return "—" }
        let avg = logged.reduce(0.0) { $0 + $1.consumed } / Double(logged.count)
        return Self.calorieAverageFormatter.string(from: NSNumber(value: avg)) ?? "\(Int(avg))"
    }

    var dateRangeText: String {
        let bounds = selectedDateBounds()
        return "\(Self.rangeBoundFormatter.string(from: bounds.startDate)) – \(Self.rangeBoundFormatter.string(from: bounds.endDate))"
    }

    func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    func makePositiveScale(values: [Double], minimumUpperBound: Double) -> ChartScale {
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

    func percentile(ofSorted sortedValues: [Double], p: Double) -> Double {
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

    func nearestPoint<T: Identifiable>(for date: Date, in points: [T]) -> T? where T.ID == Date {
        points.min(by: { abs($0.id.timeIntervalSince(date)) < abs($1.id.timeIntervalSince(date)) })
    }

    func selectClosestDate(
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

    static let apiDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static let dayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let rangeBoundFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    static let monthOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    static let calorieAverageFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
