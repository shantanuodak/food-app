import SwiftUI

struct OB08AccountScreen: View {
    let isLoading: Bool
    let prefersGooglePrimary: Bool
    let enableApple: Bool
    let onSelectProvider: (AccountProvider) -> Void

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
                Text("Google sign-in is enabled right now. Apple sign-in is coming soon.")
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
                    Text("Connecting account...")
                        .font(.caption)
                        .foregroundStyle(OnboardingGlassTheme.textSecondary)
                }
                .padding(.top, 12)
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
            VStack(spacing: 12) {
                providerIcon(provider: option.provider)
                Text(option.shortTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
        }
        .buttonStyle(SignInUnifiedButtonStyle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(animDelay), value: appeared)
    }

    @ViewBuilder
    private func providerIcon(provider: AccountProvider) -> some View {
        switch provider {
        case .apple:
            Image(systemName: "apple.logo")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(OnboardingGlassTheme.textPrimary)
        case .google:
            Image("ios_light_rd_na")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 36, height: 36)
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
                ProviderOption(shortTitle: "Google", provider: .google, isPrimary: true, isEnabled: true),
                ProviderOption(shortTitle: "Apple", provider: .apple, isPrimary: false, isEnabled: enableApple)
            ]
        }
        return [
            ProviderOption(shortTitle: "Apple", provider: .apple, isPrimary: true, isEnabled: enableApple),
            ProviderOption(shortTitle: "Google", provider: .google, isPrimary: false, isEnabled: true)
        ]
    }
}

// MARK: - Unified Button Style

private struct SignInUnifiedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(OnboardingGlassTheme.panelFill)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(OnboardingGlassTheme.panelStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.07), radius: 10, y: 4)
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
