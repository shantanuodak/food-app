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
    @State private var isAdminNotificationTriggering = false
    @State private var adminDebugStatus: String?
    @State private var adminPreviewBadge: EarnedBadge?
    @State private var isSignOutConfirmationPresented = false
    @State private var bodyMetricEditorSheet: BodyMetricEditorSheet?

    // Auto-save
    private enum SaveStatus: Equatable {
        case idle, saving, saved, failed(String)
    }
    @State private var saveStatus: SaveStatus = .idle
    @State private var saveTask: Task<Void, Never>?
    @State private var savedResetTask: Task<Void, Never>?

    var body: some View {
        // No outer NavigationStack — this screen is pushed onto the bento
        // dashboard's NavigationStack, so wrapping here would nest stacks
        // and break back behavior. The internal NavigationLinks (Body /
        // Diet / Plan etc.) push onto the parent stack the same way.
        Form {
            healthSection
            bodySection
            appHubSection
        }
        .navigationTitle("Account & App")
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
        }
        .fullScreenCover(item: $adminPreviewBadge) { badge in
            StreakAchievementPopup(badge: badge) {
                adminPreviewBadge = nil
            }
        }
    }

    // MARK: - Sections

    private var profileHubSection: some View {
        Section {
            NavigationLink {
                ProgressSectionView()
                    .navigationTitle("Progress")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                ProfileHubRow(
                    title: "Progress & insights",
                    systemImage: "chart.bar.fill"
                )
            }

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
                    foodPreferencesIntroSection
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
        Section {
            NavigationLink {
                AccountProfileDetailView(title: "Account") {
                    accountSection
                }
            } label: {
                ProfileHubRow(
                    title: "Account",
                    systemImage: accountProviderIcon
                )
            }

            NavigationLink {
                FeedbackView()
            } label: {
                ProfileHubRow(
                    title: "Send feedback",
                    systemImage: "envelope"
                )
            }

            NavigationLink {
                UpcomingFeaturesAndFixesView()
            } label: {
                ProfileHubRow(
                    title: "Upcoming features and fixes",
                    systemImage: "sparkle.magnifyingglass"
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
        Section {
            VStack(spacing: 0) {
                Picker("Units", selection: unitsBinding) {
                    ForEach(UnitsOption.allCases) { opt in
                        Text(L10n.unitsLabel(opt)).tag(opt)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 14)

                Divider()

                bodySexRow

                Divider()
                    .padding(.leading, 58)

                bodyAgeRow

                Divider()
                    .padding(.leading, 58)

                bodyEditableRow(
                    title: "Height",
                    value: heightLabel,
                    systemImage: "ruler",
                    iconTint: .blue,
                    editor: .height
                )

                Divider()
                    .padding(.leading, 58)

                bodyEditableRow(
                    title: "Weight",
                    value: weightLabel,
                    systemImage: "scalemass.fill",
                    iconTint: .blue,
                    editor: .weight
                )
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.035), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 10, y: 4)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)
            .sheet(item: $bodyMetricEditorSheet) { editor in
                bodyMetricEditorSheetView(editor)
            }
        } header: {
            Text("Body")
        }
    }

    private var bodySexRow: some View {
        HStack(spacing: 14) {
            bodyRowIcon(systemImage: "person.fill", tint: .blue)

            Text("Sex")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            Picker("Sex", selection: sexBinding) {
                ForEach(SexOption.allCases) { opt in
                    Text(opt.title).tag(Optional(opt))
                }
                Text("Not set").tag(Optional<SexOption>.none)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.blue)
        }
        .frame(minHeight: 58)
    }

    private var bodyAgeRow: some View {
        bodyEditableRow(
            title: "Age",
            value: "\(Int(draft.ageValue))",
            systemImage: "calendar",
            iconTint: .primary,
            editor: .age
        )
    }

    private func bodyEditableRow(
        title: String,
        value: String,
        systemImage: String,
        iconTint: Color,
        editor: BodyMetricEditorSheet
    ) -> some View {
        Button {
            bodyMetricEditorSheet = editor
        } label: {
            HStack(spacing: 14) {
                bodyRowIcon(systemImage: systemImage, tint: iconTint)

                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Text(value)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func bodyMetricEditorSheetView(_ editor: BodyMetricEditorSheet) -> some View {
        NavigationStack {
            Group {
                switch editor {
                case .age:
                    AgePickerView(draft: $draft)
                case .height:
                    HeightPickerView(draft: $draft)
                case .weight:
                    WeightPickerView(draft: $draft)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        bodyMetricEditorSheet = nil
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func bodyRowIcon(systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
    }

    /// Single explainer at the top of Food preferences. Two short lines
    /// covering both dietary preferences and allergies — the user sees
    /// this once when they open the screen, no per-row info icons.
    @ViewBuilder
    private var foodPreferencesIntroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("We'll use these to flag meals that don't match your diet or include allergens.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text("Set what fits today — you can change this any time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    @ViewBuilder
    private var dietSection: some View {
        Section {
            ForEach(PreferenceChoice.allCases.filter { $0 != .noPreference }) { pref in
                Toggle(isOn: preferenceToggleBinding(pref)) {
                    Label(pref.title, systemImage: preferenceSymbol(for: pref))
                }
            }
        } header: {
            Text("Dietary preferences")
        }
    }

    @ViewBuilder
    private var allergiesSection: some View {
        Section {
            ForEach(AllergyChoice.allCases) { allergy in
                Toggle(isOn: allergyToggleBinding(allergy)) {
                    Label(allergy.title, systemImage: allergy.systemImage)
                }
            }
        } header: {
            Text("Allergies")
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

    private var accountSection: some View {
        Section("Account") {
            LabeledContent {
                Text(accountProviderName).foregroundStyle(.secondary)
            } label: {
                Label("Signed in with", systemImage: accountProviderIcon)
            }
            LabeledContent {
                Text(accountDisplayName)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("Name", systemImage: "person.crop.circle")
            }
            LabeledContent {
                Text(accountEmail)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            } label: {
                Label("Email", systemImage: "envelope")
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

    @ViewBuilder
    private var adminSection: some View {
        Section("Feature flags") {
            Toggle(isOn: $adminGeminiEnabled) {
                Label("Gemini AI", systemImage: "sparkles")
            }
            .onChange(of: adminGeminiEnabled) { _, _ in triggerAdminAutoSave() }
        }

        Section {
            ForEach(AdminTestNotificationKind.allCases) { kind in
                Button {
                    triggerAdminNotification(kind)
                } label: {
                    Label("Trigger \(kind.title)", systemImage: kind.systemImage)
                }
                .disabled(isAdminNotificationTriggering)
            }

            if isAdminNotificationTriggering {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Scheduling test notification…")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Notification debug")
        } footer: {
            Text("Sends an immediate local test notification on this device. If iOS notification permission is blocked, open Settings and allow notifications for Food App.")
        }

        Section {
            Menu {
                ForEach(BadgeCatalog.definitions) { definition in
                    Button {
                        adminPreviewBadge = EarnedBadge(definition: definition)
                    } label: {
                        Label(definition.title, systemImage: definition.systemImage)
                    }
                }
            } label: {
                Label("Preview badge popup", systemImage: "sparkles.rectangle.stack.fill")
            }

            Button(role: .destructive) {
                StreakBadgeCelebrationState.reset()
                BadgeCelebrationState.reset()
                adminDebugStatus = "Badge celebration history reset."
            } label: {
                Label("Reset badge celebration history", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Reward debug")
        } footer: {
            Text("Admin-only previews for badge reward animations. These controls do not change real badge progress.")
        }

        if let adminDebugStatus {
            Section {
                Text(adminDebugStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
        currentAccountProvider == .apple ? "apple.logo" : "globe"
    }

    private var accountProviderName: String {
        switch currentAccountProvider {
        case .apple: return "Apple"
        case .google: return "Google"
        case .none: return "Not signed in"
        }
    }

    private var currentAccountProvider: AccountProvider? {
        appStore.authSessionStore.session?.provider ?? draft.accountProvider
    }

    private var accountDisplayName: String {
        appStore.authSessionStore.session?.displayFullName ?? "Name unavailable"
    }

    private var accountEmail: String {
        appStore.authSessionStore.session?.email ?? "Email unavailable"
    }

    private var mealReminderSummaryText: String {
        let settings = appStore.mealReminderSettings
        guard settings.remindersEnabled else { return "Off" }

        var enabledMeals: [String] = []
        if settings.breakfastEnabled {
            enabledMeals.append("Breakfast \(timeLabel(for: settings.breakfastStart))-\(timeLabel(for: settings.breakfast))")
        }
        if settings.lunchEnabled {
            enabledMeals.append("Lunch \(timeLabel(for: settings.lunchStart))-\(timeLabel(for: settings.lunch))")
        }
        if settings.dinnerEnabled {
            enabledMeals.append("Dinner \(timeLabel(for: settings.dinnerStart))-\(timeLabel(for: settings.dinner))")
        }
        return enabledMeals.isEmpty ? "No meal times selected" : enabledMeals.joined(separator: " · ")
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

    private func timeLabel(for time: MealReminderTime) -> String {
        date(for: time).formatted(date: .omitted, time: .shortened)
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

    private func triggerAdminNotification(_ kind: AdminTestNotificationKind) {
        guard isAdmin, !isAdminNotificationTriggering else { return }
        isAdminNotificationTriggering = true
        adminDebugStatus = "Scheduling \(kind.title)…"

        Task {
            let result = await AdminNotificationDebugService.trigger(kind)
            await appStore.refreshNotificationAuthState()

            await MainActor.run {
                isAdminNotificationTriggering = false
                switch result {
                case .scheduled:
                    adminDebugStatus = "\(kind.title) test notification scheduled. It should appear in about 1 second."
                case .denied:
                    adminDebugStatus = "Notifications are blocked for this device. Allow Food App notifications in iOS Settings, then try again."
                    openAppSettings()
                case .failed(let message):
                    adminDebugStatus = "Could not schedule \(kind.title): \(message)"
                }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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

private struct UpcomingFeaturesAndFixesView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var selectedBucket: Bucket = .fixes
    @State private var roadmap: RoadmapResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private enum Bucket: String, CaseIterable, Identifiable {
        case fixes
        case features

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fixes:
                return "Upcoming fixes"
            case .features:
                return "Upcoming features"
            }
        }
    }

    private var selectedItems: [RoadmapItem] {
        switch selectedBucket {
        case .fixes:
            return roadmap?.fixes ?? []
        case .features:
            return roadmap?.features ?? []
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Roadmap bucket", selection: $selectedBucket) {
                    ForEach(Bucket.allCases) { bucket in
                        Text(bucket.title).tag(bucket)
                    }
                }
                .pickerStyle(.segmented)
            }

            if isLoading && roadmap == nil {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading roadmap…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let errorMessage {
                Section {
                    ContentUnavailableView(
                        "Roadmap unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                    Button("Retry") {
                        Task { await loadRoadmap() }
                    }
                }
            } else if selectedItems.isEmpty {
                Section {
                    ContentUnavailableView(
                        selectedBucket == .fixes ? "No upcoming fixes yet" : "No upcoming features yet",
                        systemImage: selectedBucket == .fixes ? "wrench.and.screwdriver" : "sparkles",
                        description: Text("Check back after the next roadmap update.")
                    )
                }
            } else {
                Section {
                    ForEach(selectedItems) { item in
                        roadmapRow(item)
                    }
                } footer: {
                    Text("Roadmap items are curated from user feedback and internal planning. Dates and release numbers may change before shipping.")
                }
            }
        }
        .navigationTitle("Upcoming features and fixes")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadRoadmap()
        }
        .task {
            await loadRoadmap()
        }
    }

    private func roadmapRow(_ item: RoadmapItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                    if !item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(item.description)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                statusChip(item.status)
            }

            HStack(spacing: 8) {
                metadataChip(icon: "shippingbox", text: item.releaseVersion?.isEmpty == false ? item.releaseVersion! : "Release TBD")
                metadataChip(icon: "calendar", text: item.targetDate ?? item.targetDateLabel)
            }
        }
        .padding(.vertical, 6)
    }

    private func statusChip(_ status: String) -> some View {
        Text(statusLabel(status))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(statusColor(status).opacity(0.12), in: Capsule())
    }

    private func metadataChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "in_progress":
            return "In progress"
        case "done":
            return "Done"
        default:
            return "Not started"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "in_progress":
            return .blue
        case "done":
            return .green
        default:
            return .secondary
        }
    }

    @MainActor
    private func loadRoadmap() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            roadmap = try await appStore.apiClient.getRoadmap()
        } catch {
            _ = appStore.handleAuthFailureIfNeeded(error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
