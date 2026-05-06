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

    // MARK: - Account Route (OB08) — Quiet Wellness redesign
    //
    // Pilot of the new onboarding visual direction. Static neutral background
    // (no animated gradient), single amber accent (no gradient pairs), flat
    // hairline-bordered card and buttons. Rest of onboarding still uses the
    // OnboardingGlassTheme glass language; see docs/UI_COMPONENTS.md →
    // "Onboarding refresh — in progress".

    var accountRouteView: some View {
        ZStack {
            OnboardingGlassTheme.neutralBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Back button — neutral surface circle with hairline border
                HStack {
                    Button {
                        flow.moveBackOnboarding()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(OnboardingGlassTheme.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(OnboardingGlassTheme.neutralSurface)
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(OnboardingGlassTheme.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Back"))
                    .disabled(isSubmitting || isAccountLoading)
                    Spacer()
                }
                .frame(height: 44)
                .padding(.top, 12)
                .padding(.horizontal, 24)

                // Hero — headline + completed subtitle. Larger title now that
                // the carousel no longer competes for vertical space.
                VStack(spacing: 12) {
                    Text("Almost \(Text("there").font(OnboardingTypography.instrumentSerif(style: .italic, size: 36)))")
                        .font(OnboardingTypography.instrumentSerif(style: .regular, size: 36))
                        .foregroundStyle(OnboardingGlassTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(L10n.onboardingAccountSubtitle)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(OnboardingGlassTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.top, 32)
                .padding(.horizontal, 24)
                .opacity(accountScreenAppeared ? 1 : 0)
                .offset(y: accountScreenAppeared ? 0 : 12)
                .animation(.easeOut(duration: 0.5).delay(0.05), value: accountScreenAppeared)

                // Feature card — biggest pause on the screen sits above this
                // (48 pt), establishing the headline as the hero.
                accountBenefitsCard
                    .padding(.top, 48)
                    .padding(.horizontal, 24)

                Spacer(minLength: 24)

                // Bottom group — ratings + sign-in buttons + error message.
                VStack(spacing: 24) {
                    accountSocialProofBadge
                        .opacity(accountScreenAppeared ? 1 : 0)
                        .offset(y: accountScreenAppeared ? 0 : 8)
                        .animation(.easeOut(duration: 0.45).delay(0.18), value: accountScreenAppeared)

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

    var accountSocialProofBadge: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(OnboardingGlassTheme.accentAmber)
                }
            }
            Rectangle()
                .fill(OnboardingGlassTheme.hairline)
                .frame(width: 1, height: 14)
            Text(L10n.onboardingAccountSocialProof)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Five-star rated, \(L10n.onboardingAccountSocialProof)"))
    }

    var accountBenefitsCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            accountBenefitRow(
                icon: "wand.and.stars",
                title: L10n.onboardingAccountFeatureLoggingTitle,
                subtitle: L10n.onboardingAccountFeatureLoggingSubtitle,
                delay: 0.10
            )
            accountBenefitRow(
                icon: "chart.line.uptrend.xyaxis",
                title: L10n.onboardingAccountFeatureProgressTitle,
                subtitle: L10n.onboardingAccountFeatureProgressSubtitle,
                delay: 0.14
            )
            accountBenefitRow(
                icon: "lock.shield.fill",
                title: L10n.onboardingAccountFeatureSecureTitle,
                subtitle: L10n.onboardingAccountFeatureSecureSubtitle,
                delay: 0.18
            )
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(OnboardingGlassTheme.neutralSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(OnboardingGlassTheme.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 24, y: 4)
        .opacity(accountScreenAppeared ? 1 : 0)
        .offset(y: accountScreenAppeared ? 0 : 12)
        .animation(.easeOut(duration: 0.5).delay(0.12), value: accountScreenAppeared)
    }

    func accountBenefitRow(icon: String, title: String, subtitle: String, delay: Double) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(OnboardingGlassTheme.accentAmber)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .opacity(accountScreenAppeared ? 1 : 0)
        .offset(x: accountScreenAppeared ? 0 : -8)
        .animation(.easeOut(duration: 0.45).delay(delay), value: accountScreenAppeared)
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
                SlideToConfirmButton(label: "Start logging") {
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
            SlideToConfirmButton(label: "Start logging") {
                finishOnboarding()
            }
            .disabled(isSubmitting)
        }
    }

    func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
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
