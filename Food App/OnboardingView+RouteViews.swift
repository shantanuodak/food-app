import SwiftUI

extension OnboardingView {
    var goalRouteView: some View {
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
                    .foregroundStyle(OnboardingGlassTheme.ctaForeground)
                    .frame(width: 220, height: 60)
                    .background(OnboardingGlassTheme.ctaBackground.opacity(canContinue ? 1 : 0.2))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canContinue)
                .animation(.easeInOut(duration: 0.25), value: canContinue)
                .padding(.bottom, 24)
            }
        }
    }

    var activityRouteView: some View {
        OB04ActivityScreen(
            selectedActivity: $draft.activity,
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    var ageRouteView: some View {
        OB03AgeScreen(
            age: $draft.ageValue,
            onBack: { flow.moveBackOnboarding() },
            onContinue: handleAgeContinue
        )
    }

    var baselineRouteView: some View {
        OB03BaselineScreen(
            draft: $draft,
            step: $baselineStep,
            onBack: handleBaselineBack,
            onContinue: handleBaselineContinue
        )
    }

    var paceRouteView: some View {
        OB05PaceScreen(
            draft: $draft,
            selectedPace: $draft.pace,
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    var preferencesOptionalRouteView: some View {
        OB06PreferencesOptionalScreen(
            preferences: $draft.preferences,
            allergies: $draft.allergies,
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    var howItWorksRouteView: some View {
        OB02eHowItWorksScreen(
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    var experienceRouteView: some View {
        OB02dExperienceScreen(
            selectedExperience: $draft.experience,
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    var challengeRouteView: some View {
        OB02cChallengeScreen(
            selectedChallenge: $draft.challenge,
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    var challengeInsightRouteView: some View {
        OB02cChallengeInsightScreen(
            challenge: draft.challenge ?? .portionControl,
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    var permissionsRouteView: some View {
        OB09PermissionsScreen(
            connectHealth: $draft.connectHealth,
            isRequestingHealthPermission: isRequestingHealthPermission,
            healthPermissionMessage: healthPermissionMessage,
            onConnectHealth: requestHealthAccess,
            onDisconnectHealth: disconnectHealthAccess,
            onSkip: { flow.moveNextOnboarding() },
            onContinue: { flow.moveNextOnboarding() },
            onBack: { flow.moveBackOnboarding() }
        )
    }

    var notificationsPermissionRouteView: some View {
        OB09bNotificationsPermissionScreen(
            enableNotifications: $draft.enableNotifications,
            onEnableNotifications: requestNotificationAccess,
            notificationStatusMessage: notificationStatusMessage,
            onContinue: { flow.moveNextOnboarding() },
            onBack: { flow.moveBackOnboarding() }
        )
    }

    var accountRouteView: some View {
        ZStack {
            AccountLiquidGlassBackground()

            VStack(spacing: 0) {
                if !isExistingAccountSignIn {
                    HStack {
                        Button {
                            flow.moveBackOnboarding()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AccountRoutePalette.ink)
                                .frame(width: 44, height: 44)
                                .background(AccountRoutePalette.controlFill, in: Circle())
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(AccountRoutePalette.controlStroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Back"))
                        .disabled(isSubmitting || isAccountLoading)
                        Spacer()
                        Text("Final step")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AccountRoutePalette.secondaryInk)
                            .textCase(.uppercase)
                            .tracking(1.0)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(AccountRoutePalette.controlFill, in: Capsule())
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(AccountRoutePalette.controlStroke, lineWidth: 1))
                    }
                    .frame(height: 44)
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
                } else {
                    Color.clear
                        .frame(height: 44)
                        .padding(.top, 12)
                }

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.orange.opacity(0.92))
                            .frame(width: 8, height: 8)
                            .shadow(color: Color.orange.opacity(0.35), radius: 8)
                        Text(L10n.onboardingAccountBadge)
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(AccountRoutePalette.accentInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AccountRoutePalette.badgeFill, in: Capsule())
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(AccountRoutePalette.badgeStroke, lineWidth: 1))

                    Text("Connect to \(Text("keep going").font(OnboardingTypography.instrumentSerif(style: .italic, size: 42)))")
                        .font(OnboardingTypography.instrumentSerif(style: .regular, size: 42))
                        .foregroundStyle(AccountRoutePalette.ink)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(.top, 32)
                .padding(.horizontal, 24)
                .opacity(accountScreenAppeared ? 1 : 0)
                .offset(y: accountScreenAppeared ? 0 : 12)
                .animation(.easeOut(duration: 0.5).delay(0.05), value: accountScreenAppeared)

                AccountPreviewGlassStack(appeared: accountScreenAppeared)
                    .padding(.top, 36)
                    .padding(.horizontal, 24)

                Spacer(minLength: 24)

                VStack(spacing: 24) {
                    OB08AccountScreen(
                        isLoading: isAccountLoading,
                        prefersGooglePrimary: isSupabaseAuthMode,
                        enableApple: true,
                        onSelectProvider: continueAccount(provider:),
                        createAccountTitle: isExistingAccountSignIn ? "Create an account" : nil,
                        onCreateAccount: isExistingAccountSignIn ? {
                            isExistingAccountSignIn = false
                            localError = nil
                            flow.moveToOnboarding(.goal)
                        } : nil
                    )

                    if let localError {
                        Text(localError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
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

    var readyRouteView: some View {
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

                // Slide-to-confirm CTA. The drag gesture replaces the previous
                // tap button so the final onboarding submission requires a
                // small deliberate motion. "Explore app" was removed: the
                // Ready screen now has a single, intentional commit path.
                SlideToConfirmButton(label: "Start logging", isProcessing: isSubmitting) {
                    finishOnboarding()
                }
                .disabled(isSubmitting)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    var socialProofRouteView: some View {
        OB02bSocialProofScreen(
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() }
        )
    }

    var goalValidationRouteView: some View {
        OB05bGoalValidationScreen(
            draft: draft,
            metrics: metrics,
            onBack: { flow.moveBackOnboarding() },
            onContinue: { flow.moveNextOnboarding() },
            onAdjustPlan: { flow.moveToOnboarding(.goal) }
        )
    }

    var goalTopBar: some View {
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

    var activityTopBar: some View {
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

    var headerBlock: some View {
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
    var bodyBlock: some View {
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
            // Now rendered by `preferencesOptionalRouteView` (self-contained
            // screen). Kept here to satisfy the exhaustive switch.
            EmptyView()
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
                isRequestingHealthPermission: isRequestingHealthPermission,
                healthPermissionMessage: healthPermissionMessage,
                onConnectHealth: requestHealthAccess,
                onDisconnectHealth: disconnectHealthAccess,
                onSkip: { flow.moveNextOnboarding() },
                onContinue: { flow.moveNextOnboarding() },
                onBack: { flow.moveBackOnboarding() }
            )
        case .notificationsPermission:
            OB09bNotificationsPermissionScreen(
                enableNotifications: $draft.enableNotifications,
                onEnableNotifications: requestNotificationAccess,
                notificationStatusMessage: notificationStatusMessage,
                onContinue: { flow.moveNextOnboarding() },
                onBack: { flow.moveBackOnboarding() }
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
    var actionBlock: some View {
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
            // Self-contained screen renders its own centered Next button;
            // no skip button per design.
            EmptyView()
        case .planPreview:
            EmptyView()
        case .account:
            EmptyView()
        case .permissions:
            primaryButton("Next") {
                flow.moveNextOnboarding()
            }
            .disabled(isRequestingHealthPermission)
        case .notificationsPermission:
            primaryButton("Next") {
                flow.moveNextOnboarding()
            }
        case .ready:
            // Fallback path (not normally reached — `.ready` is handled
            // directly by `readyRouteView`). Mirrors the same single-CTA
            // slide-to-confirm so behaviour is consistent if this branch
            // is ever exercised by future routing changes.
            SlideToConfirmButton(label: "Start logging", isProcessing: isSubmitting) {
                finishOnboarding()
            }
            .disabled(isSubmitting)
        }
    }

    func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSubmitting {
                ProgressView()
                    .tint(OnboardingGlassTheme.ctaForeground)
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
                .foregroundStyle(OnboardingGlassTheme.ctaForeground)
                .frame(width: 220, height: 60)
            }
        }
        .background(OnboardingGlassTheme.ctaBackground)
        .clipShape(Capsule())
        .disabled(isSubmitting || isAccountLoading)
    }

    func secondaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
        }
        .disabled(isSubmitting || isAccountLoading)
    }

    var canContinueCurrentScreen: Bool {
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

    var selectedPreferenceTitles: String {
        draft.preferences
            .filter { $0 != .noPreference }
            .map(\.title)
            .sorted()
            .joined(separator: ", ")
    }

    var isSupabaseAuthMode: Bool {
        guard appStore.configuration.supabaseURL != nil else { return false }
        let anon = appStore.configuration.supabaseAnonKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        return !(anon?.isEmpty ?? true)
    }

    @ViewBuilder
    var valuePropositionBlock: some View {
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
            // No value-card; the redesigned self-contained screen owns its
            // own visual feedback (filled pills + checkmark).
            EmptyView()
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

}

private struct AccountLiquidGlassBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AccountRoutePalette.backgroundTop,
                    AccountRoutePalette.backgroundBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    AccountRoutePalette.backgroundSheen,
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )

            LinearGradient(
                colors: [
                    .clear,
                    AccountRoutePalette.backgroundDepth
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum AccountRoutePalette {
    static let ink = adaptiveColor(
        light: UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0),
        dark: UIColor(white: 0.96, alpha: 1.0)
    )
    static let secondaryInk = adaptiveColor(
        light: UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 0.76),
        dark: UIColor(white: 0.92, alpha: 0.74)
    )
    static let accentInk = adaptiveColor(
        light: UIColor(red: 0.86, green: 0.42, blue: 0.12, alpha: 1.0),
        dark: UIColor(red: 0.98, green: 0.71, blue: 0.42, alpha: 1.0)
    )
    static let backgroundTop = adaptiveColor(
        light: UIColor.white,
        dark: UIColor(red: 0.07, green: 0.06, blue: 0.05, alpha: 1.0)
    )
    static let backgroundBottom = adaptiveColor(
        light: UIColor.white,
        dark: UIColor(red: 0.11, green: 0.09, blue: 0.08, alpha: 1.0)
    )
    static let backgroundSheen = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.0),
        dark: UIColor(white: 1.0, alpha: 0.05)
    )
    static let backgroundDepth = adaptiveColor(
        light: UIColor.black.withAlphaComponent(0.025),
        dark: UIColor.black.withAlphaComponent(0.26)
    )
    static let controlFill = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.86),
        dark: UIColor(white: 1.0, alpha: 0.10)
    )
    static let controlStroke = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.07),
        dark: UIColor(white: 1.0, alpha: 0.16)
    )
    static let badgeFill = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.84),
        dark: UIColor(white: 1.0, alpha: 0.10)
    )
    static let badgeStroke = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.06),
        dark: UIColor(white: 1.0, alpha: 0.18)
    )
    static let cardFront = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.78),
        dark: UIColor(red: 0.18, green: 0.15, blue: 0.13, alpha: 0.86)
    )
    static let cardStrokeStrong = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.07),
        dark: UIColor(white: 1.0, alpha: 0.14)
    )
    static let lineTrack = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.08),
        dark: UIColor(white: 1.0, alpha: 0.12)
    )
    static let lineActive = adaptiveColor(
        light: UIColor(red: 0.91, green: 0.43, blue: 0.13, alpha: 1.0),
        dark: UIColor(red: 1.0, green: 0.74, blue: 0.45, alpha: 1.0)
    )
    static let pillFill = adaptiveColor(
        light: UIColor(white: 0.96, alpha: 0.80),
        dark: UIColor(white: 1.0, alpha: 0.08)
    )
    static let pillStroke = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.06),
        dark: UIColor(white: 1.0, alpha: 0.12)
    )
    static let shine = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.56),
        dark: UIColor(white: 1.0, alpha: 0.12)
    )
    static let textBubbleFill = adaptiveColor(
        light: UIColor(white: 0.96, alpha: 0.92),
        dark: UIColor(white: 1.0, alpha: 0.08)
    )
    static let textBubbleStroke = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.06),
        dark: UIColor(white: 1.0, alpha: 0.14)
    )
    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

private struct AccountPreviewGlassStack: View {
    let appeared: Bool

    private let previewText = "2 eggs, toast, iced coffee"

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("AI text", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AccountRoutePalette.ink)
                    Spacer()
                    Circle()
                        .fill(Color.orange.opacity(0.78))
                        .frame(width: 7, height: 7)
                        .shadow(color: Color.orange.opacity(0.22), radius: 5)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AccountRoutePalette.textBubbleFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(AccountRoutePalette.textBubbleStroke, lineWidth: 1)
                            )
                            .frame(width: 34, height: 34)
                            .overlay(
                                Text("AI")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AccountRoutePalette.accentInk)
                            )

                        VStack(alignment: .leading, spacing: 8) {
                            Text(previewText)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AccountRoutePalette.ink)
                                .opacity(0.96)
                                .lineLimit(1)

                            previewLine(width: 0.78)
                                .frame(height: 8)
                        }
                    }

                    previewResultStrip
                }
                .padding(.top, 17)

            }
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 146)
            .background(AccountRoutePalette.cardFront)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(AccountRoutePalette.cardStrokeStrong, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.11), radius: 22, y: 14)
        }
        .frame(height: 184)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .scaleEffect(appeared ? 1 : 0.985)
        .animation(.easeOut(duration: 0.48).delay(0.14), value: appeared)
    }

    private func previewLine(width: CGFloat) -> some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AccountRoutePalette.lineTrack)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.68),
                                AccountRoutePalette.lineActive.opacity(0.92)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: totalWidth * width)
            }
        }
        .frame(height: 8)
    }

    private var previewResultStrip: some View {
        HStack(spacing: 10) {
            Text("512 kcal")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AccountRoutePalette.accentInk)

            Rectangle()
                .fill(AccountRoutePalette.pillStroke)
                .frame(width: 1, height: 12)

            Text("24g protein")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AccountRoutePalette.secondaryInk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AccountRoutePalette.pillFill, in: Capsule())
        .overlay(Capsule().strokeBorder(AccountRoutePalette.pillStroke, lineWidth: 1))
    }
}
