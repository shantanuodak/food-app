import SwiftUI

/// Notifications permission step — split out from the original
/// `OB09PermissionsScreen` so each permission gets a dedicated screen.
/// Visual shape mirrors the Health screen so the two read as a pair.
struct OB09bNotificationsPermissionScreen: View {
    @Binding var enableNotifications: Bool
    /// Invoked when the user toggles notifications on. The parent is
    /// responsible for actually calling the system permission prompt
    /// and reconciling the resulting authorization state.
    let onEnableNotifications: () -> Void
    /// Optional message surfaced under the notifications block — e.g.
    /// "Notifications disabled in iOS Settings — enable them anytime."
    let notificationStatusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        }
    }
}
