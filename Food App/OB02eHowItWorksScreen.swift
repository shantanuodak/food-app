import SwiftUI

struct OB02eHowItWorksScreen: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Cinematic intro choreography (2026-05-24 redesign):
    //   1. blank screen
    //   2. heading types itself out (typewriter + a soft haptic per letter),
    //      sitting low/centered as the lone hero element
    //   3. brief hold so the line lands
    //   4. heading rises to the top with a motion-blur as it travels
    //   5. the cards reveal one at a time below it (blur+lift in)
    //   6. the Next button fades in last
    // Tapping anywhere during the intro skips straight to the final state.
    private let headingText = "Why this works"
    private let cardCount = 5

    @State private var typedCount = 0
    @State private var showCaret = false
    @State private var headingSettled = false
    @State private var headingBlur: CGFloat = 0
    @State private var revealedCardCount = 0
    @State private var nextVisible = false
    @State private var introComplete = false
    @State private var skipRequested = false

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                // Voice rewrite (2026-05-01): "Why Food App's approach works"
                // → "Why this works". 2026-05-24: now types itself out as a
                // typewriter, then rises to its resting position with a
                // motion-blur. `padding(.top)` animates 168→24 to carry the
                // line up from its lower hero position to the top.
                TypewriterHeading(
                    fullText: headingText,
                    typedCount: typedCount,
                    showCaret: showCaret
                )
                .padding(.horizontal, 24)
                .padding(.top, headingSettled ? 24 : 168)
                .blur(radius: headingBlur)

                // Feature cards — staggered entry per card so they cascade in.
                // 2026-05-24: each card also gets a subtle FloatingDrift so the
                // grid reads as "infographic floating in space" rather than
                // "list of tappable rows". Testers were tapping the cards
                // expecting them to do something; the drift signals that the
                // cards are display content and Next is the only action.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 26) {
                        typingCard
                            .modifier(SequentialReveal(isVisible: revealedCardCount > 0))
                            .modifier(FloatingDrift(phaseSeed: 0.00))

                        TrackProgressCardView()
                            .modifier(SequentialReveal(isVisible: revealedCardCount > 1))
                            .modifier(FloatingDrift(phaseSeed: 0.20))

                        TakePhotoCardView()
                            .modifier(SequentialReveal(isVisible: revealedCardCount > 2))
                            .modifier(FloatingDrift(phaseSeed: 0.40))

                        CuratedRecipesCardView()
                            .modifier(SequentialReveal(isVisible: revealedCardCount > 3))
                            .modifier(FloatingDrift(phaseSeed: 0.60))

                        WidgetShortcutCardView()
                            .modifier(SequentialReveal(isVisible: revealedCardCount > 4))
                            .modifier(FloatingDrift(phaseSeed: 0.80))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
                }
                // No scrolling until the reveal finishes — the cards are
                // present (for layout) but transparent during the intro.
                .scrollDisabled(!introComplete)

                Spacer(minLength: 8)

                // CTA — fades in last, once every card has revealed.
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
                .opacity(nextVisible ? 1 : 0)
                .allowsHitTesting(nextVisible)
                .padding(.bottom, 24)
            }

            // Skip layer — present only while the intro is running. Captures
            // a tap anywhere and jumps to the final state. Removed once the
            // intro completes so it never blocks scrolling or the Next button.
            if !introComplete {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { skipIntro() }
                    .ignoresSafeArea()
            }
        }
        .task { await runIntro() }
    }

    // MARK: - Intro choreography

    @MainActor
    private func runIntro() async {
        // Reduce Motion: skip the cinematic sequence, present final state.
        if reduceMotion {
            typedCount = headingText.count
            headingSettled = true
            revealedCardCount = cardCount
            nextVisible = true
            introComplete = true
            return
        }

        func stillRunning() -> Bool { !Task.isCancelled && !skipRequested }

        // 1. A beat of stillness before anything happens.
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard stillRunning() else { return }

        // 2. Typewriter — one character at a time, soft haptic per letter.
        showCaret = true
        let chars = Array(headingText)
        for index in 1...chars.count {
            guard stillRunning() else { return }
            typedCount = index
            let character = chars[index - 1]
            if character != " " {
                AppHaptics.softImpact(intensity: 0.5)
            }
            // Slightly slower on spaces for a natural cadence + light jitter.
            let base: UInt64 = character == " " ? 92_000_000 : 60_000_000
            try? await Task.sleep(nanoseconds: base + UInt64.random(in: 0...26_000_000))
        }

        // 3. Hold so the completed line registers.
        guard stillRunning() else { return }
        try? await Task.sleep(nanoseconds: 600_000_000)

        // 4. Rise to the top with a motion-blur: blur ramps up as it starts
        //    moving, then resolves to sharp as it arrives.
        showCaret = false
        AppHaptics.mediumImpact()
        withAnimation(.easeIn(duration: 0.22)) { headingBlur = 7 }
        withAnimation(.easeInOut(duration: 0.6)) { headingSettled = true }
        try? await Task.sleep(nanoseconds: 240_000_000)
        guard stillRunning() else { return }
        withAnimation(.easeOut(duration: 0.34)) { headingBlur = 0 }
        try? await Task.sleep(nanoseconds: 320_000_000)

        // 5. Cards in, one at a time. SequentialReveal owns the spring.
        for _ in 0..<cardCount {
            guard stillRunning() else { return }
            revealedCardCount += 1
            AppHaptics.softImpact(intensity: 0.4)
            try? await Task.sleep(nanoseconds: 240_000_000)
        }

        // 6. Next button.
        guard stillRunning() else { return }
        withAnimation(.easeOut(duration: 0.4)) { nextVisible = true }
        introComplete = true
    }

    @MainActor
    private func skipIntro() {
        guard !introComplete else { return }
        skipRequested = true
        showCaret = false
        withAnimation(.easeOut(duration: 0.28)) {
            typedCount = headingText.count
            headingSettled = true
            headingBlur = 0
            revealedCardCount = cardCount
            nextVisible = true
        }
        introComplete = true
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

// MARK: - Typewriter heading

/// Types `fullText` in one character at a time (driven by `typedCount`)
/// without any layout reflow: an invisible full-text copy reserves the
/// final frame, and the visible prefix is leading-anchored within that
/// centered block — so the line types in from the left of where the
/// finished, centered heading will sit. A blinking caret rides the end.
private struct TypewriterHeading: View {
    let fullText: String
    let typedCount: Int
    let showCaret: Bool

    private var serif: Font { OnboardingTypography.instrumentSerif(style: .regular, size: 38) }

    var body: some View {
        ZStack(alignment: .leading) {
            // Invisible reservation — keeps geometry stable + centered.
            Text(fullText)
                .font(serif)
                .lineLimit(1)
                .opacity(0)

            HStack(alignment: .center, spacing: 2) {
                Text(String(fullText.prefix(typedCount)))
                    .font(serif)
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)
                    .lineLimit(1)

                CaretView()
                    .opacity(showCaret ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement()
        .accessibilityLabel(Text(fullText))
    }
}

/// Thin blinking caret for the typewriter heading.
private struct CaretView: View {
    @State private var lit = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(OnboardingGlassTheme.textPrimary)
            .frame(width: 2.5, height: 30)
            .opacity(lit ? 1 : 0)
            .onAppear {
                guard !UIAccessibility.isReduceMotionEnabled else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    lit = false
                }
            }
    }
}

// MARK: - Sequential Reveal

/// Reveals a card when `isVisible` flips true: it lifts up, sharpens from
/// a blur, and scales to full size on a spring. Driven one-at-a-time by
/// the intro choreography so the cards arrive in sequence rather than all
/// at once. Collapses to a plain show/hide under Reduce Motion.
private struct SequentialReveal: ViewModifier {
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .blur(radius: isVisible ? 0 : (reduceMotion ? 0 : 7))
            .offset(y: isVisible ? 0 : (reduceMotion ? 0 : 24))
            .scaleEffect(isVisible ? 1 : (reduceMotion ? 1 : 0.97), anchor: .top)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.84), value: isVisible)
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
                Text("Track your progress")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)

                Text("See your daily progress and trends")
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
    @State private var shimmerPhase: CGFloat = -1

    var body: some View {
        HStack(spacing: 16) {
            // Food photo with a diagonal white sweep — same vocabulary as the
            // intro photos on `OB01WelcomeScreen` so the "this is a captured
            // photo" feeling reads consistently.
            Image("food_photo_demo")
                .resizable()
                .scaledToFill()
                .frame(width: 117, height: 117)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    shimmerSweep
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(OnboardingGlassTheme.panelStroke, lineWidth: 1)
                )

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text("Take a food photo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)

                Text("Snap a picture —\nwe'll log the rest.")
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
        .onAppear { startShimmer() }
    }

    /// Diagonal top-left → bottom-right specular sweep that loops every 2.5s.
    /// Uses `.plusLighter` blend mode so the highlight *adds* brightness to
    /// the photo instead of overlaying translucent white — that way the gleam
    /// is visible even on light/bright food shots where a plain white overlay
    /// would disappear into the background.
    /// Pure decoration; fully suppressed under `accessibilityReduceMotion`.
    private var shimmerSweep: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let sweepWidth = w * 0.5

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.45), location: 0.4),
                    .init(color: .white.opacity(0.75), location: 0.5),
                    .init(color: .white.opacity(0.45), location: 0.6),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: sweepWidth)
            .offset(x: shimmerPhase * (w + sweepWidth) - sweepWidth)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }

    private func startShimmer() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: false)) {
            shimmerPhase = 1
        }
    }
}

// MARK: - Widget Shortcut Card

private struct WidgetShortcutCardView: View {
    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            widgetPreview
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Add a widget later")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)

                Text("Home Screen and Lock Screen shortcuts keep logging close.")
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
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }

    private var widgetPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.055, green: 0.060, blue: 0.085),
                            Color(red: 0.090, green: 0.075, blue: 0.125),
                            Color(red: 0.060, green: 0.085, blue: 0.115)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: OnboardingGlassTheme.accentEnd.opacity(glow ? 0.34 : 0.12), radius: glow ? 18 : 8, y: 8)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("842")
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("cal")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

                Capsule()
                    .fill(.white.opacity(0.16))
                    .frame(height: 5)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [OnboardingGlassTheme.accentStart, OnboardingGlassTheme.accentEnd],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 56, height: 5)
                    }

                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                    Image(systemName: "mic.fill")
                }
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(12)
        }
        .frame(width: 117, height: 117)
    }
}

// MARK: - Floating Drift modifier

/// Subtly drifts a view via sin-wave-driven offset + rotation. Used to
/// signal "this is a display element floating in space" rather than
/// "this is a tappable settings row" — testers were tapping the
/// feature cards in onboarding expecting them to do something. Each
/// card gets a different `phaseSeed` so they don't drift in sync.
///
/// Drift amplitudes are intentionally tiny (±1.5pt translate, ±0.4°
/// rotate) — enough to read as motion, small enough that content stays
/// stable to read. Respects `accessibilityReduceMotion`.
private struct FloatingDrift: ViewModifier {
    let phaseSeed: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let twoPi = Double.pi * 2
                let dx = sin(t * 0.40 + phaseSeed * twoPi)        * 1.5
                let dy = sin(t * 0.32 + phaseSeed * twoPi * 1.5)  * 1.5
                let rotation = sin(t * 0.22 + phaseSeed * twoPi)  * 0.4

                content
                    .offset(x: dx, y: dy)
                    .rotationEffect(.degrees(rotation))
            }
        }
    }
}

// MARK: - Curated Recipes Card

/// Fifth feature card (added 2026-05-24). Positions the recipe feature
/// as "we did the curation work" rather than "we dump 10,000 random
/// recipes on you" — the differentiator vs. competitors. Shows a
/// stylized recipe preview tile on the left with macros + a
/// "Fits your targets" chip; title + subtitle on the right.
private struct CuratedRecipesCardView: View {
    @State private var checkPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            recipePreview
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Recipes worth your goals")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)

                Text("Hand-picked meals that hit your targets — no endless scrolling.")
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
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                checkPulse = true
            }
        }
    }

    /// Compact recipe preview — circular dish illustration at top, name,
    /// macros, and a "Fits your targets" check chip at the bottom. Same
    /// 117pt square footprint as the other cards' left panels.
    private var recipePreview: some View {
        let accent = LinearGradient(
            colors: [OnboardingGlassTheme.accentStart, OnboardingGlassTheme.accentEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return ZStack {
            // Outer card chrome — matches widget preview style
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.94, blue: 0.84),
                            Color(red: 1.00, green: 0.88, blue: 0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(OnboardingGlassTheme.panelStroke, lineWidth: 1)
                )

            VStack(spacing: 6) {
                // Dish illustration: stacked circles signaling a bowl
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 38, height: 38)
                    Circle()
                        .fill(.white.opacity(0.85))
                        .frame(width: 28, height: 28)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(accent)
                }

                Text("Greek bowl")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.30, green: 0.18, blue: 0.08))
                    .lineLimit(1)

                Text("320 cal · 22g P")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.42, green: 0.30, blue: 0.18))
                    .monospacedDigit()

                // "Fits your targets" check chip — gently pulses to draw
                // attention to the curated/personalized angle
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Fits")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.30))
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.85, green: 0.95, blue: 0.88))
                )
                .scaleEffect(checkPulse ? 1.06 : 1.0)
            }
            .padding(12)
        }
        .frame(width: 117, height: 117)
    }
}
