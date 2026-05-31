import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OB03AgeScreen: View {
    @Binding var age: Double
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    private let ageRange = OnboardingBaselineRange.age
    private let itemHeight: CGFloat = 90

    private var currentAge: Int {
        Int(age.rounded())
    }

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                // Headline
                Text("How young are you?")
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 34))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .padding(.top, 20)

                Text("We'll use this to personalize your plan")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
                    .opacity(appeared ? 1 : 0)
                    .padding(.top, 8)

                Spacer()

                // Hero age display
                heroAgeSelector
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.9)

                Spacer()

                // CTA
                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text("Next")
                            .font(.system(size: 16, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(OnboardingGlassTheme.ctaForeground)
                    .frame(width: 220, height: 60)
                    .background(OnboardingGlassTheme.ctaBackground)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    // MARK: - Hero Age Selector

    private var heroAgeSelector: some View {
        SmoothScrollPicker(
            value: currentAge,
            range: ageRange.lowerBound...ageRange.upperBound,
            onSet: { age = Double($0) }
        )
    }

    // MARK: - Top Bar

    private var topBar: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white)
                                .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
                        )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .frame(height: 44)
    }

    // MARK: - Helpers

}
