import SwiftUI
import Combine

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
    @State private var accountScreenAppeared = false
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
                    .transition(.obScreen)
                } else if flow.onboardingRoute == .goal {
                    goalRouteView
                        .transition(.obScreen)
                } else if flow.onboardingRoute == .age {
                    ageRouteView
                        .transition(.obScreen)
                } else if flow.onboardingRoute == .baseline {
                    baselineRouteView
                        .transition(.obScreen)
                } else if flow.onboardingRoute == .activity {
                    activityRouteView
                        .transition(.obScreen)
                } else if flow.onboardingRoute == .pace {
                    paceRouteView
                        .transition(.obScreen)
                } else if flow.onboardingRoute == .goalValidation {
                    goalValidationRouteView
                        .transition(.obScreen)
                } else if flow.onboardingRoute == .socialProof {
                    socialProofRouteView
                        .transition(.obScreen)
                } else if flow.onboardingRoute == .experience {
                    experienceRouteView
                        .transition(.obScreen)
                } else if flow.onboardingRoute == .howItWorks {
                    howItWorksRouteView
                        .transition(.obScreen)
                } else if flow.onboardingRoute == .challenge {
                    challengeRouteView
                        .transition(.obScreen)
                } else if flow.onboardingRoute == .challengeInsight {
                    challengeInsightRouteView
                        .transition(.obScreen)
                } else if flow.onboardingRoute == .ready {
                    readyRouteView
                        .transition(.obScreen)
                } else if flow.onboardingRoute == .account {
                    accountRouteView
                        .transition(.obScreen)
                } else if flow.onboardingRoute == .permissions {
                    permissionsRouteView
                        .transition(.obScreen)
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
                    .transition(.obScreen)
                }
            }
            .animation(.easeOut(duration: 0.38), value: flow.onboardingRoute)
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

    private var permissionsRouteView: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                // Headline
                Text("Optional permissions")
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 34))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .padding(.top, 32)

                Text("Health and reminders can be enabled now or later in Settings.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.51, green: 0.51, blue: 0.51))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 24)

                Spacer()

                OB09PermissionsScreen(
                    connectHealth: $draft.connectHealth,
                    enableNotifications: $draft.enableNotifications,
                    isRequestingHealthPermission: isRequestingHealthPermission,
                    healthPermissionMessage: healthPermissionMessage,
                    onConnectHealth: requestHealthAccess,
                    onDisconnectHealth: disconnectHealthAccess
                )
                .padding(.horizontal, 20)

                Spacer()

                // Center-aligned Next button
                primaryButton("Next") {
                    flow.moveNextOnboarding()
                }
                .disabled(isRequestingHealthPermission)
                .padding(.bottom, 24)
            }
        }
    }

    private var accountRouteView: some View {
        ZStack {
            OnboardingAnimatedBackground()

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

                // Headline
                VStack(spacing: 8) {
                    Text("Almost \(Text("there").font(OnboardingTypography.instrumentSerif(style: .italic, size: 38)))")
                        .font(OnboardingTypography.instrumentSerif(style: .regular, size: 38))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.center)

                    Text("Save your progress to unlock\nyour personalized plan.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(OnboardingGlassTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 14)
                .padding(.horizontal, 24)
                .opacity(accountScreenAppeared ? 1 : 0)
                .offset(y: accountScreenAppeared ? 0 : 16)
                .animation(.easeOut(duration: 0.5).delay(0.08), value: accountScreenAppeared)

                // Auto-rotating carousel
                AccountCarouselView()
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                    .opacity(accountScreenAppeared ? 1 : 0)
                    .offset(y: accountScreenAppeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.55).delay(0.14), value: accountScreenAppeared)

                // Feature benefits card
                accountBenefitsCard
                    .padding(.top, 16)
                    .padding(.horizontal, 24)

                Spacer(minLength: 12)

                // Bottom: social proof + sign-in buttons
                VStack(spacing: 12) {
                    accountSocialProofBadge
                        .opacity(accountScreenAppeared ? 1 : 0)
                        .offset(y: accountScreenAppeared ? 0 : 12)
                        .animation(.easeOut(duration: 0.45).delay(0.5), value: accountScreenAppeared)

                    OB08AccountScreen(
                        isLoading: isAccountLoading,
                        prefersGooglePrimary: isSupabaseAuthMode,
                        enableApple: true,
                        onSelectProvider: continueAccount(provider:)
                    )

                    if let localError {
                        Text(localError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            accountScreenAppeared = true
        }
        .onDisappear {
            accountScreenAppeared = false
        }
    }

    private var accountSocialProofBadge: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(OnboardingGlassTheme.accentStart)
                }
            }
            Rectangle()
                .fill(OnboardingGlassTheme.panelStroke)
                .frame(width: 1, height: 14)
            Text("5,000+ people eating smarter")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .onboardingGlassPanel(cornerRadius: 14, fillOpacity: 0.06, strokeOpacity: 0.14)
    }

    private var accountBenefitsCard: some View {
        VStack(spacing: 0) {
            accountBenefitRow(
                icon: "wand.and.stars",
                title: "AI-powered logging",
                subtitle: "Snap, scan, or speak — tracked instantly",
                delay: 0.22
            )
            accountCardDivider(delay: 0.32)
            accountBenefitRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Progress that adapts",
                subtitle: "Your plan updates as your results do",
                delay: 0.34
            )
            accountCardDivider(delay: 0.44)
            accountBenefitRow(
                icon: "lock.shield.fill",
                title: "Private & secure",
                subtitle: "Your data is encrypted and only yours",
                delay: 0.46
            )
        }
        .padding(.vertical, 6)
        // Rich layered glass background
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                // Accent colour wash — gold top-left, teal bottom-right
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: OnboardingGlassTheme.accentStart.opacity(0.09), location: 0),
                                .init(color: Color.clear, location: 0.5),
                                .init(color: OnboardingGlassTheme.accentEnd.opacity(0.06), location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                // Top-edge inner highlight for depth
                VStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.22), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(height: 48)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .allowsHitTesting(false)
            }
        )
        // Gradient border: accent colours fade to neutral
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: OnboardingGlassTheme.accentStart.opacity(0.65), location: 0),
                            .init(color: OnboardingGlassTheme.accentEnd.opacity(0.40), location: 0.45),
                            .init(color: OnboardingGlassTheme.panelStroke.opacity(0.55), location: 0.75),
                            .init(color: OnboardingGlassTheme.panelStroke.opacity(0.20), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        // Layered shadows: accent glow + depth
        .shadow(color: OnboardingGlassTheme.accentStart.opacity(0.18), radius: 20, y: 6)
        .shadow(color: Color.black.opacity(0.10), radius: 8, y: 3)
        .opacity(accountScreenAppeared ? 1 : 0)
        .scaleEffect(accountScreenAppeared ? 1 : 0.96)
        .animation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.18), value: accountScreenAppeared)
    }

    private func accountCardDivider(delay: Double) -> some View {
        // Gradient separator: accent tint fades to transparent at edges
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: 0),
                        .init(color: OnboardingGlassTheme.accentStart.opacity(0.25), location: 0.3),
                        .init(color: OnboardingGlassTheme.accentEnd.opacity(0.20), location: 0.7),
                        .init(color: Color.clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.leading, 54)
            .opacity(accountScreenAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(delay), value: accountScreenAppeared)
    }

    private func accountBenefitRow(icon: String, title: String, subtitle: String, delay: Double) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                OnboardingGlassTheme.accentStart.opacity(0.22),
                                OnboardingGlassTheme.accentEnd.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                OnboardingGlassTheme.accentStart.opacity(0.35),
                                OnboardingGlassTheme.accentEnd.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [OnboardingGlassTheme.accentStart, OnboardingGlassTheme.accentEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(OnboardingGlassTheme.textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .opacity(accountScreenAppeared ? 1 : 0)
        .offset(x: accountScreenAppeared ? 0 : -14)
        .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(delay), value: accountScreenAppeared)
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

// MARK: - Screen Transition

private extension AnyTransition {
    /// Consistent enter/exit transition applied to every onboarding screen.
    /// Enter: fade in + slide up 22pt.  Exit: fade out only (no slide, avoids clash with entering screen).
    static var obScreen: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 22)),
            removal:   .opacity
        )
    }
}

// MARK: - Account Screen Carousel

private struct AccountCarouselView: View {
    @State private var currentIndex = 0

    private let slides: [CarouselSlideData] = [
        CarouselSlideData(
            gradientColors: [
                Color(red: 1.00, green: 0.78, blue: 0.33),
                Color(red: 0.97, green: 0.50, blue: 0.20)
            ],
            icon: "fork.knife.circle.fill",
            headline: "Log meals in seconds",
            subline: "Snap a photo, say it aloud, or just type it"
        ),
        CarouselSlideData(
            gradientColors: [
                Color(red: 0.21, green: 0.86, blue: 0.73),
                Color(red: 0.10, green: 0.58, blue: 0.82)
            ],
            icon: "chart.bar.fill",
            headline: "Watch your progress",
            subline: "Your nutrition story, day by day"
        ),
        CarouselSlideData(
            gradientColors: [
                Color(red: 0.62, green: 0.38, blue: 0.98),
                Color(red: 0.94, green: 0.36, blue: 0.76)
            ],
            icon: "sparkles",
            headline: "AI that gets you",
            subline: "Smarter, more personal every day"
        )
    ]

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $currentIndex) {
                ForEach(slides.indices, id: \.self) { i in
                    CarouselCard(slide: slides[i])
                        .tag(i)
                        .padding(.horizontal, 2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 190)

            // Dot indicators
            HStack(spacing: 6) {
                ForEach(slides.indices, id: \.self) { i in
                    Capsule()
                        .fill(
                            i == currentIndex
                                ? OnboardingGlassTheme.textPrimary
                                : OnboardingGlassTheme.textMuted.opacity(0.35)
                        )
                        .frame(width: i == currentIndex ? 20 : 6, height: 6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentIndex)
                }
            }
        }
        .onReceive(
            Timer.publish(every: 3.2, on: .main, in: .common).autoconnect()
        ) { _ in
            withAnimation(.easeInOut(duration: 0.65)) {
                currentIndex = (currentIndex + 1) % slides.count
            }
        }
    }
}

private struct CarouselSlideData {
    let gradientColors: [Color]
    let icon: String
    let headline: String
    let subline: String
}

private struct CarouselCard: View {
    let slide: CarouselSlideData

    var body: some View {
        ZStack {
            // Gradient background
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: slide.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Subtle inner highlight
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

            // Content
            VStack(spacing: 14) {
                Image(systemName: slide.icon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

                VStack(spacing: 5) {
                    Text(slide.headline)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Text(slide.subline)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: slide.gradientColors.first?.opacity(0.35) ?? .clear, radius: 16, y: 6)
    }
}

#Preview {
    OnboardingView(flow: AppFlowCoordinator())
        .environmentObject(AppStore())
}
