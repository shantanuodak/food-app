import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appStore: AppStore
    @ObservedObject var flow: AppFlowCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft = OnboardingDraft()
    @State private var localError: String?
    @State private var isSubmitting = false
    @State private var isAccountLoading = false
    @State private var isRequestingHealthPermission = false
    @State private var healthPermissionMessage: String?
    @State private var hasRestored = false
    @State private var pendingRouteError: String?
    @State private var baselineStep: BaselineScreenStep = .sex
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
                if flow.onboardingRoute == .welcome {
                    OB01WelcomeScreen(
                        onGetStarted: {
                            flow.moveNextOnboarding()
                        },
                        onExistingAccount: {
                            flow.moveToOnboarding(.account)
                        }
                    )
                } else if flow.onboardingRoute == .goal {
                    goalRouteView
                } else if flow.onboardingRoute == .age {
                    ageRouteView
                } else if flow.onboardingRoute == .baseline {
                    baselineRouteView
                } else if flow.onboardingRoute == .activity {
                    activityRouteView
                } else if flow.onboardingRoute == .pace {
                    paceRouteView
                } else if flow.onboardingRoute == .goalValidation {
                    goalValidationRouteView
                } else if flow.onboardingRoute == .socialProof {
                    socialProofRouteView
                } else if flow.onboardingRoute == .experience {
                    experienceRouteView
                } else if flow.onboardingRoute == .howItWorks {
                    howItWorksRouteView
                } else if flow.onboardingRoute == .challenge {
                    challengeRouteView
                } else if flow.onboardingRoute == .challengeInsight {
                    challengeInsightRouteView
                } else if flow.onboardingRoute == .ready {
                    readyRouteView
                } else {
                    OnboardingStaticBackground()

                    VStack(alignment: .leading, spacing: 16) {
                        if let progressStep = flow.onboardingRoute.progressStep {
                            OnboardingProgressHeader(step: progressStep, total: totalProgressSteps)
                        }

                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                headerBlock
                                bodyBlock

                                if flow.onboardingRoute != .ready, let localError {
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
            .navigationTitle(shouldHideNavigationBar ? "" : (flow.onboardingRoute == .welcome ? "" : flow.onboardingRoute.headline))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(shouldHideNavigationBar ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if flow.onboardingRoute.hasBack, !shouldHideNavigationBar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            flow.moveBackOnboarding()
                        }
                        .disabled(isSubmitting || isAccountLoading)
                    }
                }

                if flow.onboardingRoute != .welcome, !shouldHideNavigationBar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(OnboardingRoute.debugRoutes, id: \.self) { route in
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
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear {
            appStore.refreshHealthAuthorizationState()
            restorePersistedContextIfNeeded()
            syncBaselineStepForCurrentDraft()
            syncScreenStateHooks()
        }
        .onChange(of: draft) { _, _ in
            persistDraft()
            syncScreenStateHooks()
        }
        .onChange(of: flow.onboardingRoute) { oldRoute, _ in
            if let pendingRouteError {
                localError = pendingRouteError
                self.pendingRouteError = nil
            } else {
                localError = nil
            }
            if flow.onboardingRoute == .baseline {
                syncBaselineStepOnRouteChange(previousRoute: oldRoute)
            }
            persistDraft()
            syncScreenStateHooks()
        }
    }

    private var currentScreenState: OnboardingScreenState {
        screenStates[flow.onboardingRoute] ?? OnboardingScreenState()
    }

    private var shouldHideNavigationBar: Bool {
        true
    }

    private var goalRouteView: some View {
        let canContinue = canContinueCurrentScreen && !isSubmitting && !isAccountLoading

        return ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                goalTopBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                Spacer()

                OB02GoalScreen(selectedGoal: $draft.goal)
                    .padding(.horizontal, 20)

                if let localError {
                    Text(localError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 16)
                        .padding(.horizontal, 24)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Button {
                    flow.moveNextOnboarding()
                } label: {
                    HStack(spacing: 8) {
                        Text("Next")
                            .font(.system(size: 16, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 220, height: 60)
                    .background(Color.black.opacity(canContinue ? 1 : 0.2))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canContinue)
                .animation(.easeInOut(duration: 0.25), value: canContinue)
                .padding(.bottom, 24)
            }
        }
    }

    private var activityRouteView: some View {
        OB04ActivityScreen(
            selectedActivity: $draft.activity,
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    private var ageRouteView: some View {
        OB03AgeScreen(
            age: $draft.ageValue,
            onBack: { flow.moveBackOnboarding() },
            onContinue: handleAgeContinue
        )
    }

    private var baselineRouteView: some View {
        OB03BaselineScreen(
            draft: $draft,
            step: $baselineStep,
            onBack: handleBaselineBack,
            onContinue: handleBaselineContinue
        )
    }

    private var paceRouteView: some View {
        OB05PaceScreen(
            draft: $draft,
            selectedPace: $draft.pace,
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    private var howItWorksRouteView: some View {
        OB02eHowItWorksScreen(
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    private var experienceRouteView: some View {
        OB02dExperienceScreen(
            selectedExperience: $draft.experience,
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    private var challengeRouteView: some View {
        OB02cChallengeScreen(
            selectedChallenge: $draft.challenge,
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    private var challengeInsightRouteView: some View {
        OB02cChallengeInsightScreen(
            challenge: draft.challenge ?? .portionControl,
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    private var readyRouteView: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                // Top bar with back button
                ZStack {
                    HStack {
                        Button {
                            flow.moveBackOnboarding()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white)
                                        .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting || isAccountLoading)
                        Spacer()
                    }
                }
                .frame(height: 44)
                .padding(.top, 12)
                .padding(.horizontal, 16)

                OB10ReadyScreen(
                    targetKcal: metrics.targetKcal,
                    proteinTarget: metrics.proteinTarget,
                    carbTarget: metrics.carbTarget,
                    fatTarget: metrics.fatTarget,
                    statusMessage: readyScreenStatusMessage,
                    isError: currentScreenState.loadState == .error
                )

                // Action buttons
                VStack(spacing: 10) {
                    primaryButton("Start logging") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        finishOnboarding()
                    }
                    .disabled(isSubmitting)
                    secondaryButton("Explore app") {
                        finishOnboarding()
                    }
                    .disabled(isSubmitting)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var socialProofRouteView: some View {
        OB02bSocialProofScreen(
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    private var goalValidationRouteView: some View {
        OB05bGoalValidationScreen(
            draft: draft,
            metrics: metrics,
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() },
            onAdjustPlan: { flow.moveToOnboarding(.goal) }
        )
    }

    private var goalTopBar: some View {
        ZStack {
            Text("Set Your Goal")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)

            HStack {
                Button {
                    flow.moveBackOnboarding()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || isAccountLoading)

                Spacer()
            }
        }
        .frame(height: 44)
    }

    private var activityTopBar: some View {
        ZStack {
            Text("Your Activity Level")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)

            HStack {
                Button {
                    flow.moveBackOnboarding()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || isAccountLoading)

                Spacer()
            }
        }
        .frame(height: 44)
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(flow.onboardingRoute.headline)
                .font(OnboardingTypography.onboardingHeadline())
                .foregroundStyle(OnboardingGlassTheme.textPrimary)
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
            EmptyView()
        case .goal:
            OB02GoalScreen(selectedGoal: $draft.goal)
        case .age:
            EmptyView()
        case .baseline:
            EmptyView()
        case .activity:
            EmptyView()
        case .pace:
            EmptyView()
        case .goalValidation:
            EmptyView()
        case .socialProof:
            EmptyView()
        case .challenge:
            EmptyView()
        case .challengeInsight:
            EmptyView()
        case .experience:
            EmptyView()
        case .howItWorks:
            EmptyView()
        case .preferencesOptional:
            OB06PreferencesOptionalScreen(preferences: $draft.preferences)
        case .planPreview:
            EmptyView()
        case .account:
            OB08AccountScreen(
                isLoading: isAccountLoading,
                prefersGooglePrimary: isSupabaseAuthMode,
                enableApple: true,
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
            OB10ReadyScreen(
                targetKcal: metrics.targetKcal,
                proteinTarget: metrics.proteinTarget,
                carbTarget: metrics.carbTarget,
                fatTarget: metrics.fatTarget,
                statusMessage: readyScreenStatusMessage,
                isError: currentScreenState.loadState == .error
            )
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
        case .goal, .age, .baseline, .activity, .pace, .socialProof, .experience, .howItWorks, .challenge, .challengeInsight:
            primaryButton("Next") {
                flow.moveNextOnboarding()
            }
            .disabled(!canContinueCurrentScreen)
            .opacity(canContinueCurrentScreen ? 1 : 0.4)
        case .goalValidation:
            EmptyView()
        case .preferencesOptional:
            VStack(spacing: 10) {
                primaryButton("Next") {
                    flow.moveNextOnboarding()
                }
                secondaryButton("Skip for now") {
                    draft.preferences = [.noPreference]
                    flow.moveNextOnboarding()
                }
            }
        case .planPreview:
            EmptyView()
        case .account:
            EmptyView()
        case .permissions:
            primaryButton("Next") {
                flow.moveNextOnboarding()
            }
            .disabled(isRequestingHealthPermission)
        case .ready:
            VStack(spacing: 10) {
                primaryButton("Start logging") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    finishOnboarding()
                }
                .disabled(isSubmitting)
                secondaryButton("Explore app") {
                    finishOnboarding()
                }
                .disabled(isSubmitting)
            }
        }
    }

    private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSubmitting {
                ProgressView()
                    .tint(.white)
                    .frame(width: 220, height: 60)
            } else {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.system(size: 16, weight: .bold))
                    if label != "Start logging" && label != "Start" {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 220, height: 60)
            }
        }
        .background(Color.black)
        .clipShape(Capsule())
        .disabled(isSubmitting || isAccountLoading)
    }

    private func secondaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
        }
        .disabled(isSubmitting || isAccountLoading)
    }

    private var canContinueCurrentScreen: Bool {
        switch flow.onboardingRoute {
        case .goal:
            return draft.goal != nil
        case .age:
            return draft.ageValue >= Double(OnboardingBaselineRange.age.lowerBound) &&
                draft.ageValue <= Double(OnboardingBaselineRange.age.upperBound)
        case .baseline:
            return draft.isBaselineValid
        case .activity:
            return draft.activity != nil
        case .pace:
            return draft.pace != nil
        case .goalValidation:
            return true
        case .socialProof:
            return true
        case .challenge:
            return draft.challenge != nil
        case .experience:
            return draft.experience != nil
        case .howItWorks:
            return true
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
        case .age:
            OnboardingValueCard(
                title: "Profile setup",
                bodyText: "We’ll use age with your height and weight to personalize calorie estimates."
            )
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
                timezone: TimeZone.current.identifier,
                age: Int(draft.ageValue.rounded()),
                sex: (draft.sex ?? .other).rawValue,
                heightCm: draft.heightInCm,
                weightKg: draft.weightInKg,
                pace: (draft.pace ?? .balanced).rawValue,
                activityDetail: draft.activity?.rawValue
            )

            // Retry up to 2 times for network/timeout failures (handles Render.com cold starts).
            // On the first transient failure, show a warm-up message and retry automatically.
            let maxAttempts = 2
            var lastError: Error?

            for attempt in 1...maxAttempts {
                do {
                    _ = try await appStore.apiClient.submitOnboarding(request)
                    OnboardingPersistence.save(draft: draft, route: flow.onboardingRoute, defaults: defaults)
                    appStore.setHealthSyncEnabled(draft.connectHealth)
                    appStore.markOnboardingComplete()
                    setScreenState(.ready, state: .default)
                    flow.showHome()
                    return
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

                    lastError = error
                    let isTransient = isTransientNetworkError(error)

                    if isTransient && attempt < maxAttempts {
                        // Show a friendly warm-up message and retry automatically
                        setScreenState(.ready, state: .loading, errorMessage: "Server is warming up, please wait…")
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s pause before retry
                        continue
                    }

                    // Non-retryable or final attempt — show the error
                    let message = readyScreenErrorMessage(for: error)
                    localError = nil
                    appStore.setError(message)
                    setScreenState(.ready, state: .error, errorMessage: message)
                    return
                }
            }
        }
    }

    /// Returns true for errors that are likely transient (timeout, no connection)
    /// and worth retrying automatically — typically Render.com cold-start delays.
    private func isTransientNetworkError(_ error: Error) -> Bool {
        if let apiError = error as? APIClientError, case .networkFailure = apiError {
            return true
        }
        let nsError = error as NSError
        let transientCodes: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorCannotConnectToHost
        ]
        return nsError.domain == NSURLErrorDomain && transientCodes.contains(nsError.code)
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

    private var readyScreenStatusMessage: String? {
        guard flow.onboardingRoute == .ready else {
            return nil
        }
        return currentScreenState.errorMessage
    }

    private func readyScreenErrorMessage(for error: Error) -> String {
        if let apiError = error as? APIClientError {
            switch apiError {
            case .networkFailure:
                return "Couldn't finish setup right now. Check your connection and try again."
            case let .server(statusCode, _):
                if statusCode >= 500 {
                    return "Couldn't finish setup right now. Server is unavailable. Try again."
                }
            default:
                break
            }
        }

        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func setScreenState(_ route: OnboardingRoute, state: OnboardingScreenLoadState, errorMessage: String? = nil) {
        screenStates[route] = OnboardingScreenState(loadState: state, errorMessage: errorMessage)
    }

    private func syncScreenStateHooks() {
        if canContinueCurrentScreen {
            if currentScreenState.loadState == .disabled {
                setScreenState(flow.onboardingRoute, state: .default)
            }
        } else if [.goal, .age, .baseline, .activity, .pace].contains(flow.onboardingRoute) {
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
        if restored.route == .preferencesOptional {
            flow.moveToOnboarding(.goalValidation)
        } else {
            flow.moveToOnboarding(restored.route)
        }
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

    private func syncBaselineStepForCurrentDraft() {
        // Always start at sex. The sub-step navigation (handleBaselineContinue/Back)
        // handles forward/backward within the baseline screen.
        // When coming back from activity, handleBaselineBack isn't called —
        // the route just changes to .baseline, so we check if we're coming backward.
    }

    /// Called when the onboarding route changes TO .baseline.
    /// Determines whether to show the first or last sub-step.
    private func syncBaselineStepOnRouteChange(previousRoute: OnboardingRoute?) {
        if previousRoute == .activity {
            // Coming BACK from activity → show the last sub-step
            baselineStep = .weight
        } else {
            // Coming FORWARD from age → start at the first sub-step
            baselineStep = .sex
        }
    }

    private func handleAgeContinue() {
        draft.ageValue = draft.ageValue
        draft.baselineTouchedAge = true
        flow.moveNextOnboarding()
    }

    private func handleBaselineBack() {
        switch baselineStep {
        case .sex:
            flow.moveBackOnboarding()
        case .height:
            baselineStep = .sex
        case .weight:
            baselineStep = .height
        }
    }

    private func handleBaselineContinue() {
        switch baselineStep {
        case .sex:
            guard draft.baselineTouchedSex, draft.sex != nil else { return }
            baselineStep = .height
        case .height:
            draft.baselineTouchedHeight = true
            baselineStep = .weight
        case .weight:
            draft.baselineTouchedWeight = true
            guard draft.isBaselineValid else { return }
            flow.moveNextOnboarding()
        }
    }
}

#Preview {
    OnboardingView(flow: AppFlowCoordinator())
        .environmentObject(AppStore())
}
