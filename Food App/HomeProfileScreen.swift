//
//  HomeProfileScreen.swift
//  Food App
//
//  Extracted from ContentView.swift to bring ContentView under the
//  Phase 7A 1,000 LOC ceiling. Move-only — function/view bodies and
//  signatures unchanged.
//

import SwiftUI

// MARK: - Profile Screen

struct HomeProfileScreen: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var draft = OnboardingDraft()
    @State private var hasLoadedDraft = false
    @State private var isRequestingHealthPermission = false
    @State private var healthPermissionMessage: String?
    @State private var isAdmin = false
    @State private var adminGeminiEnabled = false
    @State private var isAdminFlagsLoading = false
    @State private var trackingAccuracy: TrackingAccuracyResponse?
    @State private var isLoadingAccuracy = false
    @State private var isSignOutConfirmationPresented = false

    // Auto-save
    private enum SaveStatus: Equatable {
        case idle, saving, saved, failed(String)
    }
    @State private var saveStatus: SaveStatus = .idle
    @State private var saveTask: Task<Void, Never>?
    @State private var savedResetTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                summaryHeaderSection
                profileHubSection
                appHubSection
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    saveStatusIndicator
                }
            }
            .onChange(of: draft) { _, _ in triggerDebouncedSave() }
            .task {
                await loadDraftIfNeeded()
                await loadAdminFlags()
                await loadTrackingAccuracy()
            }
        }
    }

    // MARK: - Sections

    private var profileHubSection: some View {
        Section {
            NavigationLink {
                PlanProfileDetailView {
                    planSection
                }
            } label: {
                ProfileHubRow(
                    title: "Plan & goals",
                    systemImage: "target"
                )
            }

            NavigationLink {
                BodyProfileDetailView {
                    bodySection
                }
            } label: {
                ProfileHubRow(
                    title: "Body details",
                    systemImage: "person.text.rectangle"
                )
            }

            NavigationLink {
                FoodPreferencesProfileDetailView {
                    dietSection
                    allergiesSection
                }
            } label: {
                ProfileHubRow(
                    title: "Food preferences",
                    systemImage: "fork.knife"
                )
            }

            NavigationLink {
                HealthInsightsProfileDetailView {
                    healthSection
                    trackingAccuracySection
                }
            } label: {
                ProfileHubRow(
                    title: "Health & insights",
                    systemImage: "heart.text.square"
                )
            }
        }
    }

    private var appHubSection: some View {
        Section("Account and app") {
            NavigationLink {
                AccountProfileDetailView {
                    accountSection
                    mealReminderSection
                }
            } label: {
                ProfileHubRow(
                    title: "Account & app",
                    systemImage: accountProviderIcon
                )
            }

            if isAdmin {
                NavigationLink {
                    AdminProfileDetailView {
                        adminSection
                    }
                } label: {
                    ProfileHubRow(
                        title: "Admin",
                        systemImage: "sparkles"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var summaryHeaderSection: some View {
        if draft.hasBaselineValues, let goal = draft.goal {
            let metrics = OnboardingCalculator.metrics(from: draft)
            let calorieTarget = draft.savedCalorieTarget ?? metrics.targetKcal
            let proteinTarget = draft.savedMacroTargets?.protein ?? metrics.proteinTarget
            let carbTarget = draft.savedMacroTargets?.carbs ?? metrics.carbTarget
            let fatTarget = draft.savedMacroTargets?.fat ?? metrics.fatTarget
            Section {
                LabeledContent("Daily target", value: "\(calorieTarget) kcal")
                LabeledContent("Protein", value: "\(proteinTarget) g")
                LabeledContent("Carbs", value: "\(carbTarget) g")
                LabeledContent("Fat", value: "\(fatTarget) g")
            } header: {
                Text("Daily targets")
            } footer: {
                Text("\(L10n.goalLabel(goal)) · \(draft.pace?.title ?? "Balanced") pace")
            }
        } else {
            Section {
                ContentUnavailableView(
                    "Complete your profile",
                    systemImage: "chart.bar",
                    description: Text("Set your goal and body details to see your daily target.")
                )
            }
        }
    }

    @ViewBuilder
    private var planSection: some View {
        Section("Your Plan") {
            Picker(selection: goalBinding) {
                ForEach(GoalOption.allCases) { option in
                    Text(L10n.goalLabel(option)).tag(Optional(option))
                }
                Text("Not set").tag(Optional<GoalOption>.none)
            } label: {
                Label("Goal", systemImage: "target")
            }
            .pickerStyle(.menu)

            Picker(selection: activityBinding) {
                ForEach(ActivityChoice.allCases) { option in
                    Text(option.title).tag(Optional(option))
                }
                Text("Not set").tag(Optional<ActivityChoice>.none)
            } label: {
                Label("Activity", systemImage: "figure.walk")
            }
            .pickerStyle(.menu)

            Picker(selection: paceBinding) {
                ForEach(PaceChoice.allCases) { option in
                    Text(option.title).tag(Optional(option))
                }
                Text("Not set").tag(Optional<PaceChoice>.none)
            } label: {
                Label("Pace", systemImage: "speedometer")
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var bodySection: some View {
        Section("Body") {
            Picker("Units", selection: unitsBinding) {
                ForEach(UnitsOption.allCases) { opt in
                    Text(L10n.unitsLabel(opt)).tag(opt)
                }
            }
            .pickerStyle(.segmented)

            Picker(selection: sexBinding) {
                ForEach(SexOption.allCases) { opt in
                    Text(opt.title).tag(Optional(opt))
                }
                Text("Not set").tag(Optional<SexOption>.none)
            } label: {
                Label("Sex", systemImage: "person.fill")
            }
            .pickerStyle(.menu)

            Stepper(value: ageIntBinding, in: OnboardingBaselineRange.age) {
                LabeledContent {
                    Text("\(Int(draft.ageValue))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } label: {
                    Label("Age", systemImage: "calendar")
                }
            }

            NavigationLink {
                HeightPickerView(draft: $draft)
            } label: {
                LabeledContent {
                    Text(heightLabel).foregroundStyle(.secondary)
                } label: {
                    Label("Height", systemImage: "ruler")
                }
            }

            NavigationLink {
                WeightPickerView(draft: $draft)
            } label: {
                LabeledContent {
                    Text(weightLabel).foregroundStyle(.secondary)
                } label: {
                    Label("Weight", systemImage: "scalemass.fill")
                }
            }
        }
    }

    @ViewBuilder
    private var dietSection: some View {
        let activePrefs = draft.preferences.filter { $0 != .noPreference }
        Section {
            ForEach(PreferenceChoice.allCases.filter { $0 != .noPreference }) { pref in
                Toggle(isOn: preferenceToggleBinding(pref)) {
                    Label(pref.title, systemImage: preferenceSymbol(for: pref))
                }
            }
        } header: {
            Text("Dietary Preferences")
        } footer: {
            if activePrefs.isEmpty {
                Text("Select any that apply.")
            }
        }
    }

    @ViewBuilder
    private var allergiesSection: some View {
        Section {
            ForEach(AllergyChoice.allCases) { allergy in
                Toggle(isOn: allergyToggleBinding(allergy)) {
                    Label(allergy.title, systemImage: "exclamationmark.shield")
                }
            }
        } header: {
            Text("Allergies")
        } footer: {
            if draft.allergies.isEmpty {
                Text("We'll flag foods that conflict with these in your daily log.")
            }
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        Section {
            Toggle(isOn: healthToggleBinding) {
                Label("Apple Health", systemImage: "heart.fill")
            }

            if isRequestingHealthPermission {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Requesting access…").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Health & Activity")
        } footer: {
            if let healthPermissionMessage, !isRequestingHealthPermission {
                Text(healthPermissionMessage)
                    .foregroundStyle(draft.connectHealth ? .green : .secondary)
            }
        }
    }

    // MARK: - Tracking Accuracy

    @ViewBuilder
    private var trackingAccuracySection: some View {
        Section {
            if isLoadingAccuracy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading…").foregroundStyle(.secondary)
                }
            } else if let accuracy = trackingAccuracy, accuracy.entryCount > 0 {
                LabeledContent("All-time accuracy") {
                    Text("\(Int(accuracy.averageConfidence * 100))%")
                        .foregroundStyle(tierColor(accuracy.tier))
                        .monospacedDigit()
                }

                ProgressView(value: accuracy.averageConfidence)
                    .tint(tierColor(accuracy.tier))

                LabeledContent("Entries logged", value: "\(accuracy.entryCount)")

                Text(tierMessage(accuracy.tier))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView(
                    "No data yet",
                    systemImage: "chart.bar",
                    description: Text("Log some food to see your tracking accuracy.")
                )
            }
        } header: {
            Text("Tracking accuracy")
        }

        if let accuracy = trackingAccuracy, !accuracy.lowConfidenceEntries.isEmpty {
            Section {
                ForEach(accuracy.lowConfidenceEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\"\(entry.rawText)\"")
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(entry.confidence * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Label(entry.suggestion, systemImage: "lightbulb")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } header: {
                Text("Tips to improve")
            }
        }
    }

    private func tierColor(_ tier: String) -> Color {
        switch tier {
        case "excellent": return .green
        case "good": return .blue
        case "fair": return .orange
        case "needs_work": return .red
        default: return .secondary
        }
    }

    private func tierMessage(_ tier: String) -> String {
        switch tier {
        case "excellent": return "Your entries are highly specific — great job!"
        case "good": return "Most entries are solid. A few could be more specific."
        case "fair": return "Some entries could use more detail for better accuracy."
        case "needs_work": return "Adding quantities and specifics will improve accuracy."
        default: return ""
        }
    }

    private func loadTrackingAccuracy() async {
        isLoadingAccuracy = true
        defer { isLoadingAccuracy = false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: Date())
        let tz = TimeZone.current.identifier
        do {
            trackingAccuracy = try await appStore.apiClient.getTrackingAccuracy(date: today, timezone: tz)
        } catch {
            // Silently fail — accuracy card is non-critical
            _ = appStore.handleAuthFailureIfNeeded(error)
        }
    }

    private var accountSection: some View {
        Section("Account") {
            LabeledContent {
                Text(accountProviderName).foregroundStyle(.secondary)
            } label: {
                Label("Signed in with", systemImage: accountProviderIcon)
            }
            Button(role: .destructive) {
                isSignOutConfirmationPresented = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .alert("Sign out?", isPresented: $isSignOutConfirmationPresented) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    appStore.signOut()
                }
            } message: {
                Text("This clears this device's session and returns you to sign in. Your saved food logs stay in your account.")
            }
        }
    }

    private var mealReminderSection: some View {
        Section {
            reminderTimePicker(
                title: "Breakfast",
                systemImage: "sunrise.fill",
                keyPath: \.breakfast
            )
            reminderTimePicker(
                title: "Lunch",
                systemImage: "sun.max.fill",
                keyPath: \.lunch
            )
            reminderTimePicker(
                title: "Dinner",
                systemImage: "moon.fill",
                keyPath: \.dinner
            )
        } header: {
            Text("Meal reminders")
        } footer: {
            Text("Used for local food reminders when notifications are enabled.")
        }
    }

    private var adminSection: some View {
        Section("Admin") {
            Toggle(isOn: $adminGeminiEnabled) {
                Label("Gemini AI", systemImage: "sparkles")
            }
            .onChange(of: adminGeminiEnabled) { _, _ in triggerAdminAutoSave() }
        }
    }

    // MARK: - Toolbar save indicator

    @ViewBuilder
    private var saveStatusIndicator: some View {
        switch saveStatus {
        case .idle:
            EmptyView()
        case .saving:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.7)
                Text("Saving…").font(.caption).foregroundStyle(.secondary)
            }
        case .saved:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                Text("Saved").font(.caption).foregroundStyle(.green)
            }
            .transition(.opacity)
        case .failed:
            Button {
                triggerDebouncedSave(immediate: true)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                    Text("Retry").font(.caption.weight(.medium)).foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Display helpers

    private var heightLabel: String {
        if (draft.units ?? .imperial) == .metric {
            return "\(Int(draft.heightMetricValue)) cm"
        }
        let h = draft.imperialHeightFeetInches
        return "\(h.feet)' \(h.inches)\""
    }

    private var weightLabel: String {
        let unitLabel = (draft.units ?? .imperial) == .metric ? "kg" : "lbs"
        return "\(Int(draft.weightValue)) \(unitLabel)"
    }

    private var accountProviderIcon: String {
        draft.accountProvider == .apple ? "apple.logo" : "globe"
    }

    private var accountProviderName: String {
        switch draft.accountProvider {
        case .apple: return "Apple"
        case .google: return "Google"
        case .none: return "Not signed in"
        }
    }

    private func preferenceSymbol(for preference: PreferenceChoice) -> String {
        switch preference {
        case .highProtein:   return "bolt.fill"
        case .vegetarian:    return "leaf"
        case .vegan:         return "leaf.fill"
        case .pescatarian:   return "fish"
        case .lowCarb:       return "minus.circle.fill"
        case .keto:          return "bolt.circle.fill"
        case .glutenFree:    return "checkmark.circle.fill"
        case .dairyFree:     return "drop.fill"
        case .halal:         return "moon.fill"
        case .lowSodium:     return "heart.text.square.fill"
        case .mediterranean: return "sun.max.fill"
        case .noPreference:  return "fork.knife"
        }
    }

    // MARK: - Bindings

    private var goalBinding: Binding<GoalOption?> {
        Binding(get: { draft.goal }, set: { draft.goal = $0 })
    }

    private var activityBinding: Binding<ActivityChoice?> {
        Binding(get: { draft.activity }, set: { draft.activity = $0 })
    }

    private var paceBinding: Binding<PaceChoice?> {
        Binding(get: { draft.pace }, set: { draft.pace = $0 })
    }

    private var sexBinding: Binding<SexOption?> {
        Binding(
            get: { draft.sex },
            set: {
                draft.sex = $0
                draft.baselineTouchedSex = true
            }
        )
    }

    private var unitsBinding: Binding<UnitsOption> {
        Binding(
            get: { draft.units ?? .imperial },
            set: { draft.setUnitsPreservingBaseline($0) }
        )
    }

    private var ageIntBinding: Binding<Int> {
        Binding(
            get: { Int(draft.ageValue) },
            set: {
                draft.ageValue = Double($0)
                draft.baselineTouchedAge = true
            }
        )
    }

    private func togglePreference(_ preference: PreferenceChoice) {
        if draft.preferences.contains(preference) {
            draft.preferences.remove(preference)
            if draft.preferences.filter({ $0 != .noPreference }).isEmpty {
                draft.preferences = [.noPreference]
            }
        } else {
            draft.preferences.insert(preference)
            draft.preferences.remove(.noPreference)
        }
    }

    private func toggleAllergy(_ allergy: AllergyChoice) {
        if draft.allergies.contains(allergy) {
            draft.allergies.remove(allergy)
        } else {
            draft.allergies.insert(allergy)
        }
    }

    private func preferenceToggleBinding(_ preference: PreferenceChoice) -> Binding<Bool> {
        Binding(
            get: { draft.preferences.contains(preference) },
            set: { _ in togglePreference(preference) }
        )
    }

    private func allergyToggleBinding(_ allergy: AllergyChoice) -> Binding<Bool> {
        Binding(
            get: { draft.allergies.contains(allergy) },
            set: { _ in toggleAllergy(allergy) }
        )
    }

    private var healthToggleBinding: Binding<Bool> {
        Binding(
            get: { draft.connectHealth },
            set: { wantsEnabled in
                if wantsEnabled { requestHealthAccess() } else { disconnectHealthAccess() }
            }
        )
    }

    private func reminderTimePicker(
        title: String,
        systemImage: String,
        keyPath: WritableKeyPath<MealReminderSettings, MealReminderTime>
    ) -> some View {
        DatePicker(
            selection: Binding(
                get: { date(for: appStore.mealReminderSettings[keyPath: keyPath]) },
                set: { newDate in
                    var settings = appStore.mealReminderSettings
                    settings[keyPath: keyPath] = reminderTime(from: newDate)
                    appStore.setMealReminderSettings(settings)
                }
            ),
            displayedComponents: .hourAndMinute
        ) {
            Label(title, systemImage: systemImage)
        }
    }

    private func date(for time: MealReminderTime) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = time.hour
        components.minute = time.minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func reminderTime(from date: Date) -> MealReminderTime {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return MealReminderTime(hour: components.hour ?? 12, minute: components.minute ?? 0)
    }

    private var dietPreferencePayload: String {
        if draft.preferences.isEmpty || draft.preferences.contains(.noPreference) {
            return "no_preference"
        }
        return draft.preferences.map(\.rawValue).sorted().joined(separator: ",")
    }

    // MARK: - Data loading

    private func loadDraftIfNeeded() async {
        guard !hasLoadedDraft else { return }
        hasLoadedDraft = true
        appStore.refreshHealthAuthorizationState()
        if let persisted = OnboardingPersistence.load() {
            draft = persisted.draft
        }
        if let profile = try? await appStore.apiClient.getOnboardingProfile() {
            draft = OnboardingDraft(profile: profile, accountProvider: appStore.authSessionStore.session?.provider)
        }
        draft.migrateLegacyBaselineTouchStateIfNeeded()
        draft.connectHealth = appStore.isHealthSyncEnabled
    }

    private func requestHealthAccess() {
        guard !isRequestingHealthPermission else { return }
        isRequestingHealthPermission = true
        healthPermissionMessage = nil
        Task {
            do {
                let granted = try await appStore.requestAppleHealthAccess()
                await MainActor.run {
                    draft.connectHealth = granted
                    healthPermissionMessage = granted ? "Apple Health connected." : "Permission not granted."
                    isRequestingHealthPermission = false
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    draft.connectHealth = false
                    healthPermissionMessage = msg
                    isRequestingHealthPermission = false
                }
            }
        }
    }

    private func disconnectHealthAccess() {
        appStore.disconnectAppleHealth()
        draft.connectHealth = false
        healthPermissionMessage = "Apple Health disconnected."
    }

    // MARK: - Auto-save

    private func triggerDebouncedSave(immediate: Bool = false) {
        saveTask?.cancel()
        saveTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
            }
            OnboardingPersistence.save(draft: draft, route: .ready)
            guard draft.hasBaselineValues, let goal = draft.goal, let activity = draft.activity else { return }
            if draft.preferences.isEmpty { draft.preferences = [.noPreference] }
            let request = OnboardingRequest(
                goal: goal,
                dietPreference: dietPreferencePayload,
                allergies: draft.allergies.map(\.rawValue).sorted(),
                units: draft.units ?? .imperial,
                activityLevel: activity.apiValue,
                timezone: TimeZone.current.identifier,
                age: Int(draft.ageValue.rounded()),
                sex: (draft.sex ?? .other).rawValue,
                heightCm: draft.heightInCm,
                weightKg: draft.weightInKg,
                pace: (draft.pace ?? .balanced).rawValue,
                activityDetail: draft.activity?.rawValue
            )
            saveStatus = .saving
            do {
                let response = try await appStore.apiClient.submitOnboarding(request)
                draft.savedCalorieTarget = response.calorieTarget
                draft.savedMacroTargets = response.macroTargets
                OnboardingPersistence.save(draft: draft, route: .ready)
                appStore.setError(nil)
                saveStatus = .saved
                savedResetTask?.cancel()
                savedResetTask = Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    saveStatus = .idle
                }
            } catch is CancellationError {
                // ignore
            } catch {
                if appStore.handleAuthFailureIfNeeded(error) {
                    saveStatus = .failed(L10n.authSessionExpired)
                } else {
                    let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    saveStatus = .failed(msg)
                }
            }
        }
    }

    private func triggerAdminAutoSave() {
        guard isAdmin else { return }
        Task {
            do {
                let request = AdminFeatureFlagsUpdateRequest(geminiEnabled: adminGeminiEnabled)
                let response = try await appStore.apiClient.updateAdminFeatureFlags(request)
                if let flags = response.flags {
                    adminGeminiEnabled = flags.geminiEnabled
                }
            } catch {
                _ = appStore.handleAuthFailureIfNeeded(error)
            }
        }
    }

    private func loadAdminFlags() async {
        guard !isAdminFlagsLoading else { return }
        isAdminFlagsLoading = true
        defer { isAdminFlagsLoading = false }
        do {
            let response = try await appStore.apiClient.getAdminFeatureFlags()
            isAdmin = response.isAdmin
            if let flags = response.flags, response.isAdmin {
                adminGeminiEnabled = flags.geminiEnabled
            }
        } catch {
            _ = appStore.handleAuthFailureIfNeeded(error)
        }
    }
}

private struct ProfileHubRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
    }
}

private struct PlanProfileDetailView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form { content }
            .navigationTitle("Plan & Goals")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BodyProfileDetailView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form { content }
            .navigationTitle("Body Details")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FoodPreferencesProfileDetailView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form { content }
            .navigationTitle("Food Preferences")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HealthInsightsProfileDetailView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form { content }
            .navigationTitle("Health & Insights")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AccountProfileDetailView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form { content }
            .navigationTitle("Account & App")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AdminProfileDetailView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form { content }
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Height / Weight Wheel Pickers

private struct HeightPickerView: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        Group {
            if (draft.units ?? .imperial) == .imperial {
                imperialBody
            } else {
                metricBody
            }
        }
        .navigationTitle("Height")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var imperialBody: some View {
        let fi = draft.imperialHeightFeetInches
        let feetBinding = Binding<Int>(
            get: { fi.feet },
            set: { newFeet in
                draft.imperialHeightFeetInches = (newFeet, draft.imperialHeightFeetInches.inches)
                draft.baselineTouchedHeight = true
            }
        )
        let inchesBinding = Binding<Int>(
            get: { fi.inches },
            set: { newInches in
                draft.imperialHeightFeetInches = (draft.imperialHeightFeetInches.feet, newInches)
                draft.baselineTouchedHeight = true
            }
        )
        return HStack(spacing: 0) {
            Picker("Feet", selection: feetBinding) {
                ForEach(OnboardingBaselineRange.minImperialFeet ... OnboardingBaselineRange.maxImperialFeet, id: \.self) { f in
                    Text("\(f) ft").tag(f)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Picker("Inches", selection: inchesBinding) {
                ForEach(0 ... 11, id: \.self) { i in
                    Text("\(i) in").tag(i)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
    }

    private var metricBody: some View {
        let cmBinding = Binding<Int>(
            get: { Int(draft.heightMetricValue) },
            set: { newValue in
                draft.heightMetricValue = Double(newValue)
                draft.baselineTouchedHeight = true
            }
        )
        return Picker("Height", selection: cmBinding) {
            ForEach(OnboardingBaselineRange.heightCm, id: \.self) { cm in
                Text("\(cm) cm").tag(cm)
            }
        }
        .pickerStyle(.wheel)
        .padding(.horizontal)
    }
}

private struct WeightPickerView: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        let isMetric = (draft.units ?? .imperial) == .metric
        let range: ClosedRange<Int>
        let unit: String
        if isMetric {
            range = Int(OnboardingBaselineRange.weightKg.lowerBound) ... Int(OnboardingBaselineRange.weightKg.upperBound)
            unit = "kg"
        } else {
            range = Int(OnboardingBaselineRange.weightLb.lowerBound) ... Int(OnboardingBaselineRange.weightLb.upperBound)
            unit = "lbs"
        }

        let weightBinding = Binding<Int>(
            get: { Int(draft.weightValue) },
            set: { newValue in
                draft.weightValue = Double(newValue)
                draft.baselineTouchedWeight = true
            }
        )

        return Picker("Weight", selection: weightBinding) {
            ForEach(range, id: \.self) { w in
                Text("\(w) \(unit)").tag(w)
            }
        }
        .pickerStyle(.wheel)
        .padding(.horizontal)
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
    }
}
