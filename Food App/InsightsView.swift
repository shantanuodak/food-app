import SwiftUI
import Charts

/// Insights — daily-bar charts for the four nutrition metrics across a
/// user-selectable time window (7d / 14d / 1mo / 3mo). Reachable from
/// the Profile's Insights hub row.
///
/// Data source: `GET /v1/logs/progress`. Returns per-day totals, targets,
/// and a `hasLogs` flag. No new backend surface introduced.
///
/// Design intent (revised after Tier 1 review):
/// - One bar per day, four charts stacked (Calories, Protein, Carbs, Fat).
/// - Bar height = consumed value. A dashed target line overlays so the
///   user can see at a glance which days hit and which fell short.
/// - Days with no logs render with no bar (not a zero bar). The target
///   line is continuous regardless so the eye has a baseline.
/// - Segmented Picker at the top swaps the active range — re-fetches
///   progress data each time. Default is 30d.
/// - Steps chart is still Tier 2 (#8 add-on) — needs HealthKit range
///   read or new backend endpoint.
struct InsightsView: View {
    @EnvironmentObject private var appStore: AppStore

    enum RangeOption: Int, CaseIterable, Identifiable {
        case sevenDays = 7
        case fourteenDays = 14
        case oneMonth = 30
        case threeMonths = 90

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .sevenDays: return "7D"
            case .fourteenDays: return "14D"
            case .oneMonth: return "1M"
            case .threeMonths: return "3M"
            }
        }

        var headerLabel: String {
            switch self {
            case .sevenDays: return "Last 7 days"
            case .fourteenDays: return "Last 14 days"
            case .oneMonth: return "Last 30 days"
            case .threeMonths: return "Last 3 months"
            }
        }

        /// X-axis tick density — wider ranges need fewer labels to avoid
        /// overlap. Roughly aim for ~5 ticks across the range.
        var axisStrideDays: Int {
            switch self {
            case .sevenDays: return 1
            case .fourteenDays: return 2
            case .oneMonth: return 5
            case .threeMonths: return 14
            }
        }

        /// Bar width as a fraction of the per-day slot. Wider for short
        /// ranges (chunkier bars) so 7d doesn't look like skinny lines.
        var barWidthRatio: CGFloat {
            switch self {
            case .sevenDays: return 0.7
            case .fourteenDays: return 0.65
            case .oneMonth: return 0.6
            case .threeMonths: return 0.55
            }
        }
    }

    @State private var progress: ProgressResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedRange: RangeOption = .oneMonth

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                rangePicker
                rangeHeader
                chartsContent
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedRange) {
            await load()
        }
    }

    // MARK: - Range picker

    private var rangePicker: some View {
        Picker("Range", selection: $selectedRange) {
            ForEach(RangeOption.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    private var rangeHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedRange.headerLabel)
                    .font(.headline)
                if let progress {
                    Text(rangeSubtitle(from: progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rangeSubtitle(from progress: ProgressResponse) -> String {
        let logged = progress.days.filter(\.hasLogs).count
        if logged == 0 { return "No logs in this range yet." }
        return "\(logged) day\(logged == 1 ? "" : "s") logged"
    }

    // MARK: - Charts

    @ViewBuilder
    private var chartsContent: some View {
        if let errorMessage {
            errorCard(errorMessage)
        } else if isLoading && progress == nil {
            loadingCard
        } else if let progress {
            chartCard(
                title: "Calories",
                unit: "kcal",
                color: .green,
                points: progress.days.compactMap { ChartPoint(point: $0, valueKey: .calories) }
            )
            chartCard(
                title: "Protein",
                unit: "g",
                color: .blue,
                points: progress.days.compactMap { ChartPoint(point: $0, valueKey: .protein) }
            )
            chartCard(
                title: "Carbs",
                unit: "g",
                color: .orange,
                points: progress.days.compactMap { ChartPoint(point: $0, valueKey: .carbs) }
            )
            chartCard(
                title: "Fat",
                unit: "g",
                color: .red,
                points: progress.days.compactMap { ChartPoint(point: $0, valueKey: .fat) }
            )
        }
    }

    private func chartCard(
        title: String,
        unit: String,
        color: Color,
        points: [ChartPoint]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let avg = averageConsumed(points: points) {
                    Text("\(Int(avg.rounded())) \(unit) avg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            let scale = chartScale(points: points)

            Chart {
                // Consumed bars — one per logged day. No-log days render
                // nothing here; the target line below still shows.
                ForEach(points.filter(\.hasLogs)) { p in
                    BarMark(
                        x: .value("Date", p.date, unit: .day),
                        y: .value(title, scale.clamp(p.consumed)),
                        width: .ratio(selectedRange.barWidthRatio)
                    )
                    .foregroundStyle(color.gradient)
                    .cornerRadius(3)
                }

                // Target line — dashed, low-emphasis, continuous.
                ForEach(points) { p in
                    LineMark(
                        x: .value("Date", p.date, unit: .day),
                        y: .value("Target", scale.clamp(p.target))
                    )
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [3, 3]))
                    .interpolationMethod(.linear)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: selectedRange.axisStrideDays)) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                    AxisTick().foregroundStyle(Color.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(Self.shortDayFormatter.string(from: date))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .chartYScale(domain: scale.minY ... scale.maxY)
            .frame(height: 160)
            .accessibilityLabel(Text("\(title) chart over \(selectedRange.headerLabel.lowercased())"))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Couldn't load insights", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Data loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        // Don't clear `progress` — keep the previous range visible while
        // the new one loads, so range switches feel responsive.
        defer { isLoading = false }

        let formatter = Self.requestFormatter
        let toDate = Date()
        let fromDate = Calendar.current.date(byAdding: .day, value: -(selectedRange.rawValue - 1), to: toDate) ?? toDate
        let from = formatter.string(from: fromDate)
        let to = formatter.string(from: toDate)
        let tz = TimeZone.current.identifier

        do {
            progress = try await appStore.apiClient.getProgress(from: from, to: to, timezone: tz)
        } catch {
            _ = appStore.handleAuthFailureIfNeeded(error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func averageConsumed(points: [ChartPoint]) -> Double? {
        let logged = points.filter(\.hasLogs).map(\.consumed)
        guard !logged.isEmpty else { return nil }
        return logged.reduce(0, +) / Double(logged.count)
    }

    /// Y-axis scale that fits both consumed peaks and target line, with
    /// a small headroom so bars don't clip against the top edge.
    private func chartScale(points: [ChartPoint]) -> ChartScale {
        let consumed = points.filter(\.hasLogs).map(\.consumed)
        let targets = points.map(\.target)
        let maxValue = max(consumed.max() ?? 0, targets.max() ?? 0)
        guard maxValue > 0 else {
            return ChartScale(minY: 0, maxY: 1)
        }
        let withHeadroom = maxValue * 1.10
        return ChartScale(minY: 0, maxY: withHeadroom)
    }

    // MARK: - Formatters

    private static let requestFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale.current
        f.dateFormat = "MMM d"
        return f
    }()
}

// MARK: - Local types

private struct ChartPoint: Identifiable {
    let date: Date
    let consumed: Double
    let target: Double
    let hasLogs: Bool

    var id: Date { date }

    /// `compactMap`-friendly init: returns nil if the API row's date
    /// can't be parsed, so we never plant a bar at "today" by mistake
    /// (which was the rendering bug in the line-chart version).
    init?(point: ProgressDayPoint, valueKey: ChartValueKey) {
        guard let date = InsightsView.requestFormatterParse(point.date) else {
            return nil
        }
        self.date = date
        switch valueKey {
        case .calories:
            self.consumed = point.totals.calories
            self.target = point.targets.calories
        case .protein:
            self.consumed = point.totals.protein
            self.target = point.targets.protein
        case .carbs:
            self.consumed = point.totals.carbs
            self.target = point.targets.carbs
        case .fat:
            self.consumed = point.totals.fat
            self.target = point.targets.fat
        }
        self.hasLogs = point.hasLogs
    }
}

private enum ChartValueKey {
    case calories, protein, carbs, fat
}

private struct ChartScale {
    let minY: Double
    let maxY: Double

    func clamp(_ v: Double) -> Double {
        max(minY, min(maxY, v))
    }
}

// MARK: - Date parsing helper exposed for ChartPoint

extension InsightsView {
    fileprivate static func requestFormatterParse(_ s: String) -> Date? {
        requestFormatter.date(from: s)
    }
}

#Preview {
    NavigationStack {
        InsightsView()
            .environmentObject(AppStore())
    }
}
