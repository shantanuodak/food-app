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

private struct HomeTabShellView: View {
    @State private var isVoiceActive = false
    @State private var isKeyboardVisible = false

    var body: some View {
        ZStack(alignment: .bottom) {
            MainLoggingShellView()

            // Floating centered mic + camera + keyboard dismiss buttons
            if !isVoiceActive {
                HStack(spacing: 12) {
                    Button {
                        NotificationCenter.default.post(name: .openVoiceFromTabBar, object: nil)
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color(red: 0.796, green: 0.188, blue: 0.878)) // #CB30E0
                            .frame(width: 60, height: 60)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel(Text("Voice input"))

                    Button {
                        NotificationCenter.default.post(name: .openCameraFromTabBar, object: nil)
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color(red: 0.380, green: 0.333, blue: 0.961)) // #6155F5
                            .frame(width: 60, height: 60)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel(Text("Open camera"))

                    if isKeyboardVisible {
                        Button {
                            NotificationCenter.default.post(name: .dismissKeyboardFromTabBar, object: nil)
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 60, height: 60)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(Text("Dismiss keyboard"))
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    }
                }
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isVoiceActive)
        .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: .voiceRecordingStateChanged)) { notification in
            isVoiceActive = notification.userInfo?["isRecording"] as? Bool ?? false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }
}

extension Notification.Name {
    static let openCameraFromTabBar = Notification.Name("openCameraFromTabBar")
    static let openVoiceFromTabBar = Notification.Name("openVoiceFromTabBar")
    static let voiceRecordingStateChanged = Notification.Name("voiceRecordingStateChanged")
    static let dismissKeyboardFromTabBar = Notification.Name("dismissKeyboardFromTabBar")
}

// MARK: - Profile Screen

struct HomeProfileScreen: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var draft = OnboardingDraft()
    @State private var hasLoadedDraft = false
    @State private var isRequestingHealthPermission = false
    @State private var healthPermissionMessage: String?
    @State private var isRestartOnboardingConfirmationPresented = false
    @State private var isAdmin = false
    @State private var adminGeminiEnabled = false
    @State private var isAdminFlagsLoading = false
    @State private var trackingAccuracy: TrackingAccuracyResponse?
    @State private var isLoadingAccuracy = false

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
                planSection
                bodySection
                dietSection
                appearanceSection
                healthSection
                trackingAccuracySection
                accountSection
                if isAdmin { adminSection }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    saveStatusIndicator
                }
            }
            .confirmationDialog(
                "Restart onboarding?",
                isPresented: $isRestartOnboardingConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Restart", role: .destructive) { appStore.resetOnboarding() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will send you back to onboarding.")
            }
            .onChange(of: draft) { _, _ in triggerDebouncedSave() }
            .task {
                loadDraftIfNeeded()
                await loadAdminFlags()
                await loadTrackingAccuracy()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var summaryHeaderSection: some View {
        Section {
            if draft.hasBaselineValues, let goal = draft.goal {
                let metrics = OnboardingCalculator.metrics(from: draft)
                VStack(spacing: 12) {
                    VStack(spacing: 4) {
                        Text("\(metrics.targetKcal)")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.primary)
                        Text("kcal / day target")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        macroPill("P", value: metrics.proteinTarget, color: .blue)
                        macroPill("C", value: metrics.carbTarget, color: .orange)
                        macroPill("F", value: metrics.fatTarget, color: .purple)
                    }

                    Text("\(L10n.goalLabel(goal)) · \(draft.pace?.title ?? "Balanced") pace")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ContentUnavailableView(
                    "Complete your profile",
                    systemImage: "chart.bar.fill",
                    description: Text("Set your goal and body details to see your daily target.")
                )
                .padding(.vertical, 8)
            }
        }
        .listRowBackground(Color.clear)
    }

    private func macroPill(_ label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(color)
            Text("\(value)g").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.12)))
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
                Button {
                    togglePreference(pref)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: preferenceIconStyle(for: pref).symbol)
                            .foregroundStyle(preferenceIconStyle(for: pref).color)
                            .frame(width: 22)
                        Text(pref.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if draft.preferences.contains(pref) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .font(.body.weight(.semibold))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Dietary Preferences")
        } footer: {
            if activePrefs.isEmpty {
                Text("Select any that apply.")
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: appearancePreferenceBinding) {
                ForEach(AppearancePreference.allCases) { pref in
                    Text(pref.title).tag(pref)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        Section {
            Toggle(isOn: healthToggleBinding) {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                        .frame(width: 22)
                    Text("Apple Health")
                }
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

    private var trackingAccuracySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Tracking Accuracy", systemImage: "chart.bar.fill")
                        .font(.headline)
                    Spacer()
                    if isLoadingAccuracy {
                        ProgressView().controlSize(.small)
                    }
                }

                if let accuracy = trackingAccuracy, accuracy.entryCount > 0 {
                    // Tier message
                    HStack(spacing: 8) {
                        Circle()
                            .fill(tierColor(accuracy.tier))
                            .frame(width: 10, height: 10)
                        Text(tierMessage(accuracy.tier))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Progress bar
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("All time")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(accuracy.averageConfidence * 100))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tierColor(accuracy.tier))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(.systemGray5))
                                    .frame(height: 8)
                                Capsule()
                                    .fill(tierColor(accuracy.tier))
                                    .frame(width: max(0, geo.size.width * accuracy.averageConfidence), height: 8)
                            }
                        }
                        .frame(height: 8)

                        Text("\(accuracy.entryCount) entries logged")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    // Coaching suggestions
                    if !accuracy.lowConfidenceEntries.isEmpty {
                        Divider().padding(.vertical, 4)

                        Text("Tips to improve")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(accuracy.lowConfidenceEntries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\"\(entry.rawText)\"")
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(Int(entry.confidence * 100))%")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(tierColor(
                                            entry.confidence >= 0.70 ? "good" : "fair"
                                        ))
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                    Text(entry.suggestion)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else if !isLoadingAccuracy {
                    Text("Log some food to see your tracking accuracy")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Insights")
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
                isRestartOnboardingConfirmationPresented = true
            } label: {
                Label("Restart Onboarding", systemImage: "arrow.counterclockwise")
            }
        }
    }

    private var adminSection: some View {
        Section("Admin") {
            Toggle(isOn: $adminGeminiEnabled) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                        .frame(width: 22)
                    Text("Gemini AI")
                }
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

    private struct FieldIconStyle {
        let symbol: String
        let color: Color
    }

    private func preferenceIconStyle(for preference: PreferenceChoice) -> FieldIconStyle {
        switch preference {
        case .highProtein: return FieldIconStyle(symbol: "bolt.fill", color: .orange)
        case .vegetarian:  return FieldIconStyle(symbol: "leaf", color: .green)
        case .vegan:       return FieldIconStyle(symbol: "leaf.fill", color: .mint)
        case .pescatarian: return FieldIconStyle(symbol: "fish", color: .cyan)
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
            OnboardingPersistence.save(draft: draft, route: .ready)
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


#Preview {
    ContentView()
        .environmentObject(AppStore())
}
