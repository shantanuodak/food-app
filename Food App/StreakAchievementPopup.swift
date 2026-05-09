import SwiftUI
import UIKit

/// Full-screen, time-boxed celebration shown when the user crosses a new
/// streak-badge threshold. Mirrors the visual language of `StreakBadgeMedallion`
/// so the badge that animates in matches the one in the drawer hero / carousel.
///
/// Intended to be presented for ~3.5s. Self-dismisses on a timer; user can tap
/// to dismiss earlier. Fires a success haptic on first appear and a soft
/// confetti burst.
struct StreakAchievementPopup: View {
    let badge: StreakBadge
    let onDismiss: () -> Void

    /// Total time the popup stays on screen before auto-dismissing.
    private static let displayDuration: TimeInterval = 3.5

    @State private var hasAppeared = false
    @State private var medalScale: CGFloat = 0.6
    @State private var medalRotation: Double = -12
    @State private var raysOpacity: Double = 0
    @State private var raysScale: CGFloat = 0.5
    @State private var titleOffset: CGFloat = 24
    @State private var titleOpacity: Double = 0
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 26) {
                Spacer(minLength: 0)

                Text("BADGE UNLOCKED")
                    .font(.system(size: 13, weight: .black))
                    .tracking(3.0)
                    .foregroundStyle(.white.opacity(0.78))
                    .opacity(titleOpacity)
                    .offset(y: titleOffset * 0.5)

                medalStack

                VStack(spacing: 8) {
                    Text(badge.title)
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(badge.subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(titleOpacity)
                .offset(y: titleOffset)

                Text("\(badge.requiredDays) day\(badge.requiredDays == 1 ? "" : "s") of consistency")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.6))
                    .opacity(titleOpacity)

                Spacer(minLength: 0)

                Text("Tap to dismiss")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.bottom, 36)
                    .opacity(titleOpacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { dismissNow() }
        .onAppear { runEntranceAnimation() }
        .onDisappear { dismissTask?.cancel() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Badge unlocked: \(badge.title). \(badge.subtitle)"))
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Layered backdrop

    private var backdrop: some View {
        ZStack {
            // Vignette: dark gradient that pulls focus to the medal center.
            RadialGradient(
                colors: [
                    tierGlowColor.opacity(0.42),
                    Color.black.opacity(0.92),
                    Color.black
                ],
                center: .center,
                startRadius: 40,
                endRadius: 480
            )

            // Subtle warm tint so dark mode doesn't feel pure-black-flat.
            tierGlowColor.opacity(0.06)
        }
    }

    // MARK: - Medal + rays + confetti stack

    private var medalStack: some View {
        ZStack {
            // Animated rays — radial spokes that scale + rotate slowly.
            BurstRays(count: 14, color: tierGlowColor)
                .frame(width: 320, height: 320)
                .scaleEffect(raysScale)
                .opacity(raysOpacity)

            // Soft outer halo so the medal reads against the dark backdrop.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tierGlowColor.opacity(0.55), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 160
                    )
                )
                .frame(width: 280, height: 280)
                .blur(radius: 18)
                .opacity(raysOpacity)

            // Confetti — short-lived particles seeded behind the medal.
            ConfettiBurst(seed: badge.id)
                .frame(width: 320, height: 320)
                .opacity(raysOpacity)

            // The medal itself — same component as the drawer.
            StreakBadgeMedallion(badge: badge, isEarned: true, size: 156)
                .scaleEffect(medalScale)
                .rotationEffect(.degrees(medalRotation))
                .shadow(color: tierGlowColor.opacity(0.55), radius: 30, y: 12)
        }
        .frame(width: 320, height: 320)
    }

    // MARK: - Animation choreography

    private func runEntranceAnimation() {
        guard !hasAppeared else { return }
        hasAppeared = true

        // Haptic on first arrival — success notification, the iOS gold standard
        // for "you did it" moments. Prepared in advance to fire promptly.
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)

        // Medal pops in with a spring; rays + halo cross-fade behind it.
        withAnimation(.spring(response: 0.55, dampingFraction: 0.55, blendDuration: 0)) {
            medalScale = 1.0
            medalRotation = 0
        }

        withAnimation(.easeOut(duration: 0.6).delay(0.05)) {
            raysOpacity = 1.0
            raysScale = 1.0
        }

        withAnimation(.easeOut(duration: 0.45).delay(0.18)) {
            titleOpacity = 1.0
            titleOffset = 0
        }

        // Auto-dismiss timer.
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.displayDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismissNow()
        }
    }

    private func dismissNow() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.22)) {
            titleOpacity = 0
            raysOpacity = 0
            medalScale = 0.85
        }
        // Allow the fade to play before tearing down the view.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onDismiss()
        }
    }

    // MARK: - Tier-driven palette

    private var tierGlowColor: Color {
        switch badge.tier {
        case .bronze:
            return Color(red: 0.96, green: 0.50, blue: 0.18)
        case .silver:
            return Color(red: 0.74, green: 0.79, blue: 0.86)
        case .gold:
            return Color(red: 1.0, green: 0.74, blue: 0.20)
        case .platinum:
            return Color(red: 0.62, green: 0.66, blue: 0.74)
        }
    }
}

// MARK: - Radial rays (Apple Activity-style bursts behind the medal)

private struct BurstRays: View {
    let count: Int
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
            // Slow rotation for ambient motion. 360° over 12s.
            let rotation = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 12) / 12 * 360

            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    let angle = Double(index) / Double(count) * 360
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.0), color.opacity(0.85), color.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 6, height: 200)
                        .offset(y: -100)
                        .rotationEffect(.degrees(angle))
                }
            }
            .rotationEffect(.degrees(rotation))
            .blur(radius: 1.0)
        }
    }
}

// MARK: - Confetti — small one-shot particle burst

private struct ConfettiBurst: View {
    let seed: String

    private static let particleCount = 28
    private static let palette: [Color] = [
        Color(red: 1.0, green: 0.82, blue: 0.32),
        Color(red: 1.0, green: 0.54, blue: 0.18),
        Color(red: 0.96, green: 0.36, blue: 0.50),
        Color(red: 0.42, green: 0.74, blue: 0.96),
        Color(red: 0.62, green: 0.86, blue: 0.46)
    ]

    var body: some View {
        // Stable per-popup seed → particles look intentional, not jittery.
        // SystemRandomNumberGenerator seeded from hashing the badge id keeps
        // the same badge popup visually identical across launches.
        let particles = makeParticles()

        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 4)
            ZStack {
                ForEach(particles) { particle in
                    let progress = min(1.0, elapsed / particle.duration)
                    let distance = particle.travel * progress
                    let opacity = max(0, 1 - progress * 1.4)
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .offset(
                            x: cos(particle.angle) * distance,
                            y: sin(particle.angle) * distance
                        )
                        .opacity(opacity)
                        .scaleEffect(0.6 + progress * 0.6)
                }
            }
        }
    }

    private struct Particle: Identifiable {
        let id = UUID()
        let angle: Double      // radians
        let travel: Double     // pts from center
        let duration: Double   // seconds to reach travel distance
        let size: CGFloat
        let color: Color
    }

    private func makeParticles() -> [Particle] {
        // Hash the seed so the same badge always produces the same burst.
        var rng = SeededRandomGenerator(seed: UInt64(abs(seed.hashValue)))
        return (0..<Self.particleCount).map { _ in
            Particle(
                angle: Double.random(in: 0...(2 * .pi), using: &rng),
                travel: Double.random(in: 80...160, using: &rng),
                duration: Double.random(in: 1.6...2.6, using: &rng),
                size: CGFloat.random(in: 4...9, using: &rng),
                color: Self.palette.randomElement(using: &rng) ?? .orange
            )
        }
    }
}

/// Tiny deterministic RNG so a given badge id always seeds the same confetti.
/// Splittable LCG (numbers from Numerical Recipes) — good enough for visuals,
/// not for crypto.
private struct SeededRandomGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEADBEEF : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
