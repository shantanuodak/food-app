import SwiftUI
import UIKit


struct HM00BottomActionDock: View {
    let selectedMode: HomeInputMode
    let needsClarification: Bool
    let onSelectMode: (HomeInputMode) -> Void
    let onOpenDetails: () -> Void

    init(
        selectedMode: HomeInputMode,
        needsClarification: Bool,
        onSelectMode: @escaping (HomeInputMode) -> Void,
        onOpenDetails: @escaping () -> Void
    ) {
        self.selectedMode = selectedMode
        self.needsClarification = needsClarification
        self.onSelectMode = onSelectMode
        self.onOpenDetails = onOpenDetails
    }

    var body: some View {
        HStack(spacing: 12) {
            dockButton(mode: .voice)
            dockButton(mode: .camera)
            dockButton(mode: .manualAdd)
            detailsButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private func dockButton(mode: HomeInputMode) -> some View {
        let isActive = selectedMode == mode

        return Button {
            onSelectMode(isActive ? .text : mode)
        } label: {
            Image(systemName: mode.icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .glassEffect(isActive ? .regular.tint(Color.accentColor).interactive() : .regular.interactive(), in: .rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(mode.title))
    }

    private var detailsButton: some View {
        Button {
            onOpenDetails()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "message")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.primary)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14, style: .continuous))

                if needsClarification {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .offset(x: -2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Open details"))
    }

}

struct HM03ParseSummarySection: View {
    let totals: NutritionTotals
    let hasEditedItems: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.estimatedTotalsTitle)
                .font(.headline)

            HStack(spacing: 10) {
                statPill(title: L10n.totalsCalories, value: totals.calories, fractionDigits: 0)
                statPill(title: L10n.totalsProtein, value: totals.protein, fractionDigits: 1, unit: "g")
            }
            HStack(spacing: 10) {
                statPill(title: L10n.totalsCarbs, value: totals.carbs, fractionDigits: 1, unit: "g")
                statPill(title: L10n.totalsFat, value: totals.fat, fractionDigits: 1, unit: "g")
            }

            if hasEditedItems {
                Text(L10n.totalsEditedHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.08))
        )
    }

    private func statPill(title: String, value: Double, fractionDigits: Int, unit: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                RollingNumberText(value: value, fractionDigits: fractionDigits)
                if !unit.isEmpty {
                    Text(unit)
                }
            }
                .font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.8))
        )
    }
}

struct HM02ParseAndSaveActionsSection: View {
    let isNetworkReachable: Bool
    let networkQualityHint: String
    let isParsing: Bool
    let isSaving: Bool
    let parseDisabled: Bool
    let openDetailsDisabled: Bool
    let saveDisabled: Bool
    let retryDisabled: Bool
    let showSaveDisabledHint: Bool
    let saveSuccessMessage: String?
    let lastTimeToLogLabel: String?
    let saveError: String?
    let idempotencyKeyLabel: String?
    let onParseNow: () -> Void
    let onOpenDetails: () -> Void
    let onSave: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isNetworkReachable {
                Text(L10n.offlineBanner)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if networkQualityHint != L10n.networkOnline {
                Text(networkQualityHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(L10n.parseNowButton) {
                    onParseNow()
                }
                .buttonStyle(.borderedProminent)
                .disabled(parseDisabled)
                .accessibilityLabel(Text(L10n.parseNowButton))
                .accessibilityHint(Text(L10n.parseNowHint))

                Button(L10n.openDetailsButton) {
                    onOpenDetails()
                }
                .buttonStyle(.bordered)
                .disabled(openDetailsDisabled)
                .accessibilityLabel(Text(L10n.openDetailsButton))
                .accessibilityHint(Text(L10n.openDetailsHint))

                if isParsing {
                    ProgressView()
                    Text(L10n.parseInProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button(L10n.saveLogButton) {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(saveDisabled)
                .accessibilityLabel(Text(L10n.saveLogButton))
                .accessibilityHint(Text(L10n.saveLogHint))

                Button(L10n.retryLastSaveButton) {
                    onRetry()
                }
                .buttonStyle(.bordered)
                .disabled(retryDisabled)
                .accessibilityLabel(Text(L10n.retryLastSaveButton))
                .accessibilityHint(Text(L10n.retryLastSaveHint))

                if isSaving {
                    ProgressView()
                    Text(L10n.saveInProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showSaveDisabledHint {
                Text(L10n.saveDisabledNeedsClarification)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let saveSuccessMessage {
                Text(saveSuccessMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }

            if let lastTimeToLogLabel {
                Text(lastTimeToLogLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let saveError {
                Text(saveError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let idempotencyKeyLabel {
                Text(idempotencyKeyLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

struct HM06DaySummarySection: View {
    @Binding var selectedDate: Date
    let maximumDate: Date
    let isLoading: Bool
    let daySummaryError: String?
    let daySummary: DaySummaryResponse?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.daySummaryTitle)
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }

            HStack {
                DatePicker(
                    L10n.daySummaryDateLabel,
                    selection: $selectedDate,
                    in: ...Calendar.current.startOfDay(for: maximumDate),
                    displayedComponents: .date
                )
                    .labelsHidden()
                Text(Self.summaryDisplayFormatter.string(from: selectedDate))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let daySummaryError {
                Text(daySummaryError)
                    .font(.footnote)
                    .foregroundStyle(.red)

                Button(L10n.retrySummaryButton) {
                    onRetry()
                }
                .buttonStyle(.bordered)
            } else if let daySummary {
                if isSummaryEmpty(daySummary) {
                    Text(L10n.daySummaryZeroTotals)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                summaryProgressRow(
                    title: L10n.totalsCalories,
                    consumed: daySummary.totals.calories,
                    target: daySummary.targets.calories,
                    remaining: daySummary.remaining.calories,
                    unit: "kcal"
                )

                summaryProgressRow(
                    title: L10n.totalsProtein,
                    consumed: daySummary.totals.protein,
                    target: daySummary.targets.protein,
                    remaining: daySummary.remaining.protein,
                    unit: "g"
                )

                summaryProgressRow(
                    title: L10n.totalsCarbs,
                    consumed: daySummary.totals.carbs,
                    target: daySummary.targets.carbs,
                    remaining: daySummary.remaining.carbs,
                    unit: "g"
                )

                summaryProgressRow(
                    title: L10n.totalsFat,
                    consumed: daySummary.totals.fat,
                    target: daySummary.targets.fat,
                    remaining: daySummary.remaining.fat,
                    unit: "g"
                )
            } else {
                Text(L10n.loadingDaySummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.08))
        )
    }

    private func summaryProgressRow(
        title: String,
        consumed: Double,
        target: Double,
        remaining: Double,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 0) {
                    RollingNumberText(value: consumed, fractionDigits: 1)
                    Text("/")
                    RollingNumberText(value: target, fractionDigits: 1)
                    Text(" \(unit)")
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressFraction(consumed: consumed, target: target))
                .tint(.green)

            Text(L10n.remainingLabel(max(remaining, 0), unit: unit))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.85))
        )
    }

    private func progressFraction(consumed: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(max(consumed / target, 0), 1)
    }

    private func isSummaryEmpty(_ summary: DaySummaryResponse) -> Bool {
        summary.totals.calories <= 0.05 &&
            summary.totals.protein <= 0.05 &&
            summary.totals.carbs <= 0.05 &&
            summary.totals.fat <= 0.05
    }

    private func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static let summaryDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct HM04ClarificationEscalationSection: View {
    let parseResult: ParseLogResponse
    let isEscalating: Bool
    let escalationInfoMessage: String?
    let escalationError: String?
    let disabledReason: String?
    let canEscalate: Bool
    let onEscalate: () -> Void

    var body: some View {
        if parseResult.needsClarification {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.clarificationNeededTitle)
                    .font(.headline)

                ForEach(Array(parseResult.clarificationQuestions.enumerated()), id: \.offset) { index, question in
                    Text("\(index + 1). \(question)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button(L10n.escalateParseButton) {
                    onEscalate()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!canEscalate)
                .accessibilityLabel(Text(L10n.escalateParseButton))
                .accessibilityHint(Text(L10n.escalateParseHint))

                if isEscalating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L10n.escalatingInProgress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let escalationInfoMessage {
                    Text(escalationInfoMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                if let escalationError {
                    Text(escalationError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let disabledReason {
                    Text(disabledReason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.08))
            )
        } else if let escalationInfoMessage {
            Text(escalationInfoMessage)
                .font(.footnote)
                .foregroundStyle(.green)
        }
    }
}

private enum HomeStreakDrawerRange: Int, CaseIterable, Identifiable {
    case days30 = 30
    case year = 365

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .days30: return "30 Days"
        case .year: return "This Year"
        }
    }
}

struct HomeStreakDrawerView: View {
    @EnvironmentObject private var appStore: AppStore

    @State private var selectedRange: HomeStreakDrawerRange = .days30
    @State private var response: StreakResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedDay: StreakDay?

    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: response?.timezone ?? "") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                Picker("Streak range", selection: $selectedRange) {
                    ForEach(HomeStreakDrawerRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                if !appStore.configuration.progressFeatureEnabled {
                    disabledCard
                } else if isLoading && response == nil {
                    loadingCard
                } else if let response {
                    Group {
                        switch selectedRange {
                        case .days30:
                            StreakContributionCalendarView(
                                days: Array(response.days.reversed()),
                                range: selectedRange,
                                todayKey: todayKey,
                                timezone: response.timezone,
                                selectedDay: $selectedDay
                            )
                        case .year:
                            StreakYearGridView(
                                days: Array(response.days.reversed()),
                                todayKey: todayKey,
                                timezone: response.timezone,
                                selectedDay: $selectedDay
                            )
                        }
                    }
                    .id(selectedRange.rawValue)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))

                    legend
                } else if let errorMessage {
                    errorCard(errorMessage)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .animation(.easeInOut(duration: 0.28), value: selectedRange)
            .animation(.easeInOut(duration: 0.28), value: response?.range)
        }
        .background(Color(.systemBackground))
        .task {
            await loadStreaks()
        }
        .onChange(of: selectedRange) { _, _ in
            selectedDay = nil
            Task { await loadStreaks() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionProgressDidChange)) { _ in
            Task { await loadStreaks() }
        }
        .refreshable {
            await loadStreaks()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(response?.currentDays ?? 0) day streak")
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()

            Text("LONGEST STREAK | \(response?.longestDays ?? 0) \(response?.longestDays == 1 ? "DAY" : "DAYS")")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.primary)
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading streak history...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var disabledCard: some View {
        Text("Streaks are temporarily disabled.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)

            Button("Retry") {
                Task { await loadStreaks() }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Text("Less")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)

            ForEach(0...3, id: \.self) { level in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(StreakContributionCalendarView.color(for: level))
                    .frame(width: 16, height: 16)
            }

            Text("High")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)

            Spacer()
        }
    }

    @MainActor
    private func loadStreaks() async {
        guard appStore.configuration.progressFeatureEnabled else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await appStore.apiClient.getStreaks(
                range: selectedRange.rawValue,
                timezone: TimeZone.current.identifier
            )
            withAnimation(.easeInOut(duration: 0.28)) {
                response = result
            }
        } catch let apiError as APIClientError {
            errorMessage = apiError.errorDescription ?? "Could not load streaks."
        } catch {
            errorMessage = "Could not load streaks."
        }
    }
}

private struct StreakContributionCalendarView: View {
    let days: [StreakDay]
    let range: HomeStreakDrawerRange
    let todayKey: String
    let timezone: String
    @Binding var selectedDay: StreakDay?

    var body: some View {
        let columnCount = range == .year ? 14 : 8
        let spacing: CGFloat = range == .year ? 6 : 10
        let cellRadius: CGFloat = range == .year ? 4 : 6

        let columns = Array(
            repeating: GridItem(.flexible(), spacing: spacing),
            count: columnCount
        )

        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(days, id: \.date) { day in
                StreakDayCell(
                    day: day,
                    cornerRadius: cellRadius,
                    isToday: day.date == todayKey,
                    timezone: timezone,
                    selectedDay: $selectedDay
                )
            }
        }
    }

    static func color(for level: Int) -> Color {
        switch level {
        case 1:
            // Light peach
            return Color(red: 0.99, green: 0.83, blue: 0.65)
        case 2:
            // Pumpkin orange
            return Color(red: 0.96, green: 0.58, blue: 0.20)
        case 3:
            // Burnt sienna
            return Color(red: 0.72, green: 0.36, blue: 0.08)
        default:
            // Neutral beige (no activity)
            return Color(red: 0.91, green: 0.90, blue: 0.86)
        }
    }
}

private struct StreakYearGridView: View {
    let days: [StreakDay]
    let todayKey: String
    let timezone: String
    @Binding var selectedDay: StreakDay?

    var body: some View {
        let groups = Self.groupByMonth(days: days)

        VStack(alignment: .leading, spacing: 20) {
            ForEach(groups, id: \.key) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.label)
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)

                    let columns = Array(
                        repeating: GridItem(.flexible(), spacing: 8),
                        count: 8
                    )
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(group.days, id: \.date) { day in
                            StreakDayCell(
                                day: day,
                                cornerRadius: 5,
                                isToday: day.date == todayKey,
                                timezone: timezone,
                                selectedDay: $selectedDay
                            )
                        }
                    }
                }
            }
        }
    }

    private struct MonthGroup {
        let key: String          // "2026-04"
        let label: String        // "APRIL 2026"
        let days: [StreakDay]    // already in display order (newest first)
    }

    /// Groups a reverse-chronological day list into month buckets, preserving order.
    /// First bucket is the most recent month; days within a bucket stay in input order.
    private static func groupByMonth(days: [StreakDay]) -> [MonthGroup] {
        var groups: [MonthGroup] = []
        var bucket: [StreakDay] = []
        var currentKey: String?

        func flush() {
            guard let key = currentKey, !bucket.isEmpty else { return }
            let label = monthLabel(forKey: key, fallback: bucket.first?.date ?? "")
            groups.append(MonthGroup(key: key, label: label, days: bucket))
            bucket = []
        }

        for day in days {
            let key = String(day.date.prefix(7)) // "yyyy-MM"
            if key != currentKey {
                flush()
                currentKey = key
            }
            bucket.append(day)
        }
        flush()
        return groups
    }

    private static func monthLabel(forKey key: String, fallback: String) -> String {
        if let date = monthKeyFormatter.date(from: key) {
            return monthDisplayFormatter.string(from: date).uppercased()
        }
        return fallback
    }

    private static let monthKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static let monthDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM yyyy"
        return f
    }()
}

private struct StreakDayCell: View {
    let day: StreakDay
    let cornerRadius: CGFloat
    let isToday: Bool
    let timezone: String
    @Binding var selectedDay: StreakDay?

    var body: some View {
        let isSelected = selectedDay?.date == day.date

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(StreakContributionCalendarView.color(for: day.level))
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary, lineWidth: 2)
                    .opacity(isToday ? 1 : 0)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectedDay = isSelected ? nil : day
            }
            .popover(isPresented: Binding(
                get: { isSelected },
                set: { newValue in
                    if !newValue { selectedDay = nil }
                }
            )) {
                StreakDayPopover(day: day, isToday: isToday, timezone: timezone)
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        let foods = day.foodsCount == 1 ? "1 food" : "\(day.foodsCount) foods"
        let suffix = isToday ? ", today" : ""
        return "\(day.date): \(foods)\(suffix)"
    }
}

private struct StreakDayPopover: View {
    let day: StreakDay
    let isToday: Bool
    let timezone: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(formattedDate)
                    .font(.headline)
                if isToday {
                    Text("TODAY")
                        .font(.caption2.weight(.bold))
                        .tracking(1.0)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color(red: 0.96, green: 0.58, blue: 0.20))
                        )
                }
            }

            if day.foodsCount == 0 {
                Text("No foods logged")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(day.foodsCount) \(day.foodsCount == 1 ? "food" : "foods") logged")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if day.logsCount > 1 {
                    Text("Across \(day.logsCount) entries")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 180, alignment: .leading)
    }

    private var formattedDate: String {
        Self.formatDate(day.date, timezone: timezone)
    }

    private static let dateDisplay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = .current
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private static func formatDate(_ value: String, timezone: String) -> String {
        let effectiveTimezone = TimeZone(identifier: timezone) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = effectiveTimezone
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return value }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = effectiveTimezone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let date = calendar.date(from: components) else { return value }
        dateDisplay.timeZone = effectiveTimezone
        return dateDisplay.string(from: date)
    }
}
