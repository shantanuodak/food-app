import SwiftUI

/// Animated dual-ring "breathing pause" visual. Originally lived inside
/// `EmotionalEatingBreathingDemoCard` in `OB02cChallengeInsightScreen`;
/// extracted so the real `MindfulPauseSheet` can reuse the exact same
/// breathing rhythm the user previewed during onboarding.
///
/// Honors `accessibilityReduceMotion` — when reduce-motion is on, the
/// circles render at their resting size with no scale animation, and the
/// countdown still ticks (so the timer remains useful) but without the
/// numericText content transition.
struct BreathingCircleView: View {
    var accent: Color = .pink
    /// Initial countdown in seconds. Decrements once per second; resets
    /// after a brief pause when it reaches near zero, so the user can
    /// watch the cycle for as long as they want to.
    var startSeconds: Int = 60

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    @State private var count: Int
    @State private var countdownTask: Task<Void, Never>?

    init(accent: Color = .pink, startSeconds: Int = 60) {
        self.accent = accent
        self.startSeconds = startSeconds
        self._count = State(initialValue: startSeconds)
    }

    var body: some View {
        ZStack {
            // Outer soft ring
            Circle()
                .stroke(accent.opacity(0.30), lineWidth: 10)
                .frame(width: 220, height: 220)
                .scaleEffect(reduceMotion ? 1.0 : (breathing ? 1.08 : 0.88))

            // Inner solid circle
            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: 184, height: 184)
                .scaleEffect(reduceMotion ? 1.0 : (breathing ? 1.05 : 0.9))

            VStack(spacing: 4) {
                Text("Pause")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.4)
                Text("\(count)s")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
        }
        .onAppear { start() }
        .onDisappear { countdownTask?.cancel() }
    }

    private func start() {
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            while !Task.isCancelled {
                // Tick down for ~12s, then reset for the next breath cycle.
                for _ in 0..<12 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    if reduceMotion {
                        count = max(0, count - 1)
                    } else {
                        withAnimation(.easeOut(duration: 0.25)) {
                            count = max(0, count - 1)
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }
                if reduceMotion {
                    count = startSeconds
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        count = startSeconds
                    }
                }
            }
        }
    }
}
