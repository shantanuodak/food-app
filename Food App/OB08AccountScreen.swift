import SwiftUI

struct OB08AccountScreen: View {
    let isLoading: Bool
    let prefersGooglePrimary: Bool
    let enableApple: Bool
    let onSelectProvider: (AccountProvider) -> Void
    var createAccountTitle: String? = nil
    var onCreateAccount: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                ForEach(Array(providerOptions.enumerated()), id: \.element.id) { idx, option in
                    providerButton(for: option, animDelay: 0.18 + Double(idx) * 0.1)
                        .disabled(isLoading || !option.isEnabled)
                        .opacity(option.isEnabled ? 1 : 0.4)
                }
            }

            if !enableApple {
                Text(L10n.onboardingAccountAppleUnavailable)
                    .font(.caption)
                    .foregroundStyle(AccountScreenPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.45), value: appeared)
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(AccountScreenPalette.secondaryInk)
                        .controlSize(.small)
                    Text(L10n.onboardingAccountConnecting)
                        .font(.caption)
                        .foregroundStyle(AccountScreenPalette.secondaryInk)
                }
                .padding(.top, 12)
            }

            if let createAccountTitle, let onCreateAccount {
                Button {
                    onCreateAccount()
                } label: {
                    Text(createAccountTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AccountScreenPalette.secondaryInk)
                        .padding(.top, isLoading ? 10 : 18)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .accessibilityHint(Text("Start the onboarding flow to create a new account."))
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
                .animation(.easeOut(duration: 0.45).delay(0.36), value: appeared)
            }
        }
        .onAppear {
            appeared = true
        }
    }

    // MARK: - Provider Buttons

    @ViewBuilder
    private func providerButton(for option: ProviderOption, animDelay: Double) -> some View {
        Button {
            onSelectProvider(option.provider)
        } label: {
            HStack(spacing: 14) {
                providerIcon(provider: option.provider, isPrimary: option.isPrimary)

                Text("Continue with \(option.shortTitle)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AccountScreenPalette.buttonInk)

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AccountScreenPalette.buttonInk)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(AccountScreenPalette.buttonArrowCircle))
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(SignInUnifiedButtonStyle(isPrimary: option.isPrimary))
        .accessibilityLabel(Text("Continue with \(option.shortTitle)"))
        .accessibilityHint(Text("Sign in with \(option.shortTitle) to save your progress."))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.easeOut(duration: 0.45).delay(animDelay), value: appeared)
    }

    @ViewBuilder
    private func providerIcon(provider: AccountProvider, isPrimary: Bool) -> some View {
        switch provider {
        case .apple:
            // Black Apple mark on the white card.
            Image(systemName: "apple.logo")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AccountScreenPalette.buttonInk)
                .frame(width: 38, height: 38)
        case .google:
            // Full-color Google "G" on the white card.
            Image("ios_light_rd_na")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .frame(width: 38, height: 38)
        }
    }

    // MARK: - Provider Options

    private struct ProviderOption: Identifiable {
        let shortTitle: String
        let provider: AccountProvider
        let isPrimary: Bool
        let isEnabled: Bool

        var id: String { provider.rawValue }
    }

    private var providerOptions: [ProviderOption] {
        if prefersGooglePrimary {
            return [
                ProviderOption(shortTitle: L10n.onboardingAccountGoogleLabel, provider: .google, isPrimary: true, isEnabled: true),
                ProviderOption(shortTitle: L10n.onboardingAccountAppleLabel, provider: .apple, isPrimary: false, isEnabled: enableApple)
            ]
        }
        return [
            ProviderOption(shortTitle: L10n.onboardingAccountAppleLabel, provider: .apple, isPrimary: true, isEnabled: enableApple),
            ProviderOption(shortTitle: L10n.onboardingAccountGoogleLabel, provider: .google, isPrimary: false, isEnabled: true)
        ]
    }
}

private enum AccountScreenPalette {
    static let ink = adaptiveColor(
        light: UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0),
        dark: UIColor(white: 0.96, alpha: 1.0)
    )
    static let secondaryInk = adaptiveColor(
        light: UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 0.76),
        dark: UIColor(white: 0.92, alpha: 0.74)
    )
    static let muted = adaptiveColor(
        light: UIColor(red: 0.36, green: 0.36, blue: 0.38, alpha: 0.62),
        dark: UIColor(white: 0.90, alpha: 0.60)
    )
    static let iconFill = adaptiveColor(
        light: UIColor(white: 0.94, alpha: 0.90),
        dark: UIColor(white: 1.0, alpha: 0.12)
    )
    static let primaryIconFill = adaptiveColor(
        light: UIColor(white: 0.92, alpha: 0.96),
        dark: UIColor(white: 1.0, alpha: 0.16)
    )
    static let secondaryIconFill = adaptiveColor(
        light: UIColor(white: 0.90, alpha: 0.82),
        dark: UIColor(white: 1.0, alpha: 0.08)
    )
    static let primaryButtonTop = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.94),
        dark: UIColor(red: 0.25, green: 0.20, blue: 0.17, alpha: 0.92)
    )
    static let primaryButtonBottom = adaptiveColor(
        light: UIColor(white: 0.96, alpha: 0.86),
        dark: UIColor(red: 0.18, green: 0.15, blue: 0.13, alpha: 0.92)
    )
    static let secondaryButtonTop = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.86),
        dark: UIColor(red: 0.21, green: 0.17, blue: 0.14, alpha: 0.90)
    )
    static let secondaryButtonBottom = adaptiveColor(
        light: UIColor(white: 0.95, alpha: 0.72),
        dark: UIColor(red: 0.16, green: 0.13, blue: 0.11, alpha: 0.88)
    )
    static let borderPrimary = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.07),
        dark: UIColor(white: 1.0, alpha: 0.16)
    )
    static let borderSecondary = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.055),
        dark: UIColor(white: 1.0, alpha: 0.12)
    )
    static let primaryAccent = adaptiveColor(
        light: UIColor(red: 0.87, green: 0.42, blue: 0.12, alpha: 1.0),
        dark: UIColor(red: 0.99, green: 0.76, blue: 0.55, alpha: 1.0)
    )
    static let primaryAccentFill = adaptiveColor(
        light: UIColor(red: 1.0, green: 0.91, blue: 0.84, alpha: 0.86),
        dark: UIColor(red: 0.33, green: 0.23, blue: 0.17, alpha: 0.92)
    )

    // Fixed white-card sign-in style. The connect screen renders over a dark
    // photo mosaic, so these stay white / near-black regardless of color scheme.
    static let buttonCardTop = Color.white
    static let buttonCardBottom = Color(white: 0.965)
    static let buttonCardBorder = Color.black.opacity(0.06)
    static let buttonCardShadow = Color.black.opacity(0.22)
    static let buttonInk = Color(white: 0.10)
    static let buttonArrowCircle = Color(white: 0.92)

    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

// MARK: - Unified Button Style
//
// Quiet Wellness button: flat neutral surface, hairline border, 12pt corner.
// Replaces the previous glass-panel style which sat at 96pt tall with a
// frosted material background and layered shadow.

private struct SignInUnifiedButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AccountScreenPalette.buttonCardTop, AccountScreenPalette.buttonCardBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(AccountScreenPalette.buttonCardBorder, lineWidth: 1)
            )
            .shadow(color: AccountScreenPalette.buttonCardShadow, radius: 22, y: 12)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
