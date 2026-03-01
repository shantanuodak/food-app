import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appStore: AppStore
    @ObservedObject var flow: AppFlowCoordinator

    @State private var draft = OnboardingDraft()
    @State private var localError: String?
    @State private var isSubmitting = false
    @State private var isAccountLoading = false
    @State private var isRequestingHealthPermission = false
    @State private var healthPermissionMessage: String?
    @State private var hasRestored = false
    @State private var pendingRouteError: String?
    @State private var screenStates: [OnboardingRoute: OnboardingScreenState] = {
        OnboardingRoute.allCases.reduce(into: [OnboardingRoute: OnboardingScreenState]()) { result, route in
            result[route] = OnboardingScreenState()
        }
    }()

    private let totalProgressSteps = 6
    private let defaults = UserDefaults.standard

    private var metrics: OnboardingMetrics {
        OnboardingCalculator.metrics(from: draft)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OnboardingAnimatedBackground()

                if flow.onboardingRoute == .welcome {
                    VStack(spacing: 14) {
                        Spacer(minLength: 16)
                        bodyBlock
                        Spacer(minLength: 8)

                        VStack(spacing: 8) {
                            Text(flow.onboardingRoute.headline)
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(OnboardingGlassTheme.textPrimary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)

                            if !flow.onboardingRoute.subhead.isEmpty {
                                Text(flow.onboardingRoute.subhead)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .offset(y: -12)

                        if let localError {
                            Text(localError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        actionBlock
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        if let progressStep = flow.onboardingRoute.progressStep {
                            OnboardingProgressHeader(step: progressStep, total: totalProgressSteps)
                        }

                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                headerBlock
                                bodyBlock

                                if let localError {
                                    Text(localError)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }

                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 12)
                        }

                        valuePropositionBlock
                        actionBlock
                    }
                    .padding()
                }
            }
            .navigationTitle(flow.onboardingRoute == .welcome ? "" : flow.onboardingRoute.headline)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if flow.onboardingRoute.hasBack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            flow.moveBackOnboarding()
                        }
                        .disabled(isSubmitting || isAccountLoading)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(OnboardingRoute.allCases, id: \.self) { route in
                            Button(route.headline) {
                                flow.moveToOnboarding(route)
                            }
                        }
                        Divider()
                        Button("Clear auth session", role: .destructive) {
                            appStore.authService.signOut()
                            localError = "Auth session cleared. Sign in again on Save your setup."
                        }
                    } label: {
                        Image(systemName: "ladybug")
                    }
                    .accessibilityLabel(Text("Debug route jump"))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear {
            appStore.refreshHealthAuthorizationState()
            restorePersistedContextIfNeeded()
            syncScreenStateHooks()
        }
        .onChange(of: draft) { _, _ in
            persistDraft()
            syncScreenStateHooks()
        }
        .onChange(of: flow.onboardingRoute) { _, _ in
            if let pendingRouteError {
                localError = pendingRouteError
                self.pendingRouteError = nil
            } else {
                localError = nil
            }
            persistDraft()
            syncScreenStateHooks()
        }
    }

    private var currentScreenState: OnboardingScreenState {
        screenStates[flow.onboardingRoute] ?? OnboardingScreenState()
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(flow.onboardingRoute.headline)
                .font(.title2.bold())
            if !flow.onboardingRoute.subhead.isEmpty {
                Text(flow.onboardingRoute.subhead)
                    .font(.subheadline)
                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var bodyBlock: some View {
        switch flow.onboardingRoute {
        case .welcome:
            OB01WelcomeScreen()
        case .goal:
            OB02GoalScreen(selectedGoal: $draft.goal)
        case .baseline:
            OB03BaselineScreen(
                draft: $draft,
                isValid: draft.isBaselineValid
            )
        case .activity:
            OB04ActivityScreen(selectedActivity: $draft.activity)
        case .pace:
            OB05PaceScreen(selectedPace: $draft.pace)
        case .preferencesOptional:
            OB06PreferencesOptionalScreen(preferences: $draft.preferences)
        case .planPreview:
            OB07PlanPreviewScreen(
                targetKcal: metrics.targetKcal,
                protein: metrics.proteinTarget,
                carbs: metrics.carbTarget,
                fat: metrics.fatTarget
            )
        case .account:
            OB08AccountScreen(
                isLoading: isAccountLoading,
                prefersGooglePrimary: isSupabaseAuthMode,
                enableApple: true,
                enableEmail: !isSupabaseAuthMode,
                onSelectProvider: continueAccount(provider:)
            )
        case .permissions:
            OB09PermissionsScreen(
                connectHealth: $draft.connectHealth,
                enableNotifications: $draft.enableNotifications,
                isRequestingHealthPermission: isRequestingHealthPermission,
                healthPermissionMessage: healthPermissionMessage,
                onConnectHealth: requestHealthAccess,
                onDisconnectHealth: disconnectHealthAccess
            )
        case .ready:
            OB10ReadyScreen()
        }
    }

    @ViewBuilder
    private var actionBlock: some View {
        switch flow.onboardingRoute {
        case .welcome:
            VStack(spacing: 10) {
                primaryButton("Start") {
                    flow.moveNextOnboarding()
                }
                secondaryButton("I already have an account") {
                    flow.moveToOnboarding(.account)
                }
            }
        case .goal, .baseline, .activity, .pace:
            primaryButton("Continue") {
                flow.moveNextOnboarding()
            }
            .disabled(!canContinueCurrentScreen)
        case .preferencesOptional:
            VStack(spacing: 10) {
                primaryButton("Continue") {
                    flow.moveNextOnboarding()
                }
                secondaryButton("Skip for now") {
                    draft.preferences = [.noPreference]
                    flow.moveNextOnboarding()
                }
            }
        case .planPreview:
            VStack(spacing: 10) {
                primaryButton("Looks good") {
                    flow.moveNextOnboarding()
                }
                secondaryButton("Adjust plan") {
                    flow.moveToOnboarding(.goal)
                }
            }
        case .account:
            EmptyView()
        case .permissions:
            primaryButton("Continue to app") {
                flow.moveNextOnboarding()
            }
            .disabled(isRequestingHealthPermission)
        case .ready:
            VStack(spacing: 10) {
                primaryButton("Log first meal") {
                    finishOnboarding()
                }
                secondaryButton("Explore app") {
                    finishOnboarding()
                }
                .disabled(isSubmitting)
            }
        }
    }

    private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                if isSubmitting {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text(label)
                }
                Spacer()
            }
        }
        .buttonStyle(OnboardingGlassPrimaryButtonStyle())
        .disabled(isSubmitting || isAccountLoading)
    }

    private func secondaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(OnboardingGlassSecondaryButtonStyle())
            .disabled(isSubmitting || isAccountLoading)
    }

    private var canContinueCurrentScreen: Bool {
        switch flow.onboardingRoute {
        case .goal:
            return draft.goal != nil
        case .baseline:
            return draft.isBaselineValid
        case .activity:
            return draft.activity != nil
        case .pace:
            return draft.pace != nil
        default:
            return true
        }
    }

    private var selectedPreferenceTitles: String {
        draft.preferences
            .filter { $0 != .noPreference }
            .map(\.title)
            .sorted()
            .joined(separator: ", ")
    }

    private var isSupabaseAuthMode: Bool {
        guard appStore.configuration.supabaseURL != nil else { return false }
        let anon = appStore.configuration.supabaseAnonKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        return !(anon?.isEmpty ?? true)
    }

    @ViewBuilder
    private var valuePropositionBlock: some View {
        switch flow.onboardingRoute {
        case .goal:
            if let goal = draft.goal {
                OnboardingValueCard(
                    title: "Your plan direction",
                    bodyText: "Great, we’ll optimize your targets for \(L10n.goalLabel(goal)).",
                    isSuccess: true
                )
            }
        case .baseline:
            if draft.isBaselineValid {
                OnboardingValueCard(
                    title: "Estimated maintenance",
                    bodyText: "Based on your profile, your maintenance is about \(metrics.estimatedMaintenanceKcal) kcal/day."
                )
            }
        case .activity:
            if draft.activity != nil {
                OnboardingValueCard(
                    title: "Updated daily target",
                    bodyText: "With this activity level, your target is \(metrics.targetKcal) kcal/day.",
                    isSuccess: true
                )
            }
        case .pace:
            if draft.pace != nil {
                OnboardingValueCard(
                    title: "Projected milestone",
                    bodyText: "At this pace, you’re likely to reach your goal around \(metrics.projectedGoalDate).",
                    isSuccess: true
                )
            }
        case .preferencesOptional:
            if !draft.preferences.isEmpty {
                let isFlexible = draft.preferences.contains(.noPreference)
                OnboardingValueCard(
                    title: "Personalization",
                    bodyText: isFlexible
                        ? "No strict preference selected yet. You can keep this open for flexibility."
                        : "We’ll prioritize foods that fit: \(selectedPreferenceTitles).",
                    isSuccess: !isFlexible
                )
            }
        case .permissions:
            let enabledCount = (draft.connectHealth ? 1 : 0) + (draft.enableNotifications ? 1 : 0)
            if enabledCount > 0 {
                OnboardingValueCard(
                    title: "Setup status",
                    bodyText: "\(enabledCount) integration\(enabledCount == 1 ? "" : "s") enabled.",
                    isSuccess: true
                )
            }
        default:
            EmptyView()
        }
    }

    private func continueAccount(provider: AccountProvider) {
        guard !isAccountLoading else { return }
        draft.accountProvider = provider
        localError = nil
        isAccountLoading = true
        setScreenState(.account, state: .loading)

        Task {
            do {
                _ = try await appStore.authService.signIn(with: provider)
                await MainActor.run {
                    isAccountLoading = false
                    setScreenState(.account, state: .default)
                    flow.moveNextOnboarding()
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    isAccountLoading = false
                    localError = message
                    setScreenState(.account, state: .error, errorMessage: message)
                }
            }
        }
    }

    private func finishOnboarding() {
        Task {
            isSubmitting = true
            localError = nil
            appStore.setError(nil)
            setScreenState(.ready, state: .loading)
            defer { isSubmitting = false }

            let request = OnboardingRequest(
                goal: draft.goal ?? .maintain,
                dietPreference: dietPreferencePayload,
                allergies: [],
                units: draft.units ?? .imperial,
                activityLevel: draft.activity?.apiValue ?? .moderate,
                timezone: TimeZone.current.identifier
            )

            do {
                _ = try await appStore.apiClient.submitOnboarding(request)
                OnboardingPersistence.save(draft: draft, route: flow.onboardingRoute, defaults: defaults)
                appStore.setHealthSyncEnabled(draft.connectHealth)
                appStore.markOnboardingComplete()
                setScreenState(.ready, state: .default)
                flow.showHome()
            } catch {
                if appStore.handleAuthFailureIfNeeded(error) {
                    let message = isSupabaseAuthMode
                        ? "Session expired. Please sign in again with Apple or Google."
                        : L10n.authSessionExpired
                    appStore.setError(message)
                    setScreenState(.ready, state: .error, errorMessage: message)
                    setScreenState(.account, state: .error, errorMessage: message)
                    pendingRouteError = message
                    flow.moveToOnboarding(.account)
                    return
                }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                localError = message
                appStore.setError(message)
                setScreenState(.ready, state: .error, errorMessage: message)
            }
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

    private func setScreenState(_ route: OnboardingRoute, state: OnboardingScreenLoadState, errorMessage: String? = nil) {
        screenStates[route] = OnboardingScreenState(loadState: state, errorMessage: errorMessage)
    }

    private func syncScreenStateHooks() {
        if canContinueCurrentScreen {
            if currentScreenState.loadState == .disabled {
                setScreenState(flow.onboardingRoute, state: .default)
            }
        } else if [.goal, .baseline, .activity, .pace].contains(flow.onboardingRoute) {
            setScreenState(flow.onboardingRoute, state: .disabled)
        }
    }

    private func persistDraft() {
        OnboardingPersistence.save(draft: draft, route: flow.onboardingRoute, defaults: defaults)
    }

    private func restorePersistedContextIfNeeded() {
        guard !hasRestored else { return }
        hasRestored = true
        guard !appStore.isOnboardingComplete else {
            OnboardingPersistence.clear(defaults: defaults)
            return
        }

        guard let restored = OnboardingPersistence.load(defaults: defaults) else {
            return
        }
        var restoredDraft = restored.draft
        if restoredDraft.units == nil {
            restoredDraft.units = .imperial
        }
        draft = restoredDraft
        appStore.setHealthSyncEnabled(draft.connectHealth)
        draft.connectHealth = appStore.isHealthSyncEnabled
        flow.moveToOnboarding(restored.route)
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
}

#Preview {
    OnboardingView(flow: AppFlowCoordinator())
        .environmentObject(AppStore())
}
