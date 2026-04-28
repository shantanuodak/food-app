import SwiftUI

/// Notifications permission step. Self-contained layout owning its own
/// chrome (back chevron, headline, dialog preview, Connect/Continue
/// CTA) so the parent route view is a thin shell.
///
/// Visual brief (per design feedback):
/// - Permission *priming*: show a preview of the iOS system dialog
///   on-screen so the user knows exactly what's about to happen and
///   what tapping "Allow" does. Tapping the screen's "Connect" CTA
///   fires the real iOS permission prompt.
/// - Big serif "Notifications" headline + brief subhead.
/// - Mock dialog rendered natively in SwiftUI by default; if a PNG
///   asset named `NotificationsPermissionPreview` is dropped into
///   `Assets.xcassets`, that takes over so the team can iterate on
///   the visual without touching code.
/// - Black-pill "Connect" CTA, switching to "Continue" once the
///   user has answered the OS prompt (regardless of allow/deny).
struct OB09bNotificationsPermissionScreen: View {
    @Binding var enableNotifications: Bool
    /// Invoked when the user taps Connect for the first time. The parent
    /// is responsible for actually calling the system permission prompt
    /// and reconciling the resulting authorization state.
    let onEnableNotifications: () -> Void
    /// Optional message surfaced under the dialog preview — e.g.
    /// "Notifications disabled in iOS Settings — enable them anytime."
    let notificationStatusMessage: String?
    /// Tap on "Continue" once the prompt has been answered.
    let onContinue: () -> Void
    /// Tap on the back chevron in the top bar.
    let onBack: () -> Void

    /// Tracks whether the user has tapped Connect at least once during
    /// this view's lifetime, so the CTA flips to "Continue" after the
    /// system prompt has been shown (even if the user denied).
    @State private var hasRequestedPermission = false

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                Spacer(minLength: 16)

                headline
                    .padding(.horizontal, 24)

                Spacer(minLength: 24)

                primingLabel
                    .padding(.bottom, 14)

                dialogPreview
                    .contentShape(Rectangle())
                    .onTapGesture {
                        requestOrContinue()
                    }

                if let notificationStatusMessage {
                    Text(notificationStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(enableNotifications ? .green : OnboardingGlassTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .padding(.horizontal, 32)
                }

                Spacer(minLength: 24)

                continueButton
                    .padding(.bottom, 28)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: onBack) {
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
            Spacer()
        }
        .frame(height: 44)
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: 8) {
            Text("Notifications")
                .font(OnboardingTypography.instrumentSerif(style: .regular, size: 41))
                .foregroundStyle(OnboardingGlassTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text("Optional. Helpful reminders to stay consistent — you can change this later in Settings.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Priming label

    private var primingLabel: some View {
        Text("When you tap Connect, you'll see this:")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(OnboardingGlassTheme.textMuted)
            .multilineTextAlignment(.center)
    }

    // MARK: - Dialog preview

    /// Asset-first: drop a PNG named `NotificationsPermissionPreview` into
    /// `Assets.xcassets` and it takes over. Otherwise the native SwiftUI
    /// replica renders so the layout never looks broken.
    @ViewBuilder
    private var dialogPreview: some View {
        if UIImage(named: "NotificationsPermissionPreview") != nil {
            Image("NotificationsPermissionPreview")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 290)
                .shadow(color: Color.black.opacity(0.18), radius: 22, y: 8)
        } else {
            iOSAlertReplica
                .frame(maxWidth: 270)
                .shadow(color: Color.black.opacity(0.18), radius: 22, y: 8)
        }
    }

    private var iOSAlertReplica: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("\u{201C}Food App\u{201D} Would Like to\nSend You Notifications")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Notifications may include alerts, sounds, and icon badges. These can be configured in Settings.")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 19)
            .padding(.bottom, 16)

            Divider()

            HStack(spacing: 0) {
                Text("Don\u{2019}t Allow")
                    .font(.system(size: 17))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)

                Divider()
                    .frame(height: 44)

                Text("Allow")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .frame(height: 44)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Continue CTA

    private var continueButton: some View {
        let hasAnswered = enableNotifications || hasRequestedPermission
        let label = hasAnswered ? "Continue" : "Connect"

        return Button {
            requestOrContinue()
        } label: {
            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OnboardingGlassTheme.ctaForeground)
                .frame(width: 280, height: 56)
                .background(OnboardingGlassTheme.ctaBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func requestOrContinue() {
        if enableNotifications || hasRequestedPermission {
            onContinue()
        } else {
            hasRequestedPermission = true
            onEnableNotifications()
        }
    }
}
