import SwiftUI

/// Apple Health permission step. Self-contained layout owning its own
/// chrome (back chevron, icon row, big serif headline, privacy block,
/// Continue button) so the parent route view is a thin shell.
///
/// Visual brief (per design feedback):
/// - Two app-style icon cards at the top with a small link badge between
///   them (Apple Health on the left, Food App on the right).
/// - Two-line big headline ("link to" + "Apple Health"), with the second
///   line in an Apple-Health-leaning blue accent.
/// - Subhead + hairline divider + lock icon + privacy disclosure.
/// - Single light-pill "Continue" CTA at the bottom.
///
/// **TODO assets**: drop the real Apple Health icon as
/// `Assets.xcassets/AppleHealthIcon.imageset` and the Food App logomark
/// as `Assets.xcassets/FoodAppIcon.imageset` (or tell me a different
/// name and I'll wire it up). The placeholders below render OK for
/// layout review but should be swapped before TestFlight.
struct OB09PermissionsScreen: View {
    @Binding var connectHealth: Bool
    let isRequestingHealthPermission: Bool
    let healthPermissionMessage: String?
    let onConnectHealth: () -> Void
    let onDisconnectHealth: () -> Void
    /// Tap on the "Continue" CTA. The parent advances to the next route.
    let onContinue: () -> Void
    /// Tap on the back chevron in the top bar.
    let onBack: () -> Void

    /// Apple Health brand-leaning blue. Light-mode equivalent of the
    /// lavender used in the dark-mode mockup.
    private let appleHealthAccent = Color(red: 0.30, green: 0.40, blue: 0.95)

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                Spacer(minLength: 8)

                iconRow
                    .padding(.bottom, 28)

                headline
                    .padding(.horizontal, 24)

                subhead
                    .padding(.top, 12)
                    .padding(.horizontal, 32)

                if let healthPermissionMessage {
                    Text(healthPermissionMessage)
                        .font(.footnote)
                        .foregroundStyle(connectHealth ? .green : OnboardingGlassTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal, 32)
                }

                Spacer(minLength: 20)

                Divider()
                    .background(OnboardingGlassTheme.panelStroke)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 18)

                privacyBlock
                    .padding(.horizontal, 32)

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

    // MARK: - Icon row (Apple Health ↔ link badge ↔ Food App)

    private var iconRow: some View {
        HStack(spacing: 14) {
            // Apple Health placeholder — white rounded card with red heart.
            // Replace with `Image("AppleHealthIcon")` once the asset lands.
            iconCard(
                background: Color.white,
                cornerRadius: 22,
                content: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.18, blue: 0.33), Color(red: 0.95, green: 0.10, blue: 0.55)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )

            // Food App placeholder — purple rounded card with a leaf glyph
            // standing in for the real logomark. Swap with
            // `Image("FoodAppIcon")` once the asset lands.
            iconCard(
                background: LinearGradient(
                    colors: [Color(red: 0.42, green: 0.32, blue: 0.95), Color(red: 0.32, green: 0.20, blue: 0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                cornerRadius: 22,
                content: {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                }
            )
        }
        .overlay(linkBadge)
    }

    private func iconCard<Background: ShapeStyle, Content: View>(
        background: Background,
        cornerRadius: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(background)
                .frame(width: 88, height: 88)
                .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)
            content()
        }
    }

    private var linkBadge: some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.20), radius: 6, y: 2)
            Image(systemName: "link")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("link to")
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(OnboardingGlassTheme.textPrimary)
            Text("Apple Health")
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(appleHealthAccent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subhead: some View {
        Text("With this access, we can create a more personalised experience for you.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(OnboardingGlassTheme.textSecondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, -8) // align with headline since headline has 24pt outer pad
    }

    // MARK: - Privacy block

    private var privacyBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)

            Text("Your health data is never stored or shared with third parties. It remains private and is used only to enhance your experience while ensuring the highest standards of security.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(OnboardingGlassTheme.textMuted)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Continue button

    private var continueButton: some View {
        Button {
            if connectHealth {
                onContinue()
            } else {
                onConnectHealth()
            }
        } label: {
            ZStack {
                if isRequestingHealthPermission {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.black)
                            .controlSize(.small)
                        Text("Connecting…")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                } else {
                    Text(connectHealth ? "Continue" : "Connect")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                }
            }
            .frame(width: 280, height: 56)
            .background(Color.white)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(isRequestingHealthPermission)
    }
}
