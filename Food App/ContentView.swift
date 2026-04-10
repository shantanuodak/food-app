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
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .log: return "Log"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .log: return "fork.knife.circle"
        case .profile: return "person.crop.circle"
        }
    }
}

private struct HomeTabShellView: View {
    @State private var selectedTab: HomeRootTab = .log

    var body: some View {
        TabView(selection: $selectedTab) {
            MainLoggingShellView()
                .tabItem { Label("Log", systemImage: "fork.knife.circle") }
                .tag(HomeRootTab.log)

            HomeProfileScreen()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(HomeRootTab.profile)
        }
    }
}

extension Notification.Name {
    static let openCameraFromTabBar = Notification.Name("openCameraFromTabBar")
}

// MARK: - Profile Screen

private struct HomeProfileScreen: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var draft = OnboardingDraft()
    @State private var hasLoadedDraft = false
    @State private var activeSheet: ProfileSheet?
    @State private var isRequestingHealthPermission = false
    @State private var healthPermissionMessage: String?
    @State private var isRestartOnboardingAlertPresented = false
    @State private var isAdmin = false
    @State private var adminGeminiEnabled = false
    @State private var isAdminFlagsLoading = false

    // Auto-save
    private enum SaveStatus: Equatable {
        case idle, saving, saved, failed(String)
    }
    @State private var saveStatus: SaveStatus = .idle
    @State private var saveTask: Task<Void, Never>?
    @State private var savedResetTask: Task<Void, Never>?

    private enum ProfileSheet: String, Identifiable {
        case plan, body, diet
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    summaryHeaderCard
                    planCard
                    bodyCard
                    dietCard
                    appSettingsSection
                    accountSection

                    if isAdmin {
                        adminSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    saveStatusIndicator
                }
            }
            .sheet(item: $activeSheet, onDismiss: { triggerDebouncedSave() }) { sheet in
                switch sheet {
                case .plan: ProfilePlanEditSheet(draft: $draft)
                case .body: ProfileBodyEditSheet(draft: $draft)
                case .diet: ProfileDietEditSheet(draft: $draft)
                }
            }
            .alert("Restart onboarding?", isPresented: $isRestartOnboardingAlertPresented) {
                Button("Cancel", role: .cancel) { }
                Button("Restart", role: .destructive) { appStore.resetOnboarding() }
            } message: {
                Text("This will send you back to onboarding.")
            }
            .task {
                loadDraftIfNeeded()
                await loadAdminFlags()
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
                ProgressView()
                    .scaleEffect(0.7)
                Text("Saving…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .saved:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("Saved")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            .transition(.opacity)
        case .failed:
            Button {
                triggerDebouncedSave(immediate: true)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text("Retry")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Summary Header Card

    private var summaryHeaderCard: some View {
        VStack(spacing: 12) {
            if draft.hasBaselineValues, let goal = draft.goal {
                let metrics = OnboardingCalculator.metrics(from: draft)
                Text("\(metrics.targetKcal)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("kcal / day target")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    macroPill("P", value: metrics.proteinTarget, color: .blue)
                    macroPill("C", value: metrics.carbTarget, color: .orange)
                    macroPill("F", value: metrics.fatTarget, color: .purple)
                }

                Text("\(L10n.goalLabel(goal)) · \(draft.pace?.title ?? "Balanced") pace")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Complete your profile to see targets")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func macroPill(_ label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text("\(value)g")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }

    // MARK: - Plan Card

    private var planCard: some View {
        Button { activeSheet = .plan } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Your Plan", systemImage: "target")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 3) {
                        profileRow("Goal", value: draft.goal.map { L10n.goalLabel($0) } ?? "Not set")
                        profileRow("Activity", value: draft.activity?.title ?? "Not set")
                        profileRow("Pace", value: draft.pace?.title ?? "Not set")
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Body Card

    private var bodyWeightLabel: String {
        let unitLabel = (draft.units ?? .imperial) == .metric ? "kg" : "lbs"
        return "\(Int(draft.weightValue)) \(unitLabel)"
    }

    private var bodyHeightLabel: String {
        if (draft.units ?? .imperial) == .metric {
            return "\(Int(draft.heightMetricValue)) cm"
        }
        let h = draft.imperialHeightFeetInches
        return "\(h.feet)'\(h.inches)\""
    }

    private var bodyCard: some View {
        Button { activeSheet = .body } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Body", systemImage: "figure.stand")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    bodyMetricsGrid
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private var bodyMetricsGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            profileRow("Weight", value: bodyWeightLabel)
            profileRow("Height", value: bodyHeightLabel)
            profileRow("Age", value: "\(Int(draft.ageValue))")
            profileRow("Sex", value: draft.sex?.title ?? "Not set")
        }
    }

    // MARK: - Diet Card

    private var sortedActivePreferences: [PreferenceChoice] {
        draft.preferences.filter { $0 != .noPreference }.sorted(by: { $0.rawValue < $1.rawValue })
    }

    private func dietPill(for pref: PreferenceChoice) -> some View {
        let style = preferenceIconStyle(for: pref)
        return HStack(spacing: 4) {
            Image(systemName: style.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(style.color)
            Text(pref.title)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(style.color.opacity(0.12)))
    }

    private var dietCard: some View {
        Button { activeSheet = .diet } label: {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Diet", systemImage: "fork.knife")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if sortedActivePreferences.isEmpty {
                        Text("No dietary preferences")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(sortedActivePreferences, id: \.self) { pref in
                                dietPill(for: pref)
                            }
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - App Settings (inline)

    private var appSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Settings", systemImage: "gearshape.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                // Appearance
                HStack {
                    Text("Appearance")
                        .font(.subheadline)
                    Spacer()
                    Picker("Appearance", selection: appearancePreferenceBinding) {
                        ForEach(AppearancePreference.allCases) { pref in
                            Text(pref.title).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading, 16)

                // Health
                HStack {
                    Toggle(isOn: healthToggleBinding) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.text.square.fill")
                                .foregroundStyle(.pink)
                            Text("Apple Health")
                                .font(.subheadline)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if isRequestingHealthPermission {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Requesting access…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                } else if let healthPermissionMessage {
                    Text(healthPermissionMessage)
                        .font(.caption)
                        .foregroundStyle(draft.connectHealth ? .green : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Account", systemImage: "person.crop.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: draft.accountProvider == .apple ? "apple.logo" : "globe")
                        .foregroundStyle(.secondary)
                    Text("Signed in with \(draft.accountProvider == .apple ? "Apple" : "Google")")
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading, 16)

                Button(role: .destructive) {
                    isRestartOnboardingAlertPresented = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Restart Onboarding")
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Admin Section

    private var adminSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Admin", systemImage: "wrench.and.screwdriver.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                Toggle(isOn: $adminGeminiEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                        Text("Gemini AI")
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .onChange(of: adminGeminiEnabled) { _, _ in triggerAdminAutoSave() }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Helpers

    private func profileRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private struct FieldIconStyle {
        let symbol: String
        let color: Color
    }

    private func preferenceIconStyle(for preference: PreferenceChoice) -> FieldIconStyle {
        switch preference {
        case .highProtein: return FieldIconStyle(symbol: "bolt.fill", color: .orange)
        case .vegetarian:  return FieldIconStyle(symbol: "leaf", color: .green)
        case .vegan:       return FieldIconStyle(symbol: "leaf.fill", color: .mint)
        case .pescatarian:  return FieldIconStyle(symbol: "fish", color: .cyan)
        case .lowCarb:     return FieldIconStyle(symbol: "minus.circle.fill", color: .teal)
        case .keto:        return FieldIconStyle(symbol: "bolt.circle.fill", color: .yellow)
        case .glutenFree:  return FieldIconStyle(symbol: "checkmark.circle.fill", color: .indigo)
        case .dairyFree:   return FieldIconStyle(symbol: "drop.fill", color: .blue)
        case .halal:       return FieldIconStyle(symbol: "moon.fill", color: .purple)
        case .lowSodium:   return FieldIconStyle(symbol: "heart.text.square.fill", color: .pink)
        case .mediterranean: return FieldIconStyle(symbol: "sun.max.fill", color: .red)
        case .noPreference: return FieldIconStyle(symbol: "fork.knife", color: .secondary)
        }
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

    private var healthToggleBinding: Binding<Bool> {
        Binding(
            get: { draft.connectHealth },
            set: { wantsEnabled in
                if wantsEnabled { requestHealthAccess() } else { disconnectHealthAccess() }
            }
        )
    }

    private var appearancePreferenceBinding: Binding<AppearancePreference> {
        Binding(
            get: { appStore.appearancePreference },
            set: { appStore.setAppearancePreference($0) }
        )
    }

    private var dietPreferencePayload: String {
        if draft.preferences.isEmpty || draft.preferences.contains(.noPreference) {
            return "no_preference"
        }
        return draft.preferences.map(\.rawValue).sorted().joined(separator: ",")
    }

    // MARK: - Data loading

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
            // Always persist locally
            OnboardingPersistence.save(draft: draft, route: .ready)
            // Only call API if profile is complete enough
            guard draft.hasBaselineValues, let goal = draft.goal, let activity = draft.activity else { return }
            if draft.preferences.isEmpty { draft.preferences = [.noPreference] }
            let request = OnboardingRequest(
                goal: goal,
                dietPreference: dietPreferencePayload,
                allergies: [],
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
                _ = try await appStore.apiClient.submitOnboarding(request)
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
                let request = AdminFeatureFlagsUpdateRequest(
                    geminiEnabled: adminGeminiEnabled
                )
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

// MARK: - Edit Sheets

private struct ProfilePlanEditSheet: View {
    @Binding var draft: OnboardingDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Goal
                    sectionHeader("Goal", icon: "target")
                    HStack(spacing: 10) {
                        ForEach(GoalOption.allCases) { option in
                            selectionChip(
                                title: L10n.goalLabel(option),
                                isSelected: draft.goal == option
                            ) { draft.goal = option }
                        }
                    }

                    // Activity
                    sectionHeader("Activity Level", icon: "figure.walk")
                    VStack(spacing: 8) {
                        ForEach(ActivityChoice.allCases) { option in
                            selectionRow(
                                title: option.title,
                                isSelected: draft.activity == option
                            ) { draft.activity = option }
                        }
                    }

                    // Pace
                    sectionHeader("Pace", icon: "speedometer")
                    HStack(spacing: 10) {
                        ForEach(PaceChoice.allCases) { option in
                            selectionChip(
                                title: option.title,
                                isSelected: draft.pace == option
                            ) { draft.pace = option }
                        }
                    }

                    // Live preview
                    if draft.hasBaselineValues {
                        let metrics = OnboardingCalculator.metrics(from: draft)
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                            Text("Daily target: **\(metrics.targetKcal) kcal**")
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.orange.opacity(0.1))
                        )
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Your Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private func selectionChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func selectionRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileBodyEditSheet: View {
    @Binding var draft: OnboardingDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Units
                    Label("Units", systemImage: "ruler.fill")
                        .font(.subheadline.weight(.semibold))
                    Picker("Units", selection: Binding(
                        get: { draft.units ?? .imperial },
                        set: { draft.setUnitsPreservingBaseline($0) }
                    )) {
                        Text("Imperial").tag(UnitsOption.imperial)
                        Text("Metric").tag(UnitsOption.metric)
                    }
                    .pickerStyle(.segmented)

                    // Sex
                    Label("Sex", systemImage: "person.fill")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 10) {
                        ForEach(SexOption.allCases) { option in
                            Button {
                                draft.sex = option
                            } label: {
                                Text(option.title)
                                    .font(.subheadline.weight(draft.sex == option ? .semibold : .regular))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .foregroundStyle(draft.sex == option ? .white : .primary)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(draft.sex == option ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Baseline cards (reused from onboarding)
                    Label("Age", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                    BaselineAgeCard(
                        age: Binding(get: { draft.ageValue }, set: { draft.ageValue = $0 }),
                        isTouched: $draft.baselineTouchedAge
                    )

                    Label("Height", systemImage: "ruler")
                        .font(.subheadline.weight(.semibold))
                    if draft.units == .metric {
                        BaselineMetricHeightCard(
                            heightCm: Binding(get: { draft.heightMetricValue }, set: { draft.heightMetricValue = $0 }),
                            isTouched: $draft.baselineTouchedHeight
                        )
                    } else {
                        BaselineImperialHeightCard(
                            feet: Binding(
                                get: { draft.imperialHeightFeetInches.feet },
                                set: { val in var c = draft.imperialHeightFeetInches; c.feet = val; draft.imperialHeightFeetInches = c }
                            ),
                            inches: Binding(
                                get: { draft.imperialHeightFeetInches.inches },
                                set: { val in var c = draft.imperialHeightFeetInches; c.inches = val; draft.imperialHeightFeetInches = c }
                            ),
                            isTouched: $draft.baselineTouchedHeight
                        )
                    }

                    Label("Weight", systemImage: "scalemass.fill")
                        .font(.subheadline.weight(.semibold))
                    BaselineWeightCard(
                        weight: Binding(get: { draft.weightValue }, set: { draft.weightValue = $0 }),
                        units: draft.units ?? .imperial,
                        isTouched: $draft.baselineTouchedWeight
                    )
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Body")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ProfileDietEditSheet: View {
    @Binding var draft: OnboardingDraft
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(PreferenceChoice.allCases.filter { $0 != .noPreference }) { pref in
                        let isOn = draft.preferences.contains(pref)
                        let style = iconStyle(for: pref)
                        Button {
                            if isOn {
                                draft.preferences.remove(pref)
                                if draft.preferences.isEmpty { draft.preferences = [.noPreference] }
                            } else {
                                draft.preferences.insert(pref)
                                draft.preferences.remove(.noPreference)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: style.symbol)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(style.color)
                                Text(pref.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                if isOn {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isOn ? style.color.opacity(0.12) : Color(.tertiarySystemGroupedBackground))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Diet Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func iconStyle(for preference: PreferenceChoice) -> (symbol: String, color: Color) {
        switch preference {
        case .highProtein: return ("bolt.fill", .orange)
        case .vegetarian:  return ("leaf", .green)
        case .vegan:       return ("leaf.fill", .mint)
        case .pescatarian:  return ("fish", .cyan)
        case .lowCarb:     return ("minus.circle.fill", .teal)
        case .keto:        return ("bolt.circle.fill", .yellow)
        case .glutenFree:  return ("checkmark.circle.fill", .indigo)
        case .dairyFree:   return ("drop.fill", .blue)
        case .halal:       return ("moon.fill", .purple)
        case .lowSodium:   return ("heart.text.square.fill", .pink)
        case .mediterranean: return ("sun.max.fill", .red)
        case .noPreference: return ("fork.knife", .secondary)
        }
    }
}

// MARK: - FlowLayout (wrapping horizontal layout for pills)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppStore())
}
