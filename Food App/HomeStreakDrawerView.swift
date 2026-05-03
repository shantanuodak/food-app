import SwiftUI

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
