import SwiftUI
import Charts

/// Insights — 30-day adherence charts for the four nutrition metrics.
/// Reachable from the Profile's Insights hub row.
///
/// Data source: `GET /v1/logs/progress`. The endpoint already returns the
/// per-day totals, targets, and `hasLogs` flag we need; this view does
/// not introduce any new backend surface.
///
/// Design intent (Tier 1 #8):
/// - Plain, short headers — one chart per metric, stacked vertically.
/// - Consumed line in metric color; target as a dashed gray rule.
/// - Days with no logs render as gaps (not zeros), so a missed day
///   doesn't visually equal "ate zero."
/// - Fixed 30-day range. No range picker in this MVP cut.
/// - Steps chart deliberately deferred to Tier 2 (#8 add-on); it needs
///   either a new `/v1/health/activity-range` endpoint or an on-device
///   HealthKit range read — out of scope for May 6.
struct InsightsView: View {
    @EnvironmentObject private var appStore: AppStore

    @State private var progress: ProgressResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let rangeDays = 30

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                rangeHeader
                chartsContent
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadIfNeeded()
        }
    }

    // MARK: - Header

    private var rangeHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Last \(rangeDays) days")
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
                points: progress.days.map { ChartPoint(point: $0, valueKey: .calories) }
            )
            chartCard(
                title: "Protein",
                unit: "g",
                color: .blue,
                points: progress.days.map { ChartPoint(point: $0, valueKey: .protein) }
            )
            chartCard(
                title: "Carbs",
                unit: "g",
                color: .orange,
                points: progress.days.map { ChartPoint(point: $0, valueKey: .carbs) }
            )
            chartCard(
                title: "Fat",
                unit: "g",
                color: .red,
                points: progress.days.map { ChartPoint(point: $0, valueKey: .fat) }
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

            // Days with no logs are rendered as gaps so a missed day
            // doesn't read as "ate zero."
            let consumedSegments = segmentedLoggedPoints(from: points)
            let scale = chartScale(points: points)

            Chart {
                // Consumed (segmented to break across no-log days)
                ForEach(consumedSegments) { segment in
                    ForEach(segment.points) { p in
                        LineMark(
                            x: .value("Date", p.date),
                            y: .value(title, scale.clamp(p.consumed))
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .interpolationMethod(.monotone)
                    }
                }

                // Target line — dashed, low-emphasis. Continuous across
                // the full range (target doesn't have gaps).
                ForEach(points) { p in
                    LineMark(
                        x: .value("Date", p.date),
                        y: .value("Target", scale.clamp(p.target))
                    )
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [3, 3]))
                    .interpolationMethod(.linear)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, rangeDays / 5))) { value in
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
            .frame(height: 140)
            .accessibilityLabel("\(title) chart over the last \(rangeDays) days")
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
                Task { await loadIfNeeded(force: true) }
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

    private func loadIfNeeded(force: Bool = false) async {
        if isLoading { return }
        if progress != nil && !force { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let formatter = Self.requestFormatter
        let toDate = Date()
        let fromDate = Calendar.current.date(byAdding: .day, value: -(rangeDays - 1), to: toDate) ?? toDate
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

    /// Splits the points into runs of consecutive logged days, separated
    /// by no-log days. Lets the consumed line render as multiple short
    /// segments instead of dipping to zero on missed days.
    private func segmentedLoggedPoints(from points: [ChartPoint]) -> [ChartSegment] {
        var segments: [ChartSegment] = []
        var current: [ChartPoint] = []
        for p in points {
            if p.hasLogs {
                current.append(p)
            } else if !current.isEmpty {
                segments.append(ChartSegment(points: current))
                current = []
            }
        }
        if !current.isEmpty {
            segments.append(ChartSegment(points: current))
        }
        return segments
    }

    /// Y-axis scale that fits both consumed peaks and target line, with
    /// a small headroom so lines aren't clipped against the top edge.
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

    /// Macro extractor — closure-based to keep the four chart calls
    /// concise and avoid duplicating slice logic for each metric.
    init(point: ProgressDayPoint, valueKey: ChartValueKey) {
        let date = InsightsView.requestFormatterParse(point.date) ?? Date()
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

private struct ChartSegment: Identifiable {
    let id = UUID()
    let points: [ChartPoint]
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
