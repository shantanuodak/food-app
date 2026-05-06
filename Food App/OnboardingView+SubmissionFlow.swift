import Foundation
import SwiftUI

extension OnboardingView {
    func continueAccount(provider: AccountProvider) {
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

    func finishOnboarding() {
        Task {
            isSubmitting = true
            localError = nil
            appStore.setError(nil)
            setScreenState(.ready, state: .loading)
            defer { isSubmitting = false }

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
                activityDetail: draft.activity?.rawValue
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
