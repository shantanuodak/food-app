import Foundation
import SwiftUI

extension OnboardingView {
    func continueAccount(provider: AccountProvider) {
        guard !isAccountLoading else { return }
        draft.accountProvider = provider
        localError = nil
        isAccountLoading = true
        setScreenState(.account, state: .loading)

        // V3.1 Phase 5.1 (2026-05-21): capture sign-up vs sign-in intent so
        // we know how to route after the status check. Both paths now call
        // the status endpoint — sign-in just routes straight to home if a
        // profile exists, sign-up shows the confirmation screen.
        let isSigningUp = !isExistingAccountSignIn

        Task {
            do {
                _ = try await appStore.authService.signIn(with: provider)
                await appStore.flushAuthDiagnostics()

                // V3.1 Phase 5.1 (2026-05-21): ALWAYS check status after
                // OAuth, regardless of sign-up vs sign-in path. The
                // previous code skipped the check for the sign-in path
                // assuming the user "expects" to land on home — but
                // sign-in still continued through onboarding screens and
                // ended in submitOnboarding clobbering the existing
                // profile. (Tanmay's incident 2026-05-21 13:52 UTC.)
                //
                // Routing:
                //   - sign-in + has profile → mark complete, show home
                //   - sign-up + has profile → show ExistingAccountDetectedView
                //   - either + no profile  → continue onboarding screens
                //
                // Errors are NO LONGER swallowed. If the status check
                // fails (Render cold-start timeout, 5xx, network), we
                // surface the error and let the user retry rather than
                // silently falling through and risking a profile wipe.
                let status: OnboardingStatusResponse
                do {
                    status = try await appStore.apiClient.fetchOnboardingStatus()
                } catch {
                    NSLog("[OnboardingView] fetchOnboardingStatus failed: %@", String(describing: error))
                    let message = "Couldn't verify your account just now. Check your connection and try again."
                    await MainActor.run {
                        isAccountLoading = false
                        localError = message
                        setScreenState(.account, state: .error, errorMessage: message)
                    }
                    return
                }

                if status.hasCompletedOnboarding {
                    await MainActor.run {
                        isAccountLoading = false
                        setScreenState(.account, state: .default)
                        if isSigningUp {
                            // Sign-up path → surface the confirmation
                            // screen so the user explicitly picks
                            // continue-existing vs overwrite.
                            existingAccountStatus = status
                        } else {
                            // Sign-in path → user already knows they have
                            // an account, land them on home directly.
                            resumeExistingAccountSession()
                        }
                    }
                    return
                }

                if !isSigningUp {
                    await MainActor.run {
                        let message = "We couldn't find an existing account for this sign-in. Tap Create an account to set up your targets first."
                        appStore.signOut()
                        draft.accountProvider = nil
                        isAccountLoading = false
                        localError = message
                        setScreenState(.account, state: .error, errorMessage: message)
                    }
                    return
                }

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

    func finishOnboarding() {
        Task {
            isSubmitting = true
            localError = nil
            appStore.setError(nil)
            setScreenState(.ready, state: .loading)
            defer { isSubmitting = false }

            if let missingRoute = firstMissingRequiredSetupRoute {
                let message = "Please finish setup before creating your account."
                pendingRouteError = message
                appStore.setError(message)
                setScreenState(.ready, state: .error, errorMessage: message)
                setScreenState(missingRoute, state: .error, errorMessage: message)
                flow.moveToOnboarding(missingRoute)
                return
            }

            let request = OnboardingRequest(
                goal: draft.goal ?? .maintain,
                dietPreference: dietPreferencePayload,
                allergies: draft.allergies.map(\.rawValue).sorted(),
                units: draft.units ?? .imperial,
                activityLevel: draft.activity?.apiValue ?? .moderate,
                timezone: TimeZone.current.identifier,
                age: Int(draft.ageValue.rounded()),
                sex: (draft.sex ?? .other).rawValue,
                heightCm: draft.heightInCm,
                weightKg: draft.weightInKg,
                pace: (draft.pace ?? .balanced).rawValue,
                activityDetail: draft.activity?.rawValue,
                // V3.1 Phase 5.1 (2026-05-21): pass overwriteExisting only
                // when the user explicitly tapped "Update my profile with
                // new info" on ExistingAccountDetectedView. Otherwise the
                // backend's 409 safety net will fire if a profile already
                // exists, and the catch block below routes the user to
                // the confirmation screen.
                overwriteExisting: userConfirmedProfileOverwrite
            )

            // Retry up to 2 times for network/timeout failures, mostly Render cold starts.
            let maxAttempts = 2

            for attempt in 1...maxAttempts {
                do {
                    let response = try await appStore.apiClient.submitOnboarding(request)
                    draft.savedCalorieTarget = response.calorieTarget
                    draft.savedMacroTargets = response.macroTargets
                    OnboardingPersistence.save(draft: draft, route: flow.onboardingRoute, defaults: defaults)
                    appStore.setHealthSyncEnabled(draft.connectHealth)
                    appStore.setSelectedChallenge(draft.challenge)
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

                    // V3.1 Phase 5.1 (2026-05-21): backend 409 means an
                    // onboarding profile already exists and we didn't
                    // pass overwriteExisting=true. This is the safety net
                    // firing. Surface the ExistingAccountDetectedView so
                    // the user explicitly picks continue-existing vs
                    // overwrite. This catches the case where both iOS
                    // gates (continueAccount status check + sign-in
                    // routing) somehow fail and we get to submit anyway.
                    if case let APIClientError.server(statusCode, _) = error, statusCode == 409 {
                        do {
                            let status = try await appStore.apiClient.fetchOnboardingStatus()
                            await MainActor.run {
                                setScreenState(.ready, state: .default)
                                existingAccountStatus = status
                                flow.moveToOnboarding(.account)
                            }
                        } catch {
                            // If even the status fetch fails, fall back
                            // to a generic error so the user can retry.
                            let message = "Account already exists. Please sign out and sign in again."
                            appStore.setError(message)
                            setScreenState(.ready, state: .error, errorMessage: message)
                        }
                        return
                    }

                    let isTransient = isTransientNetworkError(error)

                    if isTransient && attempt < maxAttempts {
                        setScreenState(.ready, state: .loading, errorMessage: "Server is warming up, please wait…")
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        continue
                    }

                    let message = readyScreenErrorMessage(for: error)
                    localError = nil
                    appStore.setError(message)
                    setScreenState(.ready, state: .error, errorMessage: message)
                    return
                }
            }
        }
    }

    var dietPreferencePayload: String {
        if draft.preferences.isEmpty || draft.preferences.contains(.noPreference) {
            return "no_preference"
        }
        return draft.preferences
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
    }

    var firstMissingRequiredSetupRoute: OnboardingRoute? {
        if draft.goal == nil {
            return .goal
        }
        if draft.challenge == nil {
            return .challenge
        }
        if !draft.hasBaselineValues {
            return .baseline
        }
        if draft.activity == nil {
            return .activity
        }
        if draft.pace == nil {
            return .pace
        }
        return nil
    }

    var readyScreenStatusMessage: String? {
        guard flow.onboardingRoute == .ready else {
            return nil
        }
        return currentScreenState.errorMessage
    }

    func setScreenState(_ route: OnboardingRoute, state: OnboardingScreenLoadState, errorMessage: String? = nil) {
        screenStates[route] = OnboardingScreenState(loadState: state, errorMessage: errorMessage)
    }

    func syncScreenStateHooks() {
        if canContinueCurrentScreen {
            if currentScreenState.loadState == .disabled {
                setScreenState(flow.onboardingRoute, state: .default)
            }
        } else if [.goal, .age, .baseline, .activity, .pace].contains(flow.onboardingRoute) {
            setScreenState(flow.onboardingRoute, state: .disabled)
        }
    }

    func persistDraft() {
        OnboardingPersistence.save(draft: draft, route: flow.onboardingRoute, defaults: defaults)
    }

    func restorePersistedContextIfNeeded() {
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
        // preferencesOptional is now active, so saved drafts on that screen restore normally.
        flow.moveToOnboarding(restored.route)
    }

    /// Returns true for errors that are likely transient and worth retrying automatically.
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
}
