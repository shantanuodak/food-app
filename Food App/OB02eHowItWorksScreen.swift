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
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .opacity(appeared ? 1 : 0)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                // Feature cards
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 26) {
                        // Card 1: Type anything — blue gradient
                        typingCard

                        // Card 2: Track your Progress — amber gradient
                        TrackProgressCardView()

                        // Card 3: Take a Food Photo — dark gradient
                        TakePhotoCardView()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)

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

    // MARK: - Typing Card (Blue Gradient)

    private var typingCard: some View {
        VStack(spacing: 0) {
            LoggingDemoAnimation()
                .padding(.horizontal, 12)
                .padding(.top, 29)

            Text("Type anything - get instant nutrition facts")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.top, 10)
                .padding(.bottom, 20)
        }
        .frame(height: 142)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(red: 0.56, green: 0.71, blue: 0.83), location: 0),
                            .init(color: Color(red: 0.44, green: 0.62, blue: 0.81), location: 0.25),
                            .init(color: Color(red: 0.33, green: 0.53, blue: 0.78), location: 0.5),
                            .init(color: Color(red: 0.20, green: 0.45, blue: 0.76), location: 0.75),
                            .init(color: Color(red: 0.09, green: 0.36, blue: 0.74), location: 1.0)
                        ]),
                        center: UnitPoint(x: 0.23, y: 0.52),
                        startRadius: 0,
                        endRadius: 320
                    )
                )
                .shadow(color: .black.opacity(0.25), radius: 21.5, x: 0, y: 4)
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
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
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
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .overlay(
            GeometryReader { geo in
                let w = geo.size.width
                let sweepWidth = w * 0.6

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.8), location: 0.4),
                        .init(color: .white.opacity(0.9), location: 0.5),
                        .init(color: .white.opacity(0.8), location: 0.6),
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

    private let greenWidth: CGFloat = 38.0 / 92.0   // ~41%
    private let blueWidth: CGFloat = 64.0 / 92.0    // ~70%
    private let orangeWidth: CGFloat = 1.0           // 100%

    var body: some View {
        HStack(spacing: 19) {
            // Left: dark card with calorie summary
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color(red: 0.20, green: 0.20, blue: 0.20))
                    .frame(width: 115, height: 88)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Total")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.white)
                            Text("720 cal")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        Image(systemName: "flame.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(red: 0.95, green: 0.75, blue: 0.20))
                    }

                    // Animated segmented progress bar
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(red: 1.0, green: 0.51, blue: 0.15))
                            .frame(width: 92 * barProgress, height: 8)

                        Capsule()
                            .fill(Color(red: 0.16, green: 0.72, blue: 1.0))
                            .frame(width: 92 * blueWidth * barProgress, height: 8)

                        Capsule()
                            .fill(Color(red: 0.27, green: 0.69, blue: 0.08))
                            .frame(width: 92 * greenWidth * barProgress, height: 8)
                    }
                    .frame(width: 92, height: 8, alignment: .leading)
                    .padding(.top, 10)
                }
                .padding(.leading, 12)
            }
            .frame(width: 115)

            // Right: text
            VStack(alignment: .leading, spacing: 4) {
                Text("Track your Progress")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Track your daily progress and see trends")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 23)
        .padding(.trailing, 26)
        .padding(.vertical, 27)
        .frame(height: 142)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(red: 0.95, green: 0.84, blue: 0.47), location: 0),
                            .init(color: Color(red: 0.92, green: 0.73, blue: 0.31), location: 0.5),
                            .init(color: Color(red: 0.91, green: 0.67, blue: 0.22), location: 0.75),
                            .init(color: Color(red: 0.89, green: 0.62, blue: 0.14), location: 1.0)
                        ]),
                        center: UnitPoint(x: 0.23, y: 0.52),
                        startRadius: 0,
                        endRadius: 320
                    )
                )
                .shadow(color: .black.opacity(0.25), radius: 21.5, x: 0, y: 4)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 1.5).delay(0.8)) {
                barProgress = 1.0
            }
        }
    }
}

// MARK: - Take a Food Photo Card

private struct TakePhotoCardView: View {
    private let orbit: CGFloat = 52
    private let period: TimeInterval = 6

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

                // Orbiting camera icon
                let camRad = angle * .pi / 180
                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
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
                    .foregroundStyle(.white)

                Text("Just take a picture\nand log your food.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.39))
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .padding(.vertical, 12)
        .frame(height: 142)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(red: 0.43, green: 0.42, blue: 0.42), location: 0),
                            .init(color: Color(red: 0.32, green: 0.31, blue: 0.31), location: 0.23),
                            .init(color: Color(red: 0.22, green: 0.21, blue: 0.21), location: 0.47),
                            .init(color: Color(red: 0.16, green: 0.16, blue: 0.16), location: 0.59),
                            .init(color: Color(red: 0.11, green: 0.11, blue: 0.11), location: 0.70),
                            .init(color: Color(red: 0.05, green: 0.05, blue: 0.05), location: 0.82),
                            .init(color: .black, location: 0.94)
                        ]),
                        center: UnitPoint(x: 0.23, y: 0.52),
                        startRadius: 0,
                        endRadius: 320
                    )
                )
                .shadow(color: .black.opacity(0.25), radius: 21.5, x: 0, y: 4)
        )
    }
}
