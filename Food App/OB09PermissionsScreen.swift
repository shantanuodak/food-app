import SwiftUI

/// Apple Health permission step. Originally rendered both Health and
/// Notifications back-to-back; the notifications block now lives in
/// `OB09bNotificationsPermissionScreen` so each permission gets its
/// own screen with its own decision moment.
struct OB09PermissionsScreen: View {
    @Binding var connectHealth: Bool
    let isRequestingHealthPermission: Bool
    let healthPermissionMessage: String?
    let onConnectHealth: () -> Void
    let onDisconnectHealth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        }
    }
}
