import SwiftUI
import UIKit

struct OB10ReadyScreen: View {
    var targetKcal: Int = 0
    var proteinTarget: Int = 0
    var carbTarget: Int = 0
    var fatTarget: Int = 0
    var statusMessage: String? = nil
    var isError = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var showConfetti = false
    @State private var calorieCounterValue: Double = 0
    @State private var macrosVisible = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer()

                // Headline
                VStack(spacing: 8) {
                    Text("You're all set")
                        .font(OnboardingTypography.instrumentSerif(style: .regular, size: 46))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Text("Your personalized plan is ready")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(OnboardingGlassTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .padding(.bottom, 32)

                // Animated calorie counter
                VStack(spacing: 6) {
                    Text("DAILY TARGET")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(OnboardingGlassTheme.textMuted)

                    HStack(spacing: 0) {
                        RollingNumberText(value: calorieCounterValue, fractionDigits: 0)
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                        Text(" kcal")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(OnboardingGlassTheme.textSecondary)
                            .offset(y: 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .onboardingGlassPanel(cornerRadius: 24, fillOpacity: 0.08, strokeOpacity: 0.14)
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)

                // Macro pills
                HStack(spacing: 10) {
                    macroPill(label: "Protein", value: proteinTarget, color: Color(red: 0.34, green: 0.56, blue: 1.00))
                    macroPill(label: "Carbs", value: carbTarget, color: Color(red: 0.20, green: 0.90, blue: 0.62))
                    macroPill(label: "Fat", value: fatTarget, color: Color(red: 1.00, green: 0.61, blue: 0.26))
                }
                .padding(.top, 16)
                .padding(.horizontal, 24)
                .opacity(macrosVisible ? 1 : 0)
                .offset(y: macrosVisible ? 0 : 12)

                Spacer()

                // Status message (submission feedback)
                if let statusMessage, !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(isError ? .red : OnboardingGlassTheme.textSecondary)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }
            }

            // Confetti overlay
            if showConfetti {
                ConfettiOverlay()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            triggerCelebration()
        }
    }

    private func macroPill(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)g")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OnboardingGlassTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .onboardingGlassPanel(cornerRadius: 16, fillOpacity: 0.06, strokeOpacity: 0.10)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }

    private func triggerCelebration() {
        withAnimation(.easeOut(duration: 0.5)) {
            appeared = true
        }
        withAnimation(.spring(response: 1.4, dampingFraction: 0.75).delay(0.3)) {
            calorieCounterValue = Double(targetKcal)
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.8)) {
            macrosVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showConfetti = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - Confetti Overlay

private struct ConfettiOverlay: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var animating = false

    private let colors: [Color] = [
        OnboardingGlassTheme.accentStart,
        OnboardingGlassTheme.accentEnd,
        Color(red: 0.34, green: 0.56, blue: 1.00),
        Color(red: 0.20, green: 0.90, blue: 0.62),
        Color(red: 1.00, green: 0.61, blue: 0.26),
        Color(red: 0.80, green: 0.40, blue: 1.00)
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    RoundedRectangle(cornerRadius: particle.isCircle ? particle.size / 2 : 2)
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.isCircle ? particle.size : particle.size * 2.5)
                        .rotationEffect(.degrees(animating ? particle.endRotation : 0))
                        .offset(
                            x: animating ? particle.endX : geo.size.width / 2,
                            y: animating ? particle.endY : geo.size.height * 0.35
                        )
                        .scaleEffect(animating ? particle.endScale : 0.2)
                        .opacity(animating ? 0 : 1)
                }
            }
            .onAppear {
                particles = (0..<30).map { _ in
                    ConfettiParticle(
                        color: colors.randomElement() ?? .white,
                        size: CGFloat.random(in: 5...10),
                        isCircle: Bool.random(),
                        endX: CGFloat.random(in: -geo.size.width * 0.5...geo.size.width * 0.5),
                        endY: CGFloat.random(in: -geo.size.height * 0.3...geo.size.height * 0.5),
                        endRotation: Double.random(in: -360...360),
                        endScale: CGFloat.random(in: 0.4...1.2)
                    )
                }
                withAnimation(.easeOut(duration: 1.8)) {
                    animating = true
                }
            }
        }
    }
}

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let color: Color
    let size: CGFloat
    let isCircle: Bool
    let endX: CGFloat
    let endY: CGFloat
    let endRotation: Double
    let endScale: CGFloat
}
