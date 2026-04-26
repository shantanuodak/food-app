import SwiftUI

struct OB09PermissionsScreen: View {
    @Binding var connectHealth: Bool
    @Binding var enableNotifications: Bool
    let isRequestingHealthPermission: Bool
    let healthPermissionMessage: String?
    let onConnectHealth: () -> Void
    let onDisconnectHealth: () -> Void
    /// Invoked when the user toggles notifications on. The parent is
    /// responsible for actually calling the system permission prompt
    /// and reconciling the resulting authorization state.
    let onEnableNotifications: () -> Void
    /// Optional message surfaced under the notifications block — e.g.
    /// "Notifications disabled in iOS Settings — enable them anytime."
    let notificationStatusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("These are optional. You can change both later from Settings.")
                .font(.footnote)
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .padding(.horizontal, 4)

            OnboardingPermissionBlock(
                title: "Apple Health",
                bodyText: "Sync activity and energy data automatically.",
                enabled: connectHealth
            ) {
                if connectHealth {
                    onDisconnectHealth()
                } else {
                    onConnectHealth()
                }
            }

            if isRequestingHealthPermission {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Requesting Apple Health access...")
                }
                .font(.footnote)
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
            } else if let healthPermissionMessage {
                Text(healthPermissionMessage)
                    .font(.footnote)
                    .foregroundStyle(connectHealth ? .green : OnboardingGlassTheme.textSecondary)
            }

            OnboardingPermissionBlock(
                title: "Notifications",
                bodyText: "Helpful reminders to stay consistent.",
                enabled: enableNotifications
            ) {
                if enableNotifications {
                    enableNotifications = false
                } else {
                    onEnableNotifications()
                }
            }

            if let notificationStatusMessage {
                Text(notificationStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(enableNotifications ? .green : OnboardingGlassTheme.textSecondary)
            }

            let enabledCount = (connectHealth ? 1 : 0) + (enableNotifications ? 1 : 0)
            if enabledCount > 0 {
                OnboardingValueCard(
                    title: "Permissions enabled",
                    bodyText: "\(enabledCount) optional integration\(enabledCount == 1 ? "" : "s") enabled.",
                    isSuccess: true
                )
            }
        }
    }
}
