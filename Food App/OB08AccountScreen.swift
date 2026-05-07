import SwiftUI

struct OB08AccountScreen: View {
    let isLoading: Bool
    let prefersGooglePrimary: Bool
    let enableApple: Bool
    let onSelectProvider: (AccountProvider) -> Void
    var createAccountTitle: String? = nil
    var onCreateAccount: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Provider buttons — side by side
            HStack(spacing: 12) {
                ForEach(Array(providerOptions.enumerated()), id: \.element.id) { idx, option in
                    providerButton(for: option, animDelay: 0.18 + Double(idx) * 0.1)
                        .disabled(isLoading || !option.isEnabled)
                        .opacity(option.isEnabled ? 1 : 0.4)
                }
            }

            // Apple unavailable note
            if !enableApple {
                Text(L10n.onboardingAccountAppleUnavailable)
                    .font(.caption)
                    .foregroundStyle(OnboardingGlassTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.45), value: appeared)
            }

            // Loading indicator
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(OnboardingGlassTheme.textSecondary)
                        .controlSize(.small)
                    Text(L10n.onboardingAccountConnecting)
                        .font(.caption)
                        .foregroundStyle(OnboardingGlassTheme.textSecondary)
                }
                .padding(.top, 12)
            }

            if let createAccountTitle, let onCreateAccount {
                Button {
                    onCreateAccount()
                } label: {
                    Text(createAccountTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OnboardingGlassTheme.textSecondary)
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
            HStack(spacing: 10) {
                providerIcon(provider: option.provider)
                Text(option.shortTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
        }
        .buttonStyle(SignInUnifiedButtonStyle())
        .accessibilityLabel(Text(option.shortTitle))
        .accessibilityHint(Text("Sign in with \(option.shortTitle) to save your progress."))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.easeOut(duration: 0.45).delay(animDelay), value: appeared)
    }

    @ViewBuilder
    private func providerIcon(provider: AccountProvider) -> some View {
        switch provider {
        case .apple:
            Image(systemName: "apple.logo")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(OnboardingGlassTheme.textPrimary)
        case .google:
            Image("ios_light_rd_na")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 22, height: 22)
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

// MARK: - Unified Button Style
//
// Quiet Wellness button: flat neutral surface, hairline border, 12pt corner.
// Replaces the previous glass-panel style which sat at 96pt tall with a
// frosted material background and layered shadow.

private struct SignInUnifiedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(OnboardingGlassTheme.neutralSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(OnboardingGlassTheme.hairline, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
