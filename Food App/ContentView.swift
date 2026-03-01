//
//  ContentView.swift
//  Food App
//
//  Created by Shantanu Odak on 2/15/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appStore: AppStore
    @StateObject private var flow = AppFlowCoordinator()

    var body: some View {
        Group {
            switch flow.route {            case .onboarding:
                OnboardingView(flow: flow)
            case .home:
                HomeTabShellView()
            }
        }
        .onAppear {
            flow.sync(isOnboardingComplete: appStore.isOnboardingComplete)
        }
        .onChange(of: appStore.isOnboardingComplete) { _, isComplete in
            flow.sync(isOnboardingComplete: isComplete)
        }
    }
}

private enum HomeRootTab: String, CaseIterable, Identifiable {
    case log
    case progress
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .log: return "Log"
        case .progress: return "Progress"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .log: return "fork.knife.circle"
        case .progress: return "chart.bar.fill"
        case .profile: return "person.crop.circle"
        }
    }
}

private struct HomeTabShellView: View {
    @State private var selectedTab: HomeRootTab = .log

    var body: some View {
        TabView(selection: $selectedTab) {
            MainLoggingShellView()
                .tabItem {
                    Label(HomeRootTab.log.title, systemImage: HomeRootTab.log.icon)
                }
                .tag(HomeRootTab.log)

            HomeProgressScreen()
                .tabItem {
                    Label(HomeRootTab.progress.title, systemImage: HomeRootTab.progress.icon)
                }
                .tag(HomeRootTab.progress)

            HomeProfileScreen()
                .tabItem {
                    Label(HomeRootTab.profile.title, systemImage: HomeRootTab.profile.icon)
                }
                .tag(HomeRootTab.profile)
        }
    }
}

private struct HomeProfileScreen: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var draft = OnboardingDraft()
    @State private var hasLoadedDraft = false
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var saveError: String?
    @State private var isRequestingHealthPermission = false
    @State private var healthPermissionMessage: String?
    @State private var isRestartOnboardingAlertPresented = false
    @State private var isAdmin = false
    @State private var adminGeminiEnabled = false
    @State private var adminFatsecretEnabled = false
    @State private var isAdminFlagsLoading = false
    @State private var isAdminFlagsSaving = false
    @State private var adminFlagsMessage: String?
    @State private var adminFlagsError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(goalHeadline)
                            .font(.title3.weight(.semibold))
                        Text(goalSubheadline)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Body Profile") {
                    Picker(selection: goalBinding) {
                        Text("Select goal").tag(GoalOption?.none)
                        Text("Lose").tag(GoalOption?.some(.lose))
                        Text("Maintain").tag(GoalOption?.some(.maintain))
                        Text("Gain").tag(GoalOption?.some(.gain))
                    } label: {
                        profileFieldLabel("Goal", icon: "target", color: .orange)
                    }

                    Picker(selection: sexBinding) {
                        Text("Select sex").tag(SexOption?.none)
                        ForEach(SexOption.allCases) { option in
                            Text(option.title).tag(SexOption?.some(option))
                        }
                    } label: {
                        profileFieldLabel("Sex", icon: "person.2.fill", color: .purple)
                    }

                    Picker(selection: unitsBinding) {
                        ForEach(UnitsOption.allCases) { option in
                            Text(option == .metric ? "Metric" : "Imperial").tag(UnitsOption?.some(option))
                        }
                    } label: {
                        profileFieldLabel("Units", icon: "ruler.fill", color: .blue)
                    }

                    BaselineAgeCard(
                        age: profileAgeBinding,
                        isTouched: $draft.baselineTouchedAge
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    Group {
                        if draft.units == .metric {
                            BaselineMetricHeightCard(
                                heightCm: profileHeightCmBinding,
                                isTouched: $draft.baselineTouchedHeight
                            )
                        } else {
                            BaselineImperialHeightCard(
                                feet: profileFeetBinding,
                                inches: profileInchesBinding,
                                isTouched: $draft.baselineTouchedHeight
                            )
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    BaselineWeightCard(
                        weight: profileWeightBinding,
                        units: draft.units ?? .imperial,
                        isTouched: $draft.baselineTouchedWeight
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Plan") {
                    Picker(selection: activityBinding) {
                        Text("Select activity").tag(ActivityChoice?.none)
                        ForEach(ActivityChoice.allCases) { option in
                            Text(option.title).tag(ActivityChoice?.some(option))
                        }
                    } label: {
                        profileFieldLabel("Activity", icon: "figure.walk", color: .green)
                    }

                    Picker(selection: paceBinding) {
                        Text("Select pace").tag(PaceChoice?.none)
                        ForEach(PaceChoice.allCases) { option in
                            Text(option.title).tag(PaceChoice?.some(option))
                        }
                    } label: {
                        profileFieldLabel("Pace", icon: "speedometer", color: .yellow)
                    }

                    if draft.hasBaselineValues {
                        let metrics = OnboardingCalculator.metrics(from: draft)
                        LabeledContent {
                            Text("\(metrics.targetKcal) kcal/day")
                        } label: {
                            profileFieldLabel("Target calories", icon: "flame.fill", color: .red)
                        }
                    }
                }

                Section("Preferences") {
                    ForEach(PreferenceChoice.allCases.filter { $0 != .noPreference }) { preference in
                        let iconStyle = preferenceIconStyle(for: preference)
                        Toggle(isOn: preferenceBinding(preference)) {
                            profileFieldLabel(preference.title, icon: iconStyle.symbol, color: iconStyle.color)
                        }
                    }
                }

                Section("Account & Permissions") {
                    Picker(selection: accountProviderBinding) {
                        Text("Select method").tag(AccountProvider?.none)
                        Text("Apple").tag(AccountProvider?.some(.apple))
                        Text("Google").tag(AccountProvider?.some(.google))
                        Text("Email").tag(AccountProvider?.some(.email))
                    } label: {
                        profileFieldLabel("Sign in method", icon: "person.crop.circle.badge.checkmark", color: .cyan)
                    }

                    Toggle(isOn: healthToggleBinding) {
                        profileFieldLabel("Connect Health", icon: "heart.text.square.fill", color: .pink)
                    }
                    Toggle(isOn: $draft.enableNotifications) {
                        profileFieldLabel("Enable notifications", icon: "bell.badge.fill", color: .orange)
                    }

                    if isRequestingHealthPermission {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Requesting Apple Health access...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if let healthPermissionMessage {
                        Text(healthPermissionMessage)
                            .font(.footnote)
                            .foregroundStyle(draft.connectHealth ? .green : .secondary)
                    }
                }

                if isAdmin {
                    Section("Admin AI Providers") {
                        Toggle(isOn: $adminGeminiEnabled) {
                            profileFieldLabel("Enable Gemini", icon: "sparkles", color: .purple)
                        }
                        Toggle(isOn: $adminFatsecretEnabled) {
                            profileFieldLabel("Enable Food Database", icon: "bolt.heart.fill", color: .red)
                        }

                        if isAdminFlagsLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Loading admin settings...")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let adminFlagsMessage {
                            Text(adminFlagsMessage)
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                        if let adminFlagsError {
                            Text(adminFlagsError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        Button("Save AI provider settings") {
                            Task { await saveAdminFlags() }
                        }
                        .disabled(isAdminFlagsSaving)

                        if isAdminFlagsSaving {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Saving admin settings...")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    if let saveMessage {
                        Text(saveMessage)
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                    if let saveError {
                        Text(saveError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button("Save changes") {
                        Task { await saveProfileChanges() }
                    }
                    .disabled(isSaving || !draft.hasBaselineValues || draft.goal == nil || draft.activity == nil || draft.pace == nil)

                    if isSaving {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Saving...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Restart onboarding", role: .destructive) {
                        isRestartOnboardingAlertPresented = true
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .alert("Restart onboarding?", isPresented: $isRestartOnboardingAlertPresented) {
                Button("Cancel", role: .cancel) { }
                Button("Restart", role: .destructive) {
                    appStore.resetOnboarding()
                }
            } message: {
                Text("This will send you back to onboarding.")
            }
            .task {
                loadDraftIfNeeded()
                await loadAdminFlags()
            }
        }
    }

    private var goalBinding: Binding<GoalOption?> {
        Binding(
            get: { draft.goal },
            set: { draft.goal = $0 }
        )
    }

    private var sexBinding: Binding<SexOption?> {
        Binding(
            get: { draft.sex },
            set: { draft.sex = $0 }
        )
    }

    private var unitsBinding: Binding<UnitsOption?> {
        Binding(
            get: { draft.units },
            set: { draft.setUnitsPreservingBaseline($0 ?? .imperial) }
        )
    }

    private var profileAgeBinding: Binding<Double> {
        Binding(
            get: { draft.ageValue },
            set: { draft.ageValue = $0 }
        )
    }

    private var profileHeightCmBinding: Binding<Double> {
        Binding(
            get: { draft.heightMetricValue },
            set: { draft.heightMetricValue = $0 }
        )
    }

    private var profileWeightBinding: Binding<Double> {
        Binding(
            get: { draft.weightValue },
            set: { draft.weightValue = $0 }
        )
    }

    private var profileFeetBinding: Binding<Int> {
        Binding(
            get: { draft.imperialHeightFeetInches.feet },
            set: { newFeet in
                var composite = draft.imperialHeightFeetInches
                composite.feet = newFeet
                draft.imperialHeightFeetInches = composite
            }
        )
    }

    private var profileInchesBinding: Binding<Int> {
        Binding(
            get: { draft.imperialHeightFeetInches.inches },
            set: { newInches in
                var composite = draft.imperialHeightFeetInches
                composite.inches = newInches
                draft.imperialHeightFeetInches = composite
            }
        )
    }

    private var activityBinding: Binding<ActivityChoice?> {
        Binding(
            get: { draft.activity },
            set: { draft.activity = $0 }
        )
    }

    private var paceBinding: Binding<PaceChoice?> {
        Binding(
            get: { draft.pace },
            set: { draft.pace = $0 }
        )
    }

    private var accountProviderBinding: Binding<AccountProvider?> {
        Binding(
            get: { draft.accountProvider },
            set: { draft.accountProvider = $0 }
        )
    }

    private struct FieldIconStyle {
        let symbol: String
        let color: Color
    }

    private func preferenceIconStyle(for preference: PreferenceChoice) -> FieldIconStyle {
        switch preference {
        case .highProtein:
            return FieldIconStyle(symbol: "bolt.fill", color: .orange)
        case .vegetarian:
            return FieldIconStyle(symbol: "leaf", color: .green)
        case .vegan:
            return FieldIconStyle(symbol: "leaf.fill", color: .mint)
        case .pescatarian:
            return FieldIconStyle(symbol: "fish", color: .cyan)
        case .lowCarb:
            return FieldIconStyle(symbol: "minus.circle.fill", color: .teal)
        case .keto:
            return FieldIconStyle(symbol: "bolt.circle.fill", color: .yellow)
        case .glutenFree:
            return FieldIconStyle(symbol: "checkmark.circle.fill", color: .indigo)
        case .dairyFree:
            return FieldIconStyle(symbol: "drop.fill", color: .blue)
        case .halal:
            return FieldIconStyle(symbol: "moon.fill", color: .purple)
        case .lowSodium:
            return FieldIconStyle(symbol: "heart.text.square.fill", color: .pink)
        case .mediterranean:
            return FieldIconStyle(symbol: "sun.max.fill", color: .red)
        case .noPreference:
            return FieldIconStyle(symbol: "fork.knife", color: .secondary)
        }
    }

    private func profileFieldLabel(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.24))
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
            }
            .frame(width: 24, height: 24)

            Text(title)
        }
    }

    private var healthToggleBinding: Binding<Bool> {
        Binding(
            get: { draft.connectHealth },
            set: { wantsEnabled in
                if wantsEnabled {
                    requestHealthAccess()
                } else {
                    disconnectHealthAccess()
                }
            }
        )
    }

    private func preferenceBinding(_ preference: PreferenceChoice) -> Binding<Bool> {
        Binding(
            get: { draft.preferences.contains(preference) },
            set: { isEnabled in
                if isEnabled {
                    draft.preferences.insert(preference)
                    draft.preferences.remove(.noPreference)
                } else {
                    draft.preferences.remove(preference)
                }
                if draft.preferences.isEmpty {
                    draft.preferences = [.noPreference]
                }
            }
        )
    }

    private var goalHeadline: String {
        guard let goal = draft.goal else {
            return "Set your goal"
        }
        return "Goal: \(L10n.goalLabel(goal))"
    }

    private var goalSubheadline: String {
        guard draft.hasBaselineValues else {
            return "Complete your baseline details to personalize targets."
        }
        let metrics = OnboardingCalculator.metrics(from: draft)
        return "Target \(metrics.targetKcal) kcal/day"
    }

    private func loadDraftIfNeeded() {
        guard !hasLoadedDraft else { return }
        hasLoadedDraft = true
        appStore.refreshHealthAuthorizationState()
        if let persisted = OnboardingPersistence.load() {
            draft = persisted.draft
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
                    healthPermissionMessage = granted
                        ? "Apple Health connected."
                        : "Apple Health permission was not granted."
                    isRequestingHealthPermission = false
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    draft.connectHealth = false
                    healthPermissionMessage = message
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

    private func saveProfileChanges() async {
        saveError = nil
        saveMessage = nil
        isSaving = true
        defer { isSaving = false }

        guard let goal = draft.goal, let activity = draft.activity else {
            saveError = "Please complete required fields first."
            return
        }

        if draft.preferences.isEmpty {
            draft.preferences = [.noPreference]
        }

        let request = OnboardingRequest(
            goal: goal,
            dietPreference: dietPreferencePayload,
            allergies: [],
            units: draft.units ?? .imperial,
            activityLevel: activity.apiValue,
            timezone: TimeZone.current.identifier
        )

        do {
            _ = try await appStore.apiClient.submitOnboarding(request)
            OnboardingPersistence.save(draft: draft, route: .ready)
            saveMessage = "Profile updated."
            appStore.setError(nil)
        } catch {
            if appStore.handleAuthFailureIfNeeded(error) {
                let message = L10n.authSessionExpired
                saveError = message
                appStore.setError(message)
                return
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            saveError = message
            appStore.setError(message)
        }
    }

    private func loadAdminFlags() async {
        guard !isAdminFlagsLoading else { return }
        isAdminFlagsLoading = true
        adminFlagsError = nil
        adminFlagsMessage = nil
        defer { isAdminFlagsLoading = false }

        do {
            let response = try await appStore.apiClient.getAdminFeatureFlags()
            isAdmin = response.isAdmin
            if let flags = response.flags, response.isAdmin {
                adminGeminiEnabled = flags.geminiEnabled
                adminFatsecretEnabled = flags.fatsecretEnabled
            }
        } catch {
            if appStore.handleAuthFailureIfNeeded(error) {
                adminFlagsError = L10n.authSessionExpired
                appStore.setError(L10n.authSessionExpired)
                return
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            adminFlagsError = message
            appStore.setError(message)
        }
    }

    private func saveAdminFlags() async {
        guard isAdmin else { return }
        isAdminFlagsSaving = true
        adminFlagsError = nil
        adminFlagsMessage = nil
        defer { isAdminFlagsSaving = false }

        do {
            let request = AdminFeatureFlagsUpdateRequest(
                geminiEnabled: adminGeminiEnabled,
                fatsecretEnabled: adminFatsecretEnabled
            )
            let response = try await appStore.apiClient.updateAdminFeatureFlags(request)
            if let flags = response.flags {
                adminGeminiEnabled = flags.geminiEnabled
                adminFatsecretEnabled = flags.fatsecretEnabled
            }
            adminFlagsMessage = "Admin settings updated."
        } catch {
            if appStore.handleAuthFailureIfNeeded(error) {
                adminFlagsError = L10n.authSessionExpired
                appStore.setError(L10n.authSessionExpired)
                return
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            adminFlagsError = message
            appStore.setError(message)
        }
    }

    private var dietPreferencePayload: String {
        if draft.preferences.isEmpty || draft.preferences.contains(.noPreference) {
            return "no_preference"
        }
        return draft.preferences
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
    }
}

#Preview {
    ContentView()
        .environmentObject(AppStore())
}
