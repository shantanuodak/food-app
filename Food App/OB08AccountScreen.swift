import SwiftUI

struct OB08AccountScreen: View {
    let isLoading: Bool
    let prefersGooglePrimary: Bool
    let enableApple: Bool
    let onSelectProvider: (AccountProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(providerOptions) { option in
                accountButton(
                    option.title,
                    icon: option.icon,
                    provider: option.provider,
                    isPrimary: option.isPrimary
                )
                .disabled(isLoading || !option.isEnabled)
                .opacity(option.isEnabled ? 1 : 0.45)
            }

            if !enableApple {
                Text("Google sign-in is enabled right now. Apple sign-in is coming soon.")
                    .font(.caption)
                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
                    .padding(.horizontal, 4)
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Connecting account...")
                        .font(.caption)
                        .foregroundStyle(OnboardingGlassTheme.textSecondary)
                }
            }

            Text("No spam. No surprise emails. Just account essentials.")
                .font(.caption)
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    private struct ProviderOption: Identifiable {
        let title: String
        let icon: String
        let provider: AccountProvider
        let isPrimary: Bool
        let isEnabled: Bool

        var id: String { provider.rawValue }
    }

    private var providerOptions: [ProviderOption] {
        if prefersGooglePrimary {
            return [
                ProviderOption(title: "Continue with Google", icon: "globe", provider: .google, isPrimary: true, isEnabled: true),
                ProviderOption(title: "Continue with Apple", icon: "apple.logo", provider: .apple, isPrimary: false, isEnabled: enableApple)
            ]
        }

        return [
            ProviderOption(title: "Continue with Apple", icon: "apple.logo", provider: .apple, isPrimary: true, isEnabled: enableApple),
            ProviderOption(title: "Continue with Google", icon: "globe", provider: .google, isPrimary: false, isEnabled: true)
        ]
    }

    private func accountButton(_ title: String, icon: String, provider: AccountProvider, isPrimary: Bool) -> some View {
        Button {
            onSelectProvider(provider)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isPrimary ? OnboardingGlassTheme.buttonPrimaryText.opacity(0.82) : OnboardingGlassTheme.textPrimary)
                Text(title)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(isPrimary ? AnyButtonStyle(OnboardingGlassPrimaryButtonStyle()) : AnyButtonStyle(OnboardingGlassSecondaryButtonStyle()))
    }
}

private struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}
