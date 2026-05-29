import SwiftUI
import Charts
import Combine
import CoreMotion
import UIKit

/// Drives the device-tilt parallax on premium cards. Reads
/// `CMMotionManager.deviceMotion` at 30 Hz, low-pass filters the roll/pitch,
/// and publishes normalized values in -1...1. Callers multiply by a per-layer
/// intensity (pt) to get the layer's offset. Respects reduce-motion: the
/// caller is responsible for not calling `start()` when reduce-motion is on.
@MainActor
final class DeviceTiltMotion: ObservableObject {
    @Published var roll: Double = 0
    @Published var pitch: Double = 0

    private let manager = CMMotionManager()
    /// Low-pass filter coefficient. 0.18 keeps motion smooth without lag.
    private let smoothing = 0.18
    /// Clamp tilt to ±0.5 rad (~28°) so the normalized output stays bounded.
    private let clampRadians = 0.5

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        guard !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let clampedRoll = max(-self.clampRadians, min(self.clampRadians, motion.attitude.roll))
            let clampedPitch = max(-self.clampRadians, min(self.clampRadians, motion.attitude.pitch))
            let normalizedRoll = clampedRoll / self.clampRadians
            let normalizedPitch = clampedPitch / self.clampRadians
            self.roll += self.smoothing * (normalizedRoll - self.roll)
            self.pitch += self.smoothing * (normalizedPitch - self.pitch)
        }
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
        roll = 0
        pitch = 0
    }

    deinit {
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
    }
}

/// Bento-style profile dashboard. Replaces the legacy `HomeProfileScreen`
/// list as the sheet content when the user taps the greeting chip on the
/// home screen.
///
/// Phase 2: real data is warmed by `AppStore` while the user is on Home.
/// The sheet paints from that snapshot immediately, then quietly refreshes
/// so calorie/progress changes made just before opening still reconcile.
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
    @State private var streaks: StreakResponse?
    @State private var isInitialLoad = true
    @State private var errorMessage: String?
    @State private var isReminderSettingsPresented = false
    @State private var isManageAccountPresented = false
    @State private var avatarImageData: Data?
    @State private var isAvatarSourceDialogPresented = false
    @State private var isAvatarImagePickerPresented = false
    @State private var avatarImagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppDrawerHeader(onClose: { dismiss() }) {
                    Text("Profile")
                        .font(.custom("InstrumentSerif-Regular", size: 31))
                        .foregroundStyle(BentoTokens.orange700)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ProfileHeroCard(
                            firstName: appStore.authSessionStore.session?.firstName,
                            lastName: appStore.authSessionStore.session?.lastName,
                            displayName: displayName,
                            email: appStore.authSessionStore.session?.email,
                            bodyLine: profileBodyLine,
                            preferencesCount: profilePreferencesCount,
                            allergiesCount: profileAllergiesCount,
                            avatarImageData: avatarImageData,
                            onEdit: { isManageAccountPresented = true },
                            onAvatarTapped: { isAvatarSourceDialogPresented = true }
                        )

                        if let errorMessage {
                            errorBanner(errorMessage)
                        }
                        // 2026-05-22 (Phase F, Item 7): Today's calorie ring
                        // was moved out of the bento profile and into the
                        // Insights screen as the new top card. Keeping the
                        // streak indicator inside the dock + macros + diet
                        // tiles here means the bento still feels like a
                        // dashboard, without doubling up the calorie hero
                        // on every glance.
                        SavedMealsTile()
                        RecipesTile()
                        HStack(alignment: .top, spacing: 12) {
                            NavigationLink {
                                BadgesTrophyCaseView(currentStreakDays: streakDays)
                            } label: {
                                BadgeTile(days: streakDays)
                            }
                            .buttonStyle(.plain)

                            NotificationReminderTile(
                                summary: reminderSummaryText,
                                isEnabled: reminderEnabledBinding,
                                onOpenSettings: { isReminderSettingsPresented = true }
                            )
                        }
                        HStack(alignment: .top, spacing: 12) {
                            LoggingTipsTile()
                            WidgetSetupTile()
                        }
                        DietTile(diet: dietData)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
            }
            .scrollIndicators(.hidden)
            .background(AppDrawerSurface.gradient)
            // Cap accessibility text scaling so the dense hero stats grid
            // and ring don't blow out the layout on iPhone SE width.
            // Dynamic Type still scales, just within readable bounds; users
            // can still drill into editor screens which use system Form
            // styling and respect full Dynamic Type natively.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .navigationDestination(isPresented: $isReminderSettingsPresented) {
                NotificationReminderSettingsView()
            }
            .sheet(isPresented: $isManageAccountPresented) {
                NavigationStack {
                    HomeProfileScreen()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
            .confirmationDialog(
                "Profile picture",
                isPresented: $isAvatarSourceDialogPresented,
                titleVisibility: .visible
            ) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") {
                        avatarImagePickerSourceType = .camera
                        isAvatarImagePickerPresented = true
                    }
                }

                Button("Choose Photo") {
                    avatarImagePickerSourceType = .photoLibrary
                    isAvatarImagePickerPresented = true
                }

                if avatarImageData != nil {
                    Button("Remove Photo", role: .destructive) {
                        removeProfileAvatar()
                    }
                }

                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $isAvatarImagePickerPresented) {
                HomeImagePicker(
                    sourceType: avatarImagePickerSourceType,
                    onImagePicked: { image in
                        saveProfileAvatar(image)
                    },
                    onCancel: {}
                )
            }
        }
        .environmentObject(draftStore)
        .presentationBackground(AppDrawerSurface.gradient)
        .task {
            loadProfileAvatar()
            applyCachedSnapshotIfAvailable()
            await loadAll()
        }
        .onChange(of: appStore.authSessionStore.session?.userID) { _, _ in
            loadProfileAvatar()
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

    private func loadProfileAvatar() {
        avatarImageData = ProfileAvatarStore.loadAvatarData(userID: appStore.authSessionStore.session?.userID)
    }

    private func saveProfileAvatar(_ image: UIImage) {
        if let data = ProfileAvatarStore.saveAvatar(image, userID: appStore.authSessionStore.session?.userID) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                avatarImageData = data
            }
        }
    }

    private func removeProfileAvatar() {
        ProfileAvatarStore.removeAvatar(userID: appStore.authSessionStore.session?.userID)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            avatarImageData = nil
        }
    }

    // MARK: - Identity row

    private var identityRow: some View {
        HStack {
            Text(displayName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(BentoTokens.gray900)

            Spacer()

            Button {
                isManageAccountPresented = true
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
        let session = appStore.authSessionStore.session
        let first = session?.firstName?.trimmingCharacters(in: .whitespaces) ?? ""
        let last  = session?.lastName?.trimmingCharacters(in: .whitespaces) ?? ""

        if !first.isEmpty && !last.isEmpty {
            return "\(first) \(last)"
        }
        if !first.isEmpty { return first }
        if let email = session?.email, let local = email.split(separator: "@").first {
            return String(local).capitalized
        }
        return "Your Profile"
    }

    /// One-line summary of body details for the ProfileHeroCard. Skips
    /// any fields the profile response doesn't have so the line never
    /// shows orphan separators. Empty string means "no body data yet" —
    /// the card hides the line instead of rendering an empty row.
    private var profileBodyLine: String {
        guard let profile else { return "" }
        var parts: [String] = []

        if let age = profile.age { parts.append("\(age)") }
        if let sexRaw = profile.sex?.trimmingCharacters(in: .whitespaces),
           !sexRaw.isEmpty {
            parts.append(sexRaw.capitalized)
        }
        if let cm = profile.heightCm, cm > 0 {
            parts.append(formattedHeight(cm: cm, units: profile.units))
        }
        if let kg = profile.weightKg, kg > 0 {
            parts.append(formattedWeight(kg: kg, units: profile.units))
        }

        return parts.joined(separator: " · ")
    }

    private var profilePreferencesCount: Int {
        guard let raw = profile?.dietPreference else { return 0 }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.lowercased() == "none" { return 0 }
        return trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .count
    }

    private var profileAllergiesCount: Int {
        profile?.allergies.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count ?? 0
    }

    private func formattedHeight(cm: Double, units: UnitsOption) -> String {
        if units == .metric {
            return "\(Int(cm.rounded())) cm"
        }
        let totalInches = cm / 2.54
        let feet = Int(totalInches / 12)
        let inches = Int(totalInches.rounded()) - feet * 12
        return "\(feet)'\(inches)\""
    }

    private func formattedWeight(kg: Double, units: UnitsOption) -> String {
        if units == .metric {
            return "\(Int(kg.rounded())) kg"
        }
        let lb = kg * 2.20462
        return "\(Int(lb.rounded())) lb"
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BentoTokens.orange700)
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
                .fill(BentoTokens.warningSurface)
        )
    }

    // MARK: - Data loading

    @MainActor
    private func applyCachedSnapshotIfAvailable() {
        let todayStr = HomeLoggingDateUtils.summaryRequestFormatter.string(from: Date())
        let tz = TimeZone.current.identifier
        guard let snapshot = appStore.profileDashboardSnapshot,
              snapshot.isUsable(for: todayStr, timezone: tz, maxAge: 10 * 60) else {
            return
        }

        profile = snapshot.profile ?? profile
        daySummary = snapshot.daySummary ?? daySummary
        todayLogsCount = snapshot.todayLogsCount ?? todayLogsCount
        progress = snapshot.progress ?? progress
        streaks = snapshot.streaks ?? streaks
        isInitialLoad = false
    }

    @MainActor
    private func loadAll() async {
        errorMessage = nil
        await appStore.refreshProfileDashboardSnapshot()
        let snapshot = appStore.profileDashboardSnapshot
        let profileResult = snapshot?.profile
        let summaryResult = snapshot?.daySummary
        let logsCountResult = snapshot?.todayLogsCount
        let progressResult = snapshot?.progress
        let streaksResult = snapshot?.streaks

        if profileResult == nil && summaryResult == nil && progressResult == nil && streaksResult == nil {
            errorMessage = "Couldn't load your profile. Pull to retry."
        }

        profile = profileResult ?? profile
        daySummary = summaryResult ?? daySummary
        todayLogsCount = logsCountResult ?? todayLogsCount
        progress = progressResult ?? progress
        streaks = streaksResult ?? streaks
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
        streaks?.currentDays ?? progress?.streaks.currentDays ?? 0
    }

    private var reminderSummaryText: String {
        let settings = appStore.mealReminderSettings
        guard settings.remindersEnabled else { return "Off" }

        let selected = [
            settings.breakfastEnabled ? "Breakfast" : nil,
            settings.lunchEnabled ? "Lunch" : nil,
            settings.dinnerEnabled ? "Dinner" : nil
        ].compactMap { $0 }

        if selected.isEmpty { return "No windows selected" }
        return selected.joined(separator: ", ")
    }

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { appStore.mealReminderSettings.remindersEnabled },
            set: { isEnabled in
                updateReminderEnabledFromProfileCard(isEnabled)
            }
        )
    }

    private func updateReminderEnabledFromProfileCard(_ isEnabled: Bool) {
        guard isEnabled else {
            appStore.setMealRemindersEnabled(false)
            return
        }

        Task {
            await appStore.refreshNotificationAuthState()

            switch appStore.notificationAuthState {
            case .authorized, .provisional, .ephemeral:
                appStore.setMealRemindersEnabled(true)
            case .notDetermined:
                let status = await appStore.requestNotificationAuthorization()
                switch status {
                case .authorized, .provisional, .ephemeral:
                    appStore.setMealRemindersEnabled(true)
                default:
                    appStore.setMealRemindersEnabled(false)
                    return
                }
            case .denied:
                appStore.setMealRemindersEnabled(false)
                await MainActor.run {
                    openAppNotificationSettings()
                }
                return
            default:
                appStore.setMealRemindersEnabled(false)
                return
            }

            await MainActor.run {
                isReminderSettingsPresented = true
            }
        }
    }

    private func openAppNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var dietData: DietTile.Data {
        guard let profile else {
            return DietTile.Data(preferencesCount: 0, allergiesCount: 0, pace: "—")
        }
        return DietTile.Data(
            preferencesCount: dietPreferenceCount(profile.dietPreference),
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

    private func dietPreferenceCount(_ raw: String) -> Int {
        raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { value in
                !value.isEmpty &&
                value != "none" &&
                value != PreferenceChoice.noPreference.rawValue
            }
            .count
    }

    private func paceLabel(_ raw: String?) -> String {
        guard let raw, let choice = PaceChoice(rawValue: raw) else { return "—" }
        return choice.title
    }
}

// MARK: - Tiles

/// Hero card — full-width warm gradient, calorie ring + 2×2 macro stats.
struct CalorieHeroTile: View {
    struct Data {
        /// Build the hero data from the shared dashboard snapshot. Mirrors
        /// the construction inside HomeProfileBentoScreen so the Insights
        /// surface (Item 7, 2026-05-22) renders identically without
        /// duplicating the adapter logic.
        static func from(snapshot: ProfileDashboardSnapshot?, isInitialLoad: Bool) -> Data {
            let totals = snapshot?.daySummary?.totals
            let profile = snapshot?.profile
            let calorieTarget = Double(profile?.calorieTarget ?? 2_500)
            let proteinTarget = profile?.macroTargets.protein ?? 0
            let carbsTarget = profile?.macroTargets.carbs ?? 0
            let fatTarget = profile?.macroTargets.fat ?? 0

            return Data(
                consumed: totals?.calories ?? 0,
                target: calorieTarget,
                protein: totals?.protein ?? 0,
                proteinTarget: proteinTarget,
                carbs: totals?.carbs ?? 0,
                carbsTarget: carbsTarget,
                fat: totals?.fat ?? 0,
                fatTarget: fatTarget,
                logs: snapshot?.todayLogsCount ?? 0,
                isLoading: isInitialLoad && totals == nil
            )
        }

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
    /// Drives the Daily Targets editor sheet when the user taps the tile or
    /// the pencil glyph. Owned locally so the tile works regardless of
    /// whether the parent has a NavigationStack (the Insights screen does
    /// not, which is why the previous NavigationLink-based pencil button
    /// was a no-op there).
    @State private var isTargetsEditorPresented: Bool = false
    /// Local draft store so TargetsEditorScreen always has the
    /// @EnvironmentObject it needs when presented from this tile.
    @StateObject private var heroDraftStore: ProfileDraftStore = ProfileDraftStore()
    /// Device-tilt parallax source. Drives the multi-layer shift on the
    /// hero card — background highlight, specular sweep, and ring/macros
    /// each respond at different intensities so the card reads as 3D.
    @StateObject private var tilt = DeviceTiltMotion()

    private var progress: Double {
        guard data.target > 0 else { return 0 }
        return min(max(data.consumed / data.target, 0), 1)
    }

    private var ringAccessibilityLabel: String {
        let percent = Int((progress * 100).rounded())
        return "\(Int(data.consumed.rounded())) of \(Int(data.target.rounded())) calories, \(percent) percent of goal"
    }

    private var percentText: String {
        "\(Int((progress * 100).rounded()))%"
    }

    private var remainingKcal: Int {
        max(0, Int((data.target - data.consumed).rounded()))
    }

    /// Short motivational line that adapts to where the user is on the
    /// calorie goal. Keep tone warm + brief — this is glance content, not
    /// a coaching lecture. Updates immediately when progress changes
    /// because it's a derived view.
    private var motivationalCopy: String {
        let percent = progress
        if percent <= 0 { return "Log your first meal" }
        if percent < 0.25 { return "Off to a fresh start" }
        if percent < 0.5 { return "Cruising along" }
        if percent < 0.75 { return "Past the halfway mark" }
        if percent < 1.0 { return "Almost at your goal" }
        return "Goal hit — nice work"
    }

    // 2026-05-23 (revision 2): swapped translate-based parallax for a true
    // 3D tilt. The card rotates around both X (pitch) and Y (roll) axes in
    // response to phone orientation — diagonal phone tilt produces diagonal
    // card tilt. Max ±10° on each axis keeps it expressive but never breaks
    // readability. Perspective 0.55 gives a real depth illusion (front edge
    // looks bigger, back edge recedes).
    private let cardTiltDegrees: Double = 10
    private let cardPerspective: CGFloat = 0.55

    private var parallaxEnabled: Bool { !reduceMotion }

    var body: some View {
        Button(action: { isTargetsEditorPresented = true }) {
            ZStack {
                premiumBackground
                premiumContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                // Top-edge rim light + warm border — adds the "lifted off the
                // surface" feel without darkening the bottom of the card.
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.48),
                                .white.opacity(0.10),
                                .black.opacity(0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            // Elevation: a broad warm orange cast + a closer black depth
            // shadow. Together they read as a real card floating above the
            // cream Insights surface.
            .shadow(color: Color(red: 0.95, green: 0.42, blue: 0.18).opacity(0.34), radius: 22, y: 14)
            .shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            // True 3D card tilt — rotates the card around both X (pitch)
            // and Y (roll) axes in response to phone orientation. Tilt the
            // phone diagonally and the card tilts diagonally. Roll axis is
            // negated so leaning the phone right shows the card's right
            // edge lifting toward the user (matches Apple Card / Wallet
            // tilt behavior).
            .rotation3DEffect(
                .degrees(parallaxEnabled ? -cardTiltDegrees * tilt.roll : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: cardPerspective
            )
            .rotation3DEffect(
                .degrees(parallaxEnabled ? cardTiltDegrees * tilt.pitch : 0),
                axis: (x: 1, y: 0, z: 0),
                perspective: cardPerspective
            )
            .animation(.easeOut(duration: 0.20), value: tilt.roll)
            .animation(.easeOut(duration: 0.20), value: tilt.pitch)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Today's progress. Tap to edit daily targets.")
        .onAppear {
            if parallaxEnabled { tilt.start() }
        }
        .onDisappear { tilt.stop() }
        .onChange(of: reduceMotion) { _, newValue in
            if newValue { tilt.stop() } else { tilt.start() }
        }
        .sheet(isPresented: $isTargetsEditorPresented) {
            NavigationStack {
                TargetsEditorScreen()
                    .navigationTitle("Daily targets")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { isTargetsEditorPresented = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
            .environmentObject(heroDraftStore)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Saturated brand gradient + a single soft spotlight in the top-right.
    /// 2026-05-23 revision: dropped the ultra-thin material + opposite-
    /// direction specular sweep — those layers were dulling the orange and
    /// making the per-layer parallax look jittery. Pure gradient + static
    /// highlight reads more vivid, and the whole-card translation gives the
    /// motion feel without the layered jitter.
    private var premiumBackground: some View {
        ZStack {
            // Boosted-saturation brand orange gradient. Slightly more
            // vivid than BentoTokens.heroGradient — punches up the card so
            // the rim light and shadows still read as "lifted" without a
            // glass overlay damping the color.
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.65, blue: 0.22),
                    Color(red: 0.98, green: 0.48, blue: 0.16),
                    Color(red: 0.93, green: 0.36, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Soft spotlight in the top-right corner. Static (no
            // counter-parallax) so it always feels like the light source
            // is "above" — the whole-card translation moves this with the
            // rest of the card, which reads correctly.
            RadialGradient(
                colors: [Color.white.opacity(0.34), .clear],
                center: .init(x: 0.85, y: 0.08),
                startRadius: 4,
                endRadius: 260
            )
        }
    }

    /// Foreground content — no internal parallax. The whole card translates
    /// together as one unit (see body's `.offset`).
    private var premiumContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Text("Today's Progress")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.86))

                Spacer()

                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.20), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.28), lineWidth: 0.75)
                    }
                    .accessibilityHidden(true)
            }

            HStack(alignment: .center, spacing: 18) {
                ring
                statsGrid
            }

            motivationalRow
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 22)
    }

    private var motivationalRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))

            Text(motivationalCopy)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            if remainingKcal > 0 && data.target > 0 {
                Text("\(remainingKcal.formatted()) to go")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.18), in: Capsule())
                    .overlay(
                        Capsule().stroke(.white.opacity(0.22), lineWidth: 0.75)
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(motivationalCopy). \(remainingKcal) calories remaining.")
    }

    private var ring: some View {
        ZStack {
            // Background track — softer so the white fill pops.
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 15)

            // Progress fill.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: .white.opacity(0.38), radius: 7, y: 2)
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85), value: progress)

            // Endpoint dot — small white pebble at the end of the fill,
            // with a soft glow so the eye lands on it. Hidden when there
            // is no progress to mark.
            if progress > 0.02 {
                endpointDot
                    .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85), value: progress)
            }
        }
        .frame(width: 158, height: 158)
        .overlay {
            VStack(spacing: 5) {
                Text(percentText)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .tracking(0.5)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.20), in: Capsule())
                    .overlay(
                        Capsule().stroke(.white.opacity(0.26), lineWidth: 0.75)
                    )

                Text(Int(data.consumed.rounded()).formatted())
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .kerning(-0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .padding(.horizontal, 22)
                    .contentTransition(reduceMotion ? .identity : .numericText())

                Text("of \(Int(data.target.rounded()).formatted()) kcal")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ringAccessibilityLabel)
    }

    /// Small white dot positioned at the end of the progress arc, with a
    /// soft outer glow. Tracks `progress` so it slides smoothly along the
    /// ring when calories are added.
    private var endpointDot: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let angle = (progress * 2 * .pi) - (.pi / 2)
            let dotX = center.x + cos(angle) * radius
            let dotY = center.y + sin(angle) * radius

            ZStack {
                Circle()
                    .fill(.white.opacity(0.28))
                    .frame(width: 22, height: 22)
                    .blur(radius: 4)
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .white.opacity(0.42), radius: 4)
            }
            .position(x: dotX, y: dotY)
        }
        .accessibilityHidden(true)
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
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.82))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .contentTransition(reduceMotion ? .identity : .numericText())
                if let suffix {
                    Text(" \(suffix)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.74))
                }
            }
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)\(suffix.map { " \($0)" } ?? "")")
    }
}

/// Full-width resource card that reopens the food logging guidance experience.
private struct LoggingTipsTile: View {
    var body: some View {
        BentoTappableTile(
            background: BentoTokens.whiteTileBackground,
            border: BentoTokens.whiteTileBorder
        ) {
            FoodLoggingTipsView()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                iconStack
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)

                Text("Logging tips")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(BentoTokens.gray900)
                    .lineLimit(2)

                Text("Tiny details make estimates sharper.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BentoTokens.gray700)
                    .lineLimit(3)
                    .padding(.top, 6)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 146, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Logging tips. Tiny details make estimates sharper.")
            .accessibilityHint("Opens examples for better food logging.")
        }
    }

    private var iconStack: some View {
        Image(systemName: "sparkle.magnifyingglass")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(BentoTokens.orange700)
            .frame(width: 42, height: 42, alignment: .leading)
    }
}

/// Saved meals — management entry for repeat foods. Logging shortcuts stay in
/// the logging flow; this card is for reviewing and organizing.
private struct SavedMealsTile: View {
    var body: some View {
        BentoTappableTile(
            background: BentoTokens.whiteTileBackground,
            border: BentoTokens.whiteTileBorder
        ) {
            SavedMealsScreen()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "bookmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(BentoTokens.orange700)
                    .frame(width: 42, height: 42, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Saved Meals")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(BentoTokens.gray900)

                    Text("Keep repeat meals ready without retyping.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BentoTokens.gray700)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Saved Meals. Keep repeat meals ready without retyping.")
            .accessibilityHint("Opens saved meals")
        }
    }
}

/// Recipes — imported web recipes live separately from repeat logged meals.
private struct RecipesTile: View {
    var body: some View {
        BentoTappableTile(
            background: BentoTokens.whiteTileBackground,
            border: BentoTokens.whiteTileBorder
        ) {
            RecipesScreen()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "book.closed")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(BentoTokens.orange700)
                    .frame(width: 42, height: 42, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Recipes")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(BentoTokens.gray900)

                    Text("Review recipes imported from the web.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BentoTokens.gray700)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recipes. Review recipes imported from the web.")
            .accessibilityHint("Opens recipes")
        }
    }
}

/// Widgets — resource card that teaches Home Screen + Lock Screen setup.
private struct WidgetSetupTile: View {
    var body: some View {
        BentoTappableTile(
            background: BentoTokens.whiteTileBackground,
            border: BentoTokens.whiteTileBorder
        ) {
            WidgetSetupGuideView()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                widgetStack
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)

                Text("Add widgets")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(BentoTokens.gray900)
                    .lineLimit(2)

                Text("Quick shortcuts for camera and voice logging.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BentoTokens.gray700)
                    .lineLimit(3)
                    .padding(.top, 6)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 146, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Add widgets. Quick shortcuts for camera and voice logging.")
            .accessibilityHint("Opens widget setup steps.")
        }
    }

    private var widgetStack: some View {
        Image(systemName: "rectangle.stack.badge.plus")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(BentoTokens.orange700)
            .frame(width: 42, height: 42, alignment: .leading)
    }
}

/// Badges — cream gradient 1×1 with trophy icon and current streak progress.
private struct BadgeTile: View {
    let days: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 2026-05-24: matches the LoggingTips/Widgets/Reminders layout —
        // icon → "Badges" → subtitle left-aligned at top. Streak number
        // floats in the bottom-right via overlay so it reads as the
        // headline metric without disturbing the standard tile rhythm.
        VStack(alignment: .leading, spacing: 0) {
            trophyIcon
                .padding(.bottom, 12)
                .accessibilityHidden(true)

            Text("Badges")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(BentoTokens.gray900)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(badgeTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BentoTokens.gray700)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(days)")
                    .font(.system(size: 52, weight: .heavy))
                    .foregroundStyle(BentoTokens.brandGradient)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(reduceMotion ? .identity : .numericText())

                Text("day streak")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BentoTokens.gray500)
                    .lineLimit(1)
            }
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BentoTokens.gray400)
                .accessibilityHidden(true)
        }
        .bentoTile(
            background: BentoTokens.whiteTileBackground,
            border: BentoTokens.whiteTileBorder
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(days == 1 ? "Badges, 1 day streak, \(badgeTitle)" : "Badges, \(days) day streak, \(badgeTitle)")
    }

    private var badgeTitle: String {
        StreakBadges.currentBadge(for: days)?.title ?? "First Spark awaits"
    }

    private var trophyIcon: some View {
        Image(systemName: "trophy")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(BentoTokens.orange700)
            .frame(width: 38, height: 38, alignment: .leading)
    }
}

/// Notifications — quick access tile that sits beside streaks.
private struct NotificationReminderTile: View {
    let summary: String
    @Binding var isEnabled: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                // 2026-05-22: tap-to-open the reminder settings screen.
                // Previously the card body had no gesture, so when reminders
                // were OFF there was no way to enter the detail view — the
                // only path was flipping the toggle, which had a permission
                // side effect. Toggle stays its own hit target below; this
                // Button covers the upper region (icon/title/summary) so
                // testers can reach the settings regardless of toggle state.
                Button(action: onOpenSettings) {
                    VStack(alignment: .leading, spacing: 0) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(BentoTokens.orange700)
                            .frame(width: 38, height: 38, alignment: .leading)
                            .padding(.bottom, 12)
                            .accessibilityHidden(true)

                        Text("Reminders")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(BentoTokens.gray900)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text(summary)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BentoTokens.gray700)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .padding(.top, 6)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Notifications and reminders, \(summary)")
                    .accessibilityHint("Opens reminder settings.")
                }
                .buttonStyle(BentoPressScaleStyle())

                HStack {
                    Spacer(minLength: 0)
                    Toggle("Meal reminders", isOn: $isEnabled)
                        .labelsHidden()
                        .tint(Color(red: 0.204, green: 0.780, blue: 0.349))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 146, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BentoTokens.gray400)
                .padding(.top, 1)
                .accessibilityHidden(true)
        }
        .bentoTile(
            background: BentoTokens.whiteTileBackground,
            border: BentoTokens.whiteTileBorder
        )
    }
}

/// Diet — light green tinted card with saturated icon. Tappable.
private struct DietTile: View {
    struct Data {
        let preferencesCount: Int
        let allergiesCount: Int
        let pace: String
    }

    let diet: Data

    var body: some View {
        BentoTappableTile(
            background: BentoTokens.whiteTileBackground,
            border: BentoTokens.whiteTileBorder
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
                statRow(
                    name: "Preferences",
                    value: diet.preferencesCount > 0 ? "\(diet.preferencesCount)" : "—",
                    isPlaceholder: diet.preferencesCount == 0
                )
                statRow(
                    name: "Allergies",
                    value: diet.allergiesCount > 0 ? "\(diet.allergiesCount)" : "—",
                    isPlaceholder: diet.allergiesCount == 0
                )
                statRow(name: "Pace", value: diet.pace, isPlaceholder: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Diet. \(diet.preferencesCount == 1 ? "1 preference" : "\(diet.preferencesCount) preferences"). \(diet.allergiesCount == 1 ? "1 allergy" : "\(diet.allergiesCount) allergies"). Pace \(diet.pace).")
            .accessibilityHint("Opens food preferences")
        }
    }

    private var iconCircle: some View {
        Image(systemName: "fork.knife")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(BentoTokens.orange700)
            .frame(width: 40, height: 40, alignment: .leading)
    }

    private func statRow(name: String, value: String, isPlaceholder: Bool) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(BentoTokens.gray700)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isPlaceholder ? BentoTokens.gray400 : BentoTokens.gray900)
        }
        .padding(.vertical, 3)
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

/// Color + gradient palette for the bento dashboard. After the 2026-05-24
/// dark-mode pass this is a thin façade over `AppColor`; keep new tile
/// chrome going through `AppColor` directly rather than adding more
/// aliases here.
private enum BentoTokens {
    // Brand orange
    static let orange500 = AppColor.brandOrange
    static let orange700 = AppColor.brandOrangeDeep
    static let orangeSoft = Color(red: 0.986, green: 0.742, blue: 0.471)

    // Macros
    static let protein = AppColor.macroProtein
    static let carbs   = AppColor.macroCarbs
    static let fat     = AppColor.macroFat

    // Body / Diet accents (saturated for icon circles)
    static let blue500  = AppColor.macroProtein
    static let blue700  = Color(red: 0.047, green: 0.388, blue: 0.690)
    static let green500 = AppColor.success
    static let green700 = Color(red: 0.102, green: 0.490, blue: 0.227)

    // Surfaces
    static let canvas   = AppColor.background
    static let profileCanvas = AppColor.surfaceWarm
    static let warningSurface = AppColor.surfaceWarning
    static let whiteTileBackground = AppColor.surface
    static let whiteTileBorder = AppColor.borderHairline
    static let savedMealChipBackground = AppColor.surfaceChip
    static let savedMealChipBorder = AppColor.borderSubtle

    // Grays — forwarded to AppColor so dark mode flips them too.
    static let gray100 = AppColor.gray100
    static let gray200 = AppColor.gray200
    static let gray400 = AppColor.gray400
    static let gray500 = AppColor.gray500
    static let gray700 = AppColor.gray700
    static let gray900 = AppColor.gray900

    // Gradients
    static let brandGradient = LinearGradient(
        colors: [AppColor.brandOrange, AppColor.brandOrangeDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.996, green: 0.610, blue: 0.278), Color(red: 0.957, green: 0.490, blue: 0.192)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warmIconGradient = LinearGradient(
        colors: [AppColor.brandOrange, AppColor.brandOrangeDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let coolIconGradient = LinearGradient(
        colors: [Color(red: 0.420, green: 0.736, blue: 1.0), blue700],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // 2026-05-22: bento restraint pass (Phase F, Item 6). All tile chrome
    // resolves to the warm-cream `surfaceWarm` token + the warm `borderSubtle`
    // hairline. Color stays reserved for KPIs, action affordances, the
    // streak ring tile, and the per-tile icon gradients. To restore the
    // pre-restraint family-specific gradients, see git history.
    static let warmCardTop = AppColor.surfaceWarm
    static let warmCardBottom = AppColor.surfaceWarm
    static let warmBorder = AppColor.borderSubtle

    static let savedCardTop = AppColor.surfaceWarm
    static let savedCardBottom = AppColor.surfaceWarm
    static let savedBorder = AppColor.borderSubtle

    static let coolCardTop = AppColor.surfaceWarm
    static let coolCardBottom = AppColor.surfaceWarm
    static let coolBorder = AppColor.borderSubtle

    static let greenCardTop = AppColor.surfaceWarm
    static let greenCardBottom = AppColor.surfaceWarm
    static let greenBorder = AppColor.borderSubtle

    /// Vertical orange→deep-orange for chart bars (matches the prototype
    /// trend chart bars which fade darker top-to-bottom).
    static let brandGradientLinear = LinearGradient(
        colors: [AppColor.brandOrange, AppColor.brandOrangeDeep],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Preview

#Preview {
    HomeProfileBentoScreen()
        .environmentObject(AppStore())
}
