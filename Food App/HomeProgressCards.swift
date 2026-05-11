import SwiftUI
import Charts

extension ProgressSectionView {
    var disabledFeatureCard: some View {
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

    var rangePicker: some View {
        Picker("Range", selection: $selectedRange) {
            ForEach(ProgressRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    var caloriesHeroCard: some View {
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
    var macroAdherenceCard: some View {
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

    func macroSubChart(for metric: MacroMetric) -> some View {
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

    var weightTrendCard: some View {
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

    /// Steps card — Apple-Health-style daily-step bar chart with a
    /// `DAILY AVERAGE N steps` headline matching the Steps screen
    /// pattern. Pulls daily-bucketed counts from HealthKit via
    /// `appStore.fetchStepCountsByDay`. Authorization is shared with
    /// the weight chart (same `canReadWeight` check), so a single
    /// "Connect Apple Health" prompt covers both.
    var stepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Steps")
                    .font(.headline)
                Spacer()
                if isLoadingSteps {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !canReadWeight {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect Apple Health to view step counts.")
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
            } else if let stepsError {
                Text(stepsError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if loggedStepDays.isEmpty {
                Text("No step data found in Apple Health for this range.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                // Apple Health style header.
                VStack(alignment: .leading, spacing: 2) {
                    Text("DAILY AVERAGE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(averageStepsLabel)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("steps")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Text(dateRangeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let displayed = aggregateStepsForRange(stepsSamples)
                let scale = stepsScale(for: displayed)
                Chart {
                    ForEach(displayed) { point in
                        BarMark(
                            x: .value("Date", point.date),
                            y: .value("Steps", scale.clamp(point.steps)),
                            width: .fixed(stepsBarWidth)
                        )
                        .foregroundStyle(ChartPalette.stepsAccent.gradient)
                        .cornerRadius(2)
                    }

                    if let selected = selectedStepsPoint {
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
                                    value: "\(Int(selected.steps.rounded()).formatted()) steps"
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
                .chartXScale(domain: chartXDomain(dates: displayed.map(\.date)) ?? Date()...Date())
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
                                            sourceDates: displayed.map(\.date),
                                            selectedDate: &selectedStepsDate
                                        )
                                    }
                            )
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
                        .stroke(ChartPalette.stepsAccent.opacity(0.25), lineWidth: 0.5)
                )
        )
    }

    /// Selection-tooltip bubble shared by the calorie + weight charts.
    /// Solid dark-on-light (or light-on-dark in dark mode) for guaranteed
    /// contrast against bars + Material card. Larger than a typical
    /// chart annotation so the value is glanceable.
    func tooltipBubble(title: String, value: String) -> some View {
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
}
