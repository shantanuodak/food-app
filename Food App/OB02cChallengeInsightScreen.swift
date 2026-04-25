import SwiftUI

struct OB02cChallengeInsightScreen: View {
    let challenge: ChallengeChoice
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var helpVisible = false
    @State private var shimmerPhase: CGFloat = -1

    private let teal = Color(red: 0.18, green: 0.56, blue: 0.42)

    private var content: (headline: String, insight: String, help: String) {
        switch challenge {
        case .portionControl:
            return (
                headline: "Portions are tricky.\nWe make them obvious.",
                insight: "Studies show people underestimate calories by up to 50% — even nutritionists get it wrong.",
                help: "Just type what you ate — we'll show the real calorie count in seconds."
            )
        case .snacking:
            return (
                headline: "Night cravings?\nWe'll be your wingman.",
                insight: "Late-night snacking accounts for 25% of excess daily calories for most people.",
                help: "We nudge you right before your danger zone — so you stay in control."
            )
        case .eatingOut:
            return (
                headline: "Eat out freely.\nWe'll do the math.",
                insight: "A single restaurant meal can pack 1,200+ calories — and the menu won't tell you.",
                help: "Snap a photo or type your order — we'll break it down instantly."
            )
        case .inconsistentMeals:
            return (
                headline: "Skipped meals?\nWe'll keep you on track.",
                insight: "Irregular eating throws off hunger hormones, leading to 40% more overeating at your next meal.",
                help: "We spot gaps and gently nudge you — effortless consistency over time."
            )
        case .emotionalEating:
            return (
                headline: "It's not about willpower.\nIt's about awareness.",
                insight: "Research shows that a 60-second pause before eating reduces emotional binges by over 50%.",
                help: "Just open the app — that one moment creates a mindful pause."
            )
        }
    }

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                Spacer()

                // Headline
                Text(content.headline)
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 41))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .padding(.horizontal, 24)

                // Insight — simple muted text
                Text(content.insight)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 16)
                    .padding(.horizontal, 32)
                    .opacity(appeared ? 1 : 0)

                Spacer()

                // Demo card — visual demo for portion control, refined text for others
                demoCard
                    .padding(.horizontal, 16)
                    .opacity(helpVisible ? 1 : 0)
                    .offset(y: helpVisible ? 0 : 24)

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
            withAnimation(.easeOut(duration: 0.6).delay(0.5)) {
                helpVisible = true
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 1
            }
        }
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

    // MARK: - Demo Card (dispatcher)

    /// Returns a challenge-specific visual demo. Each challenge has its own
    /// animated card tuned to demonstrate the product's response to that
    /// specific struggle.
    @ViewBuilder
    private var demoCard: some View {
        switch challenge {
        case .portionControl:
            portionControlDemoCard
        case .snacking:
            SnackingNudgeDemoCard()
        case .eatingOut:
            EatingOutPlateDemoCard()
        case .inconsistentMeals:
            InconsistentMealsTimelineDemoCard()
        case .emotionalEating:
            EmotionalEatingBreathingDemoCard()
        }
    }

    /// Animated typing demo wrapped in a blue gradient card. Mirrors the
    /// `typingCard` visual language from OB02eHowItWorksScreen.
    private var portionControlDemoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            DemoCardHeader()
                .padding(.horizontal, 20)
                .padding(.top, 20)

            // Animated typing demo — "a bowl of pasta" → calorie reveal
            LoggingDemoAnimation()
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            demoCardGradient(
                stops: [
                    (Color(red: 0.56, green: 0.71, blue: 0.83), 0),
                    (Color(red: 0.44, green: 0.62, blue: 0.81), 0.25),
                    (Color(red: 0.33, green: 0.53, blue: 0.78), 0.5),
                    (Color(red: 0.20, green: 0.45, blue: 0.76), 0.75),
                    (Color(red: 0.09, green: 0.36, blue: 0.74), 1.0)
                ]
            )
        )
    }

    // MARK: - Help Card

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with shimmer
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(teal)

                Text("This is how we help")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(teal)
                    .textCase(.uppercase)
                    .tracking(1)
            }
            .overlay(helpShimmer)
            .compositingGroup()

            Text(content.help)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(teal.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(teal.opacity(0.12), lineWidth: 1)
                )
        )
    }

    // MARK: - Shimmer

    private var helpShimmer: some View {
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
            .offset(x: shimmerPhase * (w + sweepWidth) - sweepWidth)
            .blendMode(.sourceAtop)
        }
    }
}

// MARK: - Shared Demo Card Helpers

/// Shared header shown at the top of every challenge demo card.
/// Displays the "sparkles · THIS IS HOW WE HELP" row in white.
private struct DemoCardHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            Text("This is how we help")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .textCase(.uppercase)
                .tracking(1)
        }
    }
}

/// Builds a radial gradient background matching the challenge demo style.
/// Use with rounded corners (cornerRadius 24) and a colored shadow.
private func demoCardGradient(stops: [(Color, Double)]) -> some View {
    RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(
            RadialGradient(
                gradient: Gradient(stops: stops.map { Gradient.Stop(color: $0.0, location: $0.1) }),
                center: UnitPoint(x: 0.23, y: 0.52),
                startRadius: 0,
                endRadius: 320
            )
        )
        .shadow(color: .black.opacity(0.25), radius: 21.5, x: 0, y: 4)
}

/// Builds a simpler two-tone gradient from a single accent color — used for
/// the 4 new Phase 2 demos so each challenge card feels distinct but on-theme.
private func accentDemoCardGradient(_ accent: Color) -> some View {
    RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(
            RadialGradient(
                colors: [
                    accent,
                    accent.opacity(0.85),
                    accent.opacity(0.7)
                ],
                center: UnitPoint(x: 0.25, y: 0.4),
                startRadius: 0,
                endRadius: 320
            )
        )
        .shadow(color: accent.opacity(0.35), radius: 20, x: 0, y: 6)
}

// MARK: - Snacking: Smart Nudge Notification

/// Shows a friendly iOS-style notification sliding down inside the card,
/// demonstrating the "smart nudge before your danger zone" promise.
private struct SnackingNudgeDemoCard: View {
    private let accent = Color(red: 0.55, green: 0.40, blue: 0.85)

    @State private var notificationVisible = false
    @State private var notificationPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DemoCardHeader()
                .padding(.horizontal, 20)
                .padding(.top, 20)

            ZStack {
                // Faint phone-screen backdrop
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .frame(height: 124)

                notificationCard
                    .padding(.horizontal, 12)
                    .offset(y: notificationVisible ? 0 : -60)
                    .opacity(notificationVisible ? 1 : 0)
                    .scaleEffect(notificationPulse ? 1.02 : 1.0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accentDemoCardGradient(accent))
        .onAppear { runLoop() }
    }

    private var notificationCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.25))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Food App")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("9:42 PM")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Text("1,450 / 1,800 cal today.")
                    .font(.system(size: 13, weight: .medium))

                Text("A handful of almonds (160) fits great.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func runLoop() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                    notificationVisible = true
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(.easeInOut(duration: 0.35)) {
                    notificationPulse = true
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation(.easeInOut(duration: 0.35)) {
                    notificationPulse = false
                }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(.easeInOut(duration: 0.4)) {
                    notificationVisible = false
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }
}

// MARK: - Eating Out: Plate → Breakdown

/// Plate with three colored food dots, then three calorie chips pop in
/// sequentially to show "one photo → instant breakdown".
private struct EatingOutPlateDemoCard: View {
    private let accent = Color(red: 0.90, green: 0.35, blue: 0.35)

    @State private var plateVisible = false
    @State private var chipsVisible: [Bool] = [false, false, false]

    private let chips: [(emoji: String, label: String, cal: String)] = [
        ("🍚", "Rice", "220 cal"),
        ("🍗", "Chicken", "310 cal"),
        ("🥗", "Veg", "80 cal")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DemoCardHeader()
                .padding(.horizontal, 20)
                .padding(.top, 20)

            HStack(spacing: 16) {
                // Plate illustration
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 90, height: 90)
                    Circle()
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                        .frame(width: 90, height: 90)

                    // Three food dots
                    Circle()
                        .fill(Color(red: 1.0, green: 0.82, blue: 0.40))
                        .frame(width: 26, height: 26)
                        .offset(x: -18, y: -10)

                    Circle()
                        .fill(Color(red: 0.85, green: 0.60, blue: 0.40))
                        .frame(width: 30, height: 30)
                        .offset(x: 16, y: -6)

                    Circle()
                        .fill(Color(red: 0.45, green: 0.78, blue: 0.45))
                        .frame(width: 22, height: 22)
                        .offset(x: 0, y: 18)
                }
                .scaleEffect(plateVisible ? 1 : 0.88)
                .opacity(plateVisible ? 1 : 0)

                // Calorie chips stacked on the right
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                        chipView(chip)
                            .opacity(chipsVisible[index] ? 1 : 0)
                            .scaleEffect(chipsVisible[index] ? 1 : 0.85)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accentDemoCardGradient(accent))
        .onAppear { runLoop() }
    }

    private func chipView(_ chip: (emoji: String, label: String, cal: String)) -> some View {
        HStack(spacing: 6) {
            Text(chip.emoji).font(.system(size: 13))
            Text(chip.label)
                .font(.system(size: 12, weight: .semibold))
            Text("·").foregroundStyle(.white.opacity(0.6))
            Text(chip.cal)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(.white.opacity(0.18))
        )
    }

    private func runLoop() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    plateVisible = true
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
                for i in 0..<chipsVisible.count {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        chipsVisible[i] = true
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(.easeInOut(duration: 0.4)) {
                    plateVisible = false
                    chipsVisible = [false, false, false]
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }
}

// MARK: - Inconsistent Meals: Day Timeline with Gap-fill

/// A horizontal timeline representing a day. Meal dots appear for breakfast
/// and dinner, a gap pulses at lunch, then a nudge appears and the lunch dot
/// fills in — demonstrating "we spot gaps and gently nudge".
private struct InconsistentMealsTimelineDemoCard: View {
    private let accent = Color(red: 0.20, green: 0.65, blue: 0.85)

    @State private var timelineProgress: CGFloat = 0
    @State private var breakfastVisible = false
    @State private var dinnerVisible = false
    @State private var gapPulse = false
    @State private var nudgeVisible = false
    @State private var lunchVisible = false

    // Dot positions as fractions along the timeline
    private let breakfastX: CGFloat = 0.15
    private let lunchX: CGFloat = 0.5
    private let dinnerX: CGFloat = 0.82

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DemoCardHeader()
                .padding(.horizontal, 20)
                .padding(.top, 20)

            GeometryReader { geo in
                let w = geo.size.width
                let lineY: CGFloat = 40

                ZStack(alignment: .topLeading) {
                    // Base timeline (full length, faint)
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(width: w, height: 3)
                        .offset(y: lineY)

                    // Animated timeline fill
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: w * timelineProgress, height: 3)
                        .offset(y: lineY)

                    // Breakfast dot
                    mealDot(visible: breakfastVisible, label: "Breakfast")
                        .offset(x: w * breakfastX - 6, y: lineY - 6)

                    // Lunch gap pulse (only visible before lunch dot fills)
                    if !lunchVisible {
                        Circle()
                            .stroke(Color(red: 1.0, green: 0.80, blue: 0.30), lineWidth: 2)
                            .frame(width: 22, height: 22)
                            .scaleEffect(gapPulse ? 1.25 : 0.9)
                            .opacity(gapPulse ? 0.0 : 0.85)
                            .offset(x: w * lunchX - 11, y: lineY - 11)
                    }

                    // Lunch dot (fills in at the end)
                    mealDot(visible: lunchVisible, label: "Lunch")
                        .offset(x: w * lunchX - 6, y: lineY - 6)

                    // Dinner dot
                    mealDot(visible: dinnerVisible, label: "Dinner")
                        .offset(x: w * dinnerX - 6, y: lineY - 6)

                    // Nudge bubble above lunch
                    if nudgeVisible {
                        nudgeBubble
                            .offset(x: w * lunchX - 50, y: -6)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(height: 78)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accentDemoCardGradient(accent))
        .onAppear { runLoop() }
    }

    private func mealDot(visible: Bool, label: String) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(.white)
                .frame(width: 12, height: 12)
                .scaleEffect(visible ? 1 : 0)
                .opacity(visible ? 1 : 0)
            if visible {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .transition(.opacity)
            }
        }
    }

    private var nudgeBubble: some View {
        Text("Lunch time? 🍴")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(.white)
            )
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    private func runLoop() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)

                // Draw timeline
                withAnimation(.easeOut(duration: 0.8)) {
                    timelineProgress = 1
                }
                try? await Task.sleep(nanoseconds: 500_000_000)

                // Breakfast appears
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    breakfastVisible = true
                }
                try? await Task.sleep(nanoseconds: 400_000_000)

                // Dinner appears (skipping lunch)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    dinnerVisible = true
                }
                try? await Task.sleep(nanoseconds: 500_000_000)

                // Gap pulses 3 times
                for _ in 0..<3 {
                    withAnimation(.easeOut(duration: 0.6)) {
                        gapPulse = true
                    }
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    gapPulse = false
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }

                // Nudge appears
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                    nudgeVisible = true
                }
                try? await Task.sleep(nanoseconds: 700_000_000)

                // Lunch fills in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                    lunchVisible = true
                    nudgeVisible = false
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                // Reset for loop
                withAnimation(.easeInOut(duration: 0.4)) {
                    timelineProgress = 0
                    breakfastVisible = false
                    dinnerVisible = false
                    lunchVisible = false
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }
}

// MARK: - Emotional Eating: Breathing Pause

/// A breathing circle with a countdown from 60. The circle expands and
/// contracts with ease-in-out, mimicking inhale/exhale. Users literally
/// take a mindful pause while watching.
private struct EmotionalEatingBreathingDemoCard: View {
    private let accent = Color(red: 0.85, green: 0.40, blue: 0.60)

    @State private var breathing = false
    @State private var count: Int = 60
    @State private var countdownTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DemoCardHeader()
                .padding(.horizontal, 20)
                .padding(.top, 20)

            VStack(spacing: 12) {
                ZStack {
                    // Outer soft ring
                    Circle()
                        .stroke(.white.opacity(0.25), lineWidth: 8)
                        .frame(width: 110, height: 110)
                        .scaleEffect(breathing ? 1.08 : 0.88)

                    // Inner solid circle
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 92, height: 92)
                        .scaleEffect(breathing ? 1.05 : 0.9)

                    VStack(spacing: 2) {
                        Text("Pause")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .textCase(.uppercase)
                            .tracking(1.2)
                        Text("\(count)s")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                }
                .frame(height: 130)

                Text("Breathe. What does your body actually need?")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accentDemoCardGradient(accent))
        .onAppear { startBreathingLoop() }
        .onDisappear { countdownTask?.cancel() }
    }

    private func startBreathingLoop() {
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            breathing = true
        }
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            while !Task.isCancelled {
                // Decrement every second until ~48, then reset
                for _ in 0..<12 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        count = max(0, count - 1)
                    }
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    count = 60
                }
            }
        }
    }
}
