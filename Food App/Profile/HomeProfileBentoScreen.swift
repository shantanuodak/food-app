import SwiftUI
import Charts

/// Bento-style profile dashboard. Replaces the legacy `HomeProfileScreen`
/// list as the sheet content when the user taps the greeting chip on the
/// home screen.
///
/// Phase 2: real data wired from `AppStore` via four parallel API calls
/// on appear (`getOnboardingProfile`, `getDaySummary`, `getDayLogs`,
/// `getProgress`). Tiles render with optimistic placeholders while loading
/// so the layout doesn't pop when responses land.
///
/// Drill-down navigation (Phase 4) and per-tile animations (Phase 5) are
/// still pending.
struct HomeProfileBentoScreen: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// Shared draft store passed to drill-down editor screens via the
    /// environment. Body / Diet / Targets all mutate the same draft so
    /// edits in one editor are visible in the next without a refetch.
    @StateObject private var draftStore = ProfileDraftStore()

    @State private var profile: OnboardingProfileResponse?
    @State private var daySummary: DaySummaryResponse?
    @State private var todayLogsCount: Int = 0
    @State private var progress: ProgressResponse?
    @State private var isInitialLoad = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identityRow
                    if let errorMessage {
                        errorBanner(errorMessage)
                    }
                    CalorieHeroTile(data: heroData)
                    HStack(alignment: .top, spacing: 12) {
                        StreakTile(days: streakDays)
                        DailyTargetsTile(targets: targetData)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        BodyTile(info: bodyData)
                        DietTile(diet: dietData)
                    }
                    SevenDayTrendTile(data: trendData)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(BentoTokens.canvas)
            // Cap accessibility text scaling so the dense hero stats grid
            // and ring don't blow out the layout on iPhone SE width.
            // Dynamic Type still scales, just within readable bounds; users
            // can still drill into editor screens which use system Form
            // styling and respect full Dynamic Type natively.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Profile")
                        .font(.custom("InstrumentSerif-Regular", size: 24))
                        .foregroundStyle(BentoTokens.brandGradient)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(BentoTokens.gray700)
                            .frame(width: 30, height: 30)
                            .background(BentoTokens.gray100, in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .environmentObject(draftStore)
        .task {
            await loadAll()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Refresh when the user returns to the app — food may have
            // been logged on another device or the sheet may have been
            // open across a backgrounding.
            if newPhase == .active {
                Task { await loadAll() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileDraftSaved)) { _ in
            // An editor saved — re-fetch the dashboard projections so
            // tile values reflect the new state without waiting for a
            // backgrounding cycle.
            Task { await loadAll() }
        }
    }

    // MARK: - Identity row

    private var identityRow: some View {
        HStack {
            Text(displayName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(BentoTokens.gray900)

            Spacer()

            NavigationLink {
                HomeProfileScreen()
            } label: {
                HStack(spacing: 4) {
                    Text("Manage Account")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(BentoTokens.orange700)
            }
            .buttonStyle(.plain)
        }
    }

    /// Pulled from the auth session. Google / Apple sign-in only gives us
    /// `firstName`; until the backend exposes a full-name field we show
    /// just that, falling back to the email local-part if no firstName.
    private var displayName: String {
        if let first = appStore.authSessionStore.session?.firstName,
           !first.trimmingCharacters(in: .whitespaces).isEmpty {
            return first
        }
        if let email = appStore.authSessionStore.session?.email,
           let local = email.split(separator: "@").first {
            return String(local).capitalized
        }
        return "Your Profile"
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(BentoTokens.gray900)
            Spacer()
            Button("Retry") {
                Task { await loadAll() }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(BentoTokens.orange700)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
    }

    // MARK: - Data loading

    @MainActor
    private func loadAll() async {
        errorMessage = nil
        let today = Date()
        let todayStr = HomeLoggingDateUtils.summaryRequestFormatter.string(from: today)
        let weekStartDate = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
        let weekStartStr = HomeLoggingDateUtils.summaryRequestFormatter.string(from: weekStartDate)
        let tz = TimeZone.current.identifier

        async let profileTask = appStore.apiClient.getOnboardingProfile()
        async let summaryTask = appStore.apiClient.getDaySummary(date: todayStr, timezone: tz)
        async let logsTask = appStore.apiClient.getDayLogs(date: todayStr, timezone: tz)
        async let progressTask = appStore.apiClient.getProgress(from: weekStartStr, to: todayStr, timezone: tz)

        // Each call is allowed to fail independently — we'd rather render
        // a partial dashboard than block on a single bad endpoint.
        let profileResult = try? await profileTask
        let summaryResult = try? await summaryTask
        let logsResult = try? await logsTask
        let progressResult = try? await progressTask

        if profileResult == nil && summaryResult == nil && progressResult == nil {
            errorMessage = "Couldn't load your profile. Pull to retry."
        }

        profile = profileResult ?? profile
        daySummary = summaryResult ?? daySummary
        todayLogsCount = logsResult?.logs.count ?? todayLogsCount
        progress = progressResult ?? progress
        isInitialLoad = false
    }

    // MARK: - View data adapters

    private var heroData: CalorieHeroTile.Data {
        let totals = daySummary?.totals
        let calorieTarget = Double(profile?.calorieTarget ?? 2_500)
        let proteinTarget = profile?.macroTargets.protein ?? 0
        let carbsTarget = profile?.macroTargets.carbs ?? 0
        let fatTarget = profile?.macroTargets.fat ?? 0

        return CalorieHeroTile.Data(
            consumed: totals?.calories ?? 0,
            target: calorieTarget,
            protein: totals?.protein ?? 0,
            proteinTarget: proteinTarget,
            carbs: totals?.carbs ?? 0,
            carbsTarget: carbsTarget,
            fat: totals?.fat ?? 0,
            fatTarget: fatTarget,
            logs: todayLogsCount,
            isLoading: isInitialLoad && totals == nil
        )
    }

    private var streakDays: Int {
        progress?.streaks.currentDays ?? 0
    }

    private var targetData: DailyTargetsTile.Data {
        guard let profile else {
            return DailyTargetsTile.Data(calories: 2_500, protein: 0, carbs: 0, fat: 0, isPlaceholder: true)
        }
        return DailyTargetsTile.Data(
            calories: profile.calorieTarget,
            protein: profile.macroTargets.protein,
            carbs: profile.macroTargets.carbs,
            fat: profile.macroTargets.fat,
            isPlaceholder: false
        )
    }

    private var bodyData: BodyTile.Data {
        guard let profile else {
            return BodyTile.Data(weight: "—", height: "—", goal: "—")
        }
        let units = profile.units
        let weight = profile.weightKg.map { formatWeight(kg: $0, units: units) } ?? "—"
        let height = profile.heightCm.map { formatHeight(cm: $0, units: units) } ?? "—"
        return BodyTile.Data(
            weight: weight,
            height: height,
            goal: L10n.goalLabel(profile.goal)
        )
    }

    private var dietData: DietTile.Data {
        guard let profile else {
            return DietTile.Data(preference: "—", allergiesCount: 0, pace: "—")
        }
        return DietTile.Data(
            preference: dietPrefLabel(profile.dietPreference),
            allergiesCount: profile.allergies.count,
            pace: paceLabel(profile.pace)
        )
    }

    private var trendData: SevenDayTrendTile.Data {
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "en_US_POSIX")
        weekday.dateFormat = "EEE"

        let days: [SevenDayTrendTile.DayPoint] = (progress?.days ?? []).map { day in
            let date = HomeLoggingDateUtils.summaryRequestFormatter.date(from: day.date) ?? Date()
            return SevenDayTrendTile.DayPoint(
                label: weekday.string(from: date),
                value: day.totals.calories,
                logged: day.hasLogs
            )
        }

        let logged = days.filter(\.logged)
        let average = logged.isEmpty ? 0 : Int((logged.reduce(0.0) { $0 + $1.value } / Double(logged.count)).rounded())
        let total = Int(days.reduce(0.0) { $0 + $1.value }.rounded())
        let best = days.max { $0.value < $1.value }?.label ?? "—"
        let target = Double(profile?.calorieTarget ?? 2_500)
        let deltaPct = progress?.weeklyDelta.calories.deltaPct ?? 0

        return SevenDayTrendTile.Data(
            days: days,
            target: target,
            average: average,
            deltaPercent: deltaPct,
            total: total,
            bestDayLabel: best,
            loggedDays: logged.count,
            isLoading: progress == nil && isInitialLoad
        )
    }

    // MARK: - Formatters

    private func formatWeight(kg: Double, units: UnitsOption) -> String {
        let value = HealthKitService.displayWeightValue(kilograms: kg, units: units)
        let label = HealthKitService.weightUnitLabel(for: units)
        return "\(Int(value.rounded())) \(label)"
    }

    private func formatHeight(cm: Double, units: UnitsOption) -> String {
        switch units {
        case .metric:
            return "\(Int(cm.rounded())) cm"
        case .imperial:
            let totalInches = cm / 2.54
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.truncatingRemainder(dividingBy: 12).rounded())
            if inches == 12 {
                return "\(feet + 1)'0\""
            }
            return "\(feet)'\(inches)\""
        }
    }

    private func dietPrefLabel(_ raw: String) -> String {
        if let choice = PreferenceChoice(rawValue: raw) {
            return choice.title
        }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func paceLabel(_ raw: String?) -> String {
        guard let raw, let choice = PaceChoice(rawValue: raw) else { return "—" }
        return choice.title
    }
}

// MARK: - Tiles

/// Hero card — full-width orange gradient, calorie ring + 2×2 macro stats.
private struct CalorieHeroTile: View {
    struct Data {
        let consumed: Double
        let target: Double
        let protein: Double
        let proteinTarget: Int
        let carbs: Double
        let carbsTarget: Int
        let fat: Double
        let fatTarget: Int
        let logs: Int
        let isLoading: Bool
    }

    let data: Data
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        guard data.target > 0 else { return 0 }
        return min(max(data.consumed / data.target, 0), 1)
    }

    private var ringAccessibilityLabel: String {
        let percent = Int((progress * 100).rounded())
        return "\(Int(data.consumed.rounded())) of \(Int(data.target.rounded())) calories, \(percent) percent of goal"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Today's Progress")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.78))

            HStack(spacing: 18) {
                ring
                statsGrid
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                BentoTokens.brandGradient
                RadialGradient(
                    colors: [Color.white.opacity(0.22), .clear],
                    center: .init(x: 0.85, y: 0.1),
                    startRadius: 4,
                    endRadius: 220
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85), value: progress)
        }
        .frame(width: 132, height: 132)
        .overlay {
            VStack(spacing: 6) {
                Text(Int(data.consumed.rounded()).formatted())
                    .font(.system(size: 30, weight: .heavy))
                    .kerning(-0.6)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                Text("of \(Int(data.target.rounded()).formatted()) kcal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ringAccessibilityLabel)
    }

    private var statsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            statCell(
                label: "Protein",
                value: Int(data.protein.rounded()).formatted(),
                suffix: "/ \(data.proteinTarget)g"
            )
            statCell(
                label: "Carbs",
                value: Int(data.carbs.rounded()).formatted(),
                suffix: "/ \(data.carbsTarget)g"
            )
            statCell(
                label: "Fat",
                value: Int(data.fat.rounded()).formatted(),
                suffix: "/ \(data.fatTarget)g"
            )
            statCell(
                label: "Logs",
                value: data.logs.formatted(),
                suffix: nil
            )
        }
    }

    private func statCell(label: String, value: String, suffix: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.78))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .contentTransition(reduceMotion ? .identity : .numericText())
                if let suffix {
                    Text(" \(suffix)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)\(suffix.map { " \($0)" } ?? "")")
    }
}

/// Streak — cream gradient 1×1 with flame emoji and brand-orange day count.
private struct StreakTile: View {
    let days: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("🔥")
                .font(.system(size: 24))
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text("\(days)")
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(BentoTokens.brandGradient)
                .contentTransition(reduceMotion ? .identity : .numericText())
            Text("day streak")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(BentoTokens.gray500)
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bentoTile(
            background: LinearGradient(
                colors: [Color(red: 1.0, green: 0.969, blue: 0.910),
                         Color(red: 1.0, green: 0.878, blue: 0.761)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            border: Color(red: 1.0, green: 0.839, blue: 0.678)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(days == 1 ? "1 day streak" : "\(days) day streak")
    }
}

/// Daily Targets — white card with edit pencil and macro target list.
private struct DailyTargetsTile: View {
    struct Data {
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let isPlaceholder: Bool
    }

    let targets: Data
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var voiceOverSummary: String {
        "Daily targets: \(targets.calories) calories, "
            + "\(targets.protein) grams protein, "
            + "\(targets.carbs) grams carbs, "
            + "\(targets.fat) grams fat"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text("DAILY TARGETS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(BentoTokens.gray500)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(targets.calories.formatted())
                        .font(.system(size: 28, weight: .bold))
                        .contentTransition(reduceMotion ? .identity : .numericText())
                    Text("kcal")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BentoTokens.gray500)
                }
                .foregroundStyle(BentoTokens.gray900)

                VStack(spacing: 8) {
                    targetRow(color: BentoTokens.protein, name: "Protein", value: "\(targets.protein)g")
                    targetRow(color: BentoTokens.carbs,   name: "Carbs",   value: "\(targets.carbs)g")
                    targetRow(color: BentoTokens.fat,     name: "Fat",     value: "\(targets.fat)g")
                }
                .padding(.top, 4)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(targets.isPlaceholder ? 0.5 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(voiceOverSummary)

            editButton
        }
        .bentoTile(background: Color.white, border: BentoTokens.gray100)
    }

    private func targetRow(color: Color, name: String, value: String) -> some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(BentoTokens.gray700)
            }
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BentoTokens.gray900)
        }
    }

    private var editButton: some View {
        NavigationLink {
            TargetsEditorScreen()
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BentoTokens.gray700)
                .frame(width: 30, height: 30)
                .background(BentoTokens.gray100, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit targets")
    }
}

/// Body — light blue tinted card with saturated icon. Tappable.
private struct BodyTile: View {
    struct Data {
        let weight: String
        let height: String
        let goal: String
    }

    /// Named `info` instead of `body` to avoid colliding with `View.body`.
    let info: Data

    var body: some View {
        BentoTappableTile(
            background: LinearGradient(
                colors: [
                    Color(red: 0.933, green: 0.965, blue: 1.0),
                    Color(red: 0.847, green: 0.914, blue: 0.988)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            border: Color(red: 0.227, green: 0.659, blue: 0.969).opacity(0.22)
        ) {
            BodyEditorScreen()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                iconCircle
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)
                Text("Body")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(BentoTokens.gray900)
                    .padding(.bottom, 6)
                statRow(name: "Weight", value: info.weight)
                statRow(name: "Height", value: info.height)
                statRow(name: "Goal",   value: info.goal)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Body. Weight \(info.weight). Height \(info.height). Goal \(info.goal).")
            .accessibilityHint("Opens body details")
        }
    }

    private var iconCircle: some View {
        ZStack {
            LinearGradient(
                colors: [BentoTokens.blue500, BentoTokens.blue700],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "figure.stand")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: BentoTokens.blue700.opacity(0.25), radius: 4, y: 2)
    }

    private func statRow(name: String, value: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(BentoTokens.gray700)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BentoTokens.gray900)
        }
        .padding(.vertical, 2)
    }
}

/// Diet — light green tinted card with saturated icon. Tappable.
private struct DietTile: View {
    struct Data {
        let preference: String
        let allergiesCount: Int
        let pace: String
    }

    let diet: Data

    var body: some View {
        BentoTappableTile(
            background: LinearGradient(
                colors: [
                    Color(red: 0.941, green: 0.984, blue: 0.953),
                    Color(red: 0.847, green: 0.941, blue: 0.878)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            border: Color(red: 0.227, green: 0.812, blue: 0.416).opacity(0.22)
        ) {
            DietEditorScreen()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                iconCircle
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)
                Text("Diet")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(BentoTokens.gray900)
                    .padding(.bottom, 6)
                statRow(name: "Pref",      value: diet.preference)
                statRow(name: "Allergies", value: "\(diet.allergiesCount)")
                statRow(name: "Pace",      value: diet.pace)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Diet. Preference \(diet.preference). \(diet.allergiesCount == 1 ? "1 allergy" : "\(diet.allergiesCount) allergies"). Pace \(diet.pace).")
            .accessibilityHint("Opens food preferences")
        }
    }

    private var iconCircle: some View {
        ZStack {
            LinearGradient(
                colors: [BentoTokens.green500, BentoTokens.green700],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "fork.knife")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: BentoTokens.green700.opacity(0.25), radius: 4, y: 2)
    }

    private func statRow(name: String, value: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(BentoTokens.gray700)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BentoTokens.gray900)
        }
        .padding(.vertical, 2)
    }
}

/// 7-Day Calorie Trend — full-width tappable card with mini Charts bar
/// chart, target reference line, and tap-to-drill into the full
/// `HomeProgressScreen`.
private struct SevenDayTrendTile: View {
    struct DayPoint: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let logged: Bool
    }

    struct Data {
        let days: [DayPoint]
        let target: Double
        let average: Int
        let deltaPercent: Double
        let total: Int
        let bestDayLabel: String
        let loggedDays: Int
        let isLoading: Bool
    }

    let data: Data
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var voiceOverSummary: String {
        var parts: [String] = ["7-day calories"]
        parts.append("\(data.average) average")
        if data.deltaPercent.isFinite, abs(data.deltaPercent) > 0.5 {
            let direction = data.deltaPercent >= 0 ? "up" : "down"
            let pct = Int(abs(data.deltaPercent).rounded())
            parts.append("\(direction) \(pct) percent vs last week")
        }
        parts.append("\(data.total) calories total")
        parts.append("\(data.loggedDays) logged days")
        return parts.joined(separator: ", ")
    }

    var body: some View {
        BentoTappableTile(
            background: Color.white,
            border: BentoTokens.gray100
        ) {
            ProgressSectionView()
                .navigationTitle("Progress")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                header
                if data.days.isEmpty {
                    emptyChart
                } else {
                    chart
                        .padding(.top, 16)
                }
                Divider()
                    .padding(.top, 12)
                footer
                    .padding(.top, 12)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(voiceOverSummary)
            .accessibilityHint("Opens full progress charts")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("7-DAY CALORIES")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(BentoTokens.gray500)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(data.average.formatted())
                            .font(.system(size: 28, weight: .bold))
                            .contentTransition(reduceMotion ? .identity : .numericText())
                        Text("avg")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(BentoTokens.gray500)
                    }
                    .foregroundStyle(BentoTokens.gray900)

                    deltaPill
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Text("See all")
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(BentoTokens.orange700)
        }
    }

    @ViewBuilder
    private var deltaPill: some View {
        if data.deltaPercent.isFinite, abs(data.deltaPercent) > 0.5 {
            let isUp = data.deltaPercent >= 0
            let arrow = isUp ? "↑" : "↓"
            let pct = Int(abs(data.deltaPercent).rounded())
            let bg = isUp
                ? Color(red: 0.898, green: 0.973, blue: 0.918)
                : Color(red: 0.992, green: 0.886, blue: 0.886)
            let fg = isUp
                ? Color(red: 0.102, green: 0.549, blue: 0.204)
                : Color(red: 0.753, green: 0.224, blue: 0.169)
            Text("\(arrow) \(isUp ? "+" : "-")\(pct)%")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(fg)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(bg))
        }
    }

    private var chart: some View {
        Chart {
            ForEach(data.days) { day in
                BarMark(
                    x: .value("Day", day.label),
                    y: .value("kcal", day.value),
                    width: .fixed(22)
                )
                .foregroundStyle(
                    day.logged
                    ? BentoTokens.brandGradientLinear
                    : LinearGradient(
                        colors: [BentoTokens.gray200, BentoTokens.gray200],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(4)
            }
            RuleMark(y: .value("Target", data.target))
                .foregroundStyle(BentoTokens.gray400)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("\(Int(data.target).formatted()) TARGET")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.3)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(BentoTokens.gray900)
                        )
                }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisValueLabel()
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BentoTokens.gray500)
            }
        }
        .frame(height: 140)
    }

    private var emptyChart: some View {
        HStack {
            Spacer()
            Text(data.isLoading ? "Loading…" : "No logs in this range")
                .font(.system(size: 12))
                .foregroundStyle(BentoTokens.gray500)
            Spacer()
        }
        .frame(height: 140)
        .padding(.top, 16)
    }

    private var footer: some View {
        HStack {
            footerStat(value: data.total.formatted(), label: "kcal total")
            Spacer()
            HStack(spacing: 4) {
                Text("Best ·")
                    .font(.system(size: 11))
                    .foregroundStyle(BentoTokens.gray700)
                Text(data.bestDayLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BentoTokens.gray900)
            }
            Spacer()
            footerStat(value: "\(data.loggedDays)", label: "logged days")
        }
    }

    private func footerStat(value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BentoTokens.gray900)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(BentoTokens.gray700)
        }
    }
}

// MARK: - Shared tile chrome

/// Common bento-card chrome: rounded corners, padding, border, soft shadow.
/// Accepts any `ShapeStyle` for the background so callers can pass solid
/// colors or gradients without conditional wrappers.
private struct BentoTileBackground<Background: ShapeStyle, Border: ShapeStyle>: ViewModifier {
    let background: Background
    let border: Border

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

private extension View {
    func bentoTile<B: ShapeStyle, S: ShapeStyle>(background: B, border: S) -> some View {
        modifier(BentoTileBackground(background: background, border: border))
    }
}

/// Tappable bento tile that pushes a destination onto the parent
/// `NavigationStack`. Uses `NavigationLink` so the system handles the
/// transition + back navigation. Press-state scale animation comes from
/// `BentoPressScaleStyle` applied to the underlying Button label.
private struct BentoTappableTile<Background: ShapeStyle, Border: ShapeStyle, Destination: View, Content: View>: View {
    let background: Background
    let border: Border
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let label: () -> Content

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            ZStack(alignment: .topTrailing) {
                label()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BentoTokens.gray400)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(BentoPressScaleStyle())
        .bentoTile(background: background, border: border)
    }
}

/// Subtle scale-down on press for tappable tiles. Keeps the Apple-style
/// "card responds to touch" feel without a heavy ripple. Respects the
/// system "Reduce Motion" accessibility setting.
private struct BentoPressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BentoPressScaleBody(configuration: configuration)
    }

    private struct BentoPressScaleBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

// MARK: - Tokens

/// Color + gradient palette for the bento dashboard. Mirrors the HTML
/// prototype's palette so visual debugging between the two stays simple.
private enum BentoTokens {
    // Brand orange
    static let orange500 = Color(red: 1.00, green: 0.624, blue: 0.200)
    static let orange700 = Color(red: 0.902, green: 0.361, blue: 0.102)

    // Macros
    static let protein = Color(red: 0.227, green: 0.659, blue: 0.969)
    static let carbs   = Color(red: 0.961, green: 0.647, blue: 0.141)
    static let fat     = Color(red: 0.937, green: 0.267, blue: 0.267)

    // Body / Diet accents (saturated for icon circles)
    static let blue500  = Color(red: 0.227, green: 0.659, blue: 0.969)
    static let blue700  = Color(red: 0.047, green: 0.388, blue: 0.690)
    static let green500 = Color(red: 0.227, green: 0.812, blue: 0.416)
    static let green700 = Color(red: 0.102, green: 0.490, blue: 0.227)

    // Surfaces
    static let canvas   = Color(uiColor: .systemGroupedBackground)

    // Grays (mirror HTML --gray-*)
    static let gray100 = Color(red: 0.945, green: 0.953, blue: 0.961)
    static let gray200 = Color(red: 0.914, green: 0.925, blue: 0.937)
    static let gray400 = Color(red: 0.678, green: 0.710, blue: 0.741)
    static let gray500 = Color(red: 0.525, green: 0.557, blue: 0.588)
    static let gray700 = Color(red: 0.286, green: 0.314, blue: 0.341)
    static let gray900 = Color(red: 0.129, green: 0.145, blue: 0.161)

    // Gradients
    static let brandGradient = LinearGradient(
        colors: [orange500, orange700],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Vertical orange→deep-orange for chart bars (matches the prototype
    /// trend chart bars which fade darker top-to-bottom).
    static let brandGradientLinear = LinearGradient(
        colors: [orange500, orange700],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Preview

#Preview {
    HomeProfileBentoScreen()
        .environmentObject(AppStore())
}
