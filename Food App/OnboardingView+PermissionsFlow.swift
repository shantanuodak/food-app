import SwiftUI

extension OnboardingView {
    func requestHealthAccess() {
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
                    if granted {
                        flow.moveNextOnboarding()
                    }
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

    func disconnectHealthAccess() {
        appStore.disconnectAppleHealth()
        draft.connectHealth = false
        healthPermissionMessage = "Apple Health disconnected."
    }

    func requestNotificationAccess() {
        Task {
            let status = await appStore.requestNotificationAuthorization()
            await MainActor.run {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    draft.enableNotifications = true
                    notificationStatusMessage = "Notifications enabled."
                    flow.moveNextOnboarding()
                case .denied:
                    draft.enableNotifications = false
                    notificationStatusMessage = "Notifications disabled in iOS Settings — you can re-enable anytime."
                case .notDetermined:
                    draft.enableNotifications = false
                    notificationStatusMessage = nil
                @unknown default:
                    draft.enableNotifications = false
                    notificationStatusMessage = nil
                }
            }
        }
    }

    func autoAdvancePermissionRouteIfNeeded() async {
        switch flow.onboardingRoute {
        case .permissions:
            appStore.refreshHealthAuthorizationState()
            if appStore.isHealthSyncEnabled && appStore.healthAuthorizationState == .authorized {
                draft.connectHealth = true
                flow.moveNextOnboarding()
            }
        case .notificationsPermission:
            await appStore.refreshNotificationAuthState()
            switch appStore.notificationAuthState {
            case .authorized, .provisional, .ephemeral:
                draft.enableNotifications = true
                flow.moveNextOnboarding()
            default:
                break
            }
        default:
            break
        }
    }
}
