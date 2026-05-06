import SwiftUI
import Combine

struct OnboardingView: View {
    @EnvironmentObject var appStore: AppStore
    @ObservedObject var flow: AppFlowCoordinator
    @Environment(\.colorScheme) var colorScheme

    @State var draft = OnboardingDraft()
    @State var localError: String?
    @State var isSubmitting = false
    @State var isAccountLoading = false
    @State var isRequestingHealthPermission = false
    @State var healthPermissionMessage: String?
    @State var notificationStatusMessage: String?
    @State var hasRestored = false
    @State var pendingRouteError: String?
    @State var baselineStep: BaselineScreenStep = .sex
    @State var accountScreenAppeared = false
    @State var screenStates: [OnboardingRoute: OnboardingScreenState] = {
        OnboardingRoute.allCases.reduce(into: [OnboardingRoute: OnboardingScreenState]()) { result, route in
            result[route] = OnboardingScreenState()
        }
    }()

    private let totalProgressSteps = 6
    let defaults = UserDefaults.standard

    var metrics: OnboardingMetrics {
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
                } else if flow.onboardingRoute == .preferencesOptional {
                    preferencesOptionalRouteView
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
                } else if flow.onboardingRoute == .notificationsPermission {
                    notificationsPermissionRouteView
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
                                appStore.signOut()
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
            Task { await autoAdvancePermissionRouteIfNeeded() }
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
            Task { await autoAdvancePermissionRouteIfNeeded() }
        }
    }

    var currentScreenState: OnboardingScreenState {
        screenStates[flow.onboardingRoute] ?? OnboardingScreenState()
    }

    private var shouldHideNavigationBar: Bool {
        true
    }

}

// MARK: - Account Screen Carousel
//
// `AccountCarouselView` and its supporting types (`CarouselSlideData`,
// `CarouselCard`) were removed on 2026-04-26 as part of the OB08 Account
// screen redesign. The auto-rotating hero card was decorative-only motion
// and contributed to the screen feeling overloaded at the conversion moment.
// The 3 feature claims (logging / progress / privacy) are now expressed
// solely in `accountBenefitsCard`. If a hero block is reintroduced in
// future, prefer a static one over an auto-rotating carousel.

#Preview {
    OnboardingView(flow: AppFlowCoordinator())
        .environmentObject(AppStore())
}
