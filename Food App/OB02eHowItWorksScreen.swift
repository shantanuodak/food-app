import SwiftUI

struct OB02eHowItWorksScreen: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                // Headline
                Text("Why Food App's\napproach works")
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 38))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .opacity(appeared ? 1 : 0)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                // Feature cards — staggered entry per card so they cascade in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 26) {
                        typingCard
                            .modifier(StaggeredEntry(index: 0, appeared: appeared))

                        TrackProgressCardView()
                            .modifier(StaggeredEntry(index: 1, appeared: appeared))

                        TakePhotoCardView()
                            .modifier(StaggeredEntry(index: 2, appeared: appeared))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
                }

                Spacer(minLength: 8)

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

    // MARK: - Typing Card (frosted glass)

    private var typingCard: some View {
        VStack(spacing: 0) {
            LoggingDemoAnimation()
                .padding(.horizontal, 12)
                .padding(.top, 29)

            Text("Type anything — get instant nutrition facts")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .padding(.top, 10)
                .padding(.bottom, 20)
        }
        .frame(height: 142)
        .frame(maxWidth: .infinity)
        .onboardingGlassPanel(cornerRadius: 24, fillOpacity: 0.07, strokeOpacity: 0.14)
        .shadow(color: OnboardingGlassTheme.buttonShadow, radius: 8, y: 3)
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
}

// MARK: - Staggered Entry

/// Fades + lifts each card in turn so the three feature cards cascade
/// rather than appearing all at once. Stagger is 80ms per index.
private struct StaggeredEntry: ViewModifier {
    let index: Int
    let appeared: Bool

    func body(content: Content) -> some View {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let delay = reduceMotion ? 0 : 0.1 + Double(index) * 0.08
        let duration = reduceMotion ? 0.0 : 0.4
        return content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : (reduceMotion ? 0 : 12))
            .animation(.easeOut(duration: duration).delay(delay), value: appeared)
    }
}

// MARK: - Logging Demo Animation

/// Simulates the real home-screen logging experience:
/// 1. Text types in character by character
/// 2. A brief "thinking" shimmer appears on the right
/// 3. The calorie estimate fades in
/// 4. Pauses, then resets and loops with a new food item
struct LoggingDemoAnimation: View {
    @Environment(\.colorScheme) private var colorScheme

    private let items: [(text: String, calories: String)] = [
        ("2 eggs and toast", "310 cal"),
        ("chicken salad", "420 cal"),
        ("greek yogurt", "180 cal"),
        ("cheese pizza", "285 cal")
    ]

    @State private var currentIndex = 0
    @State private var typedCount = 0
    @State private var phase: DemoPhase = .idle
    @State private var timerTask: Task<Void, Never>?

    private enum DemoPhase {
        case idle
        case typing
        case thinking
        case result
        case hold
    }

    private var currentItem: (text: String, calories: String) {
        items[currentIndex % items.count]
    }

    private var displayedText: String {
        String(currentItem.text.prefix(typedCount))
    }

    var body: some View {
        VStack(spacing: 0) {
            // The simulated input row
            HStack(alignment: .center, spacing: 0) {
                // Typed text + cursor
                HStack(spacing: 0) {
                    Text(displayedText)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if phase == .typing || phase == .idle {
                        Text("|")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Color.primary.opacity(0.4))
                            .opacity(phase == .typing ? 1 : 0.4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right side: thinking or result with shimmer
                Group {
                    if phase == .thinking {
                        thinkingIndicator
                            .transition(.opacity)
                    } else if phase == .result || phase == .hold {
                        ShimmerCalorieText(text: currentItem.calories)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .frame(width: 110, alignment: .trailing)
                .animation(.easeInOut(duration: 0.3), value: phase)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .onboardingGlassPanel(cornerRadius: 14, fillOpacity: 0.10, strokeOpacity: 0.14)
        }
        .onAppear { startAnimation() }
        .onDisappear { timerTask?.cancel() }
    }

    // MARK: - Thinking shimmer

    private var thinkingIndicator: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase == .thinking ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15),
                        value: phase
                    )
            }
        }
    }

    // MARK: - Animation loop

    private func startAnimation() {
        timerTask?.cancel()

        // Reduced-motion: jump straight to the final result of the first item, no loop.
        if UIAccessibility.isReduceMotionEnabled {
            typedCount = currentItem.text.count
            phase = .hold
            return
        }

        timerTask = Task {
            // Initial pause
            try? await Task.sleep(nanoseconds: 800_000_000)

            while !Task.isCancelled {
                // Reset for new item
                typedCount = 0
                phase = .typing

                // Type each character
                let text = currentItem.text
                for charIndex in 1...text.count {
                    guard !Task.isCancelled else { return }
                    typedCount = charIndex
                    // Variable speed — faster for spaces, slight randomness
                    let char = text[text.index(text.startIndex, offsetBy: charIndex - 1)]
                    let baseDelay: UInt64 = char == " " ? 30_000_000 : 55_000_000
                    let jitter = UInt64.random(in: 0...20_000_000)
                    try? await Task.sleep(nanoseconds: baseDelay + jitter)
                }

                // Thinking phase
                guard !Task.isCancelled else { return }
                phase = .thinking
                try? await Task.sleep(nanoseconds: 1_200_000_000)

                // Result
                guard !Task.isCancelled else { return }
                phase = .result
                try? await Task.sleep(nanoseconds: 300_000_000)
                phase = .hold

                // Hold so user can read
                try? await Task.sleep(nanoseconds: 2_500_000_000)

                // Advance to next item
                guard !Task.isCancelled else { return }
                currentIndex = (currentIndex + 1) % items.count
                phase = .idle
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
    }
}

// MARK: - Shimmer Calorie Text

/// A calorie label with a continuous lighting sweep across the text.
private struct ShimmerCalorieText: View {
    let text: String
    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        let accentTint = LinearGradient(
            colors: [OnboardingGlassTheme.accentStart, OnboardingGlassTheme.accentEnd],
            startPoint: .leading,
            endPoint: .trailing
        )

        return HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(accentTint)

            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(accentTint)
        }
        .overlay(
            GeometryReader { geo in
                let w = geo.size.width
                let sweepWidth = w * 0.6

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.7), location: 0.4),
                        .init(color: .white.opacity(0.85), location: 0.5),
                        .init(color: .white.opacity(0.7), location: 0.6),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: sweepWidth)
                .offset(x: shimmerOffset * (w + sweepWidth) - sweepWidth)
                .blendMode(.sourceAtop)
            }
        )
        .compositingGroup()
        .onAppear {
            // Reduced-motion: skip the sweeping shimmer (still keeps the gradient tint)
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            withAnimation(
                .easeInOut(duration: 1.8)
                .repeatForever(autoreverses: false)
            ) {
                shimmerOffset = 1
            }
        }
    }
}

// MARK: - Track Your Progress Card

private struct TrackProgressCardView: View {
    @State private var barProgress: CGFloat = 0

    var body: some View {
        let accentBar = LinearGradient(
            colors: [OnboardingGlassTheme.accentStart, OnboardingGlassTheme.accentEnd],
            startPoint: .leading,
            endPoint: .trailing
        )

        return HStack(spacing: 19) {
            // Left: nested glass tile with calorie summary + animated progress bar
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Total")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(OnboardingGlassTheme.textSecondary)
                        Text("720 cal")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(OnboardingGlassTheme.textPrimary)
                    }

                    Image(systemName: "flame.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(OnboardingGlassTheme.accentStart)
                }

                // Single accent-gradient progress bar
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(OnboardingGlassTheme.textPrimary.opacity(0.10))
                        .frame(width: 92, height: 8)

                    Capsule()
                        .fill(accentBar)
                        .frame(width: 92 * barProgress, height: 8)
                }
                .frame(width: 92, height: 8, alignment: .leading)
            }
            .padding(12)
            .frame(width: 124)
            .onboardingGlassPanel(cornerRadius: 15, fillOpacity: 0.10, strokeOpacity: 0.14)

            // Right: text
            VStack(alignment: .leading, spacing: 4) {
                Text("Track your Progress")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)

                Text("Track your daily progress and see trends")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 18)
        .padding(.trailing, 20)
        .padding(.vertical, 16)
        .frame(height: 142)
        .frame(maxWidth: .infinity)
        .onboardingGlassPanel(cornerRadius: 24, fillOpacity: 0.07, strokeOpacity: 0.14)
        .shadow(color: OnboardingGlassTheme.buttonShadow, radius: 8, y: 3)
        .onAppear {
            // Reduced-motion: jump straight to filled state.
            guard !UIAccessibility.isReduceMotionEnabled else {
                barProgress = 1.0
                return
            }
            withAnimation(.easeOut(duration: 1.5).delay(0.8)) {
                barProgress = 1.0
            }
        }
    }
}

// MARK: - Take a Food Photo Card

private struct TakePhotoCardView: View {
    private let orbit: CGFloat = 52
    private let period: TimeInterval = 8

    var body: some View {
        TimelineView(.animation(paused: UIAccessibility.isReduceMotionEnabled)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let angle = (elapsed.truncatingRemainder(dividingBy: period) / period) * 360

            cardContent(angle: angle)
        }
    }

    private func cardContent(angle: Double) -> some View {
        HStack(spacing: 16) {
            // Food photo — large, fills card height
            ZStack {
                Image("food_photo_demo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 117, height: 117)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(OnboardingGlassTheme.panelStroke, lineWidth: 1)
                    )

                // Orbiting camera icon — accent-tinted capsule, readable on the light glass card
                let camRad = angle * .pi / 180
                Circle()
                    .fill(OnboardingGlassTheme.accentStart.opacity(0.22))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Circle()
                            .strokeBorder(OnboardingGlassTheme.accentStart.opacity(0.45), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(OnboardingGlassTheme.textPrimary)
                    )
                    .offset(
                        x: cos(camRad) * orbit,
                        y: sin(camRad) * orbit
                    )

            }
            .frame(width: 117, height: 117)

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text("Take a Food Photo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)

                Text("Just take a picture\nand log your food.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .padding(.vertical, 12)
        .frame(height: 142)
        .frame(maxWidth: .infinity)
        .onboardingGlassPanel(cornerRadius: 24, fillOpacity: 0.07, strokeOpacity: 0.14)
        .shadow(color: OnboardingGlassTheme.buttonShadow, radius: 8, y: 3)
    }
}
