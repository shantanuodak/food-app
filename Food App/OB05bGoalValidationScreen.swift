import SwiftUI

struct OB05bGoalValidationScreen: View {
    let draft: OnboardingDraft
    let metrics: OnboardingMetrics
    let onBack: () -> Void
    let onContinue: () -> Void
    var onAdjustPlan: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var cardVisible = false
    @State private var metricsVisible = false
    @State private var glowShift = false
    @State private var kcalAnimatedValue: Double = 0

    private var paceWeeks: Int {
        switch draft.pace ?? .balanced {
        case .conservative: return 16
        case .balanced: return 12
        case .aggressive: return 8
        }
    }

    private var weightUnit: String {
        (draft.units ?? .imperial) == .metric ? "kg" : "lbs"
    }

    private var currentWeight: String {
        "\(Int(draft.weightValue)) \(weightUnit)"
    }

    private var paceLabel: String {
        switch draft.pace ?? .balanced {
        case .conservative: return "Conservative pace"
        case .balanced: return "Balanced pace"
        case .aggressive: return "Aggressive pace"
        }
    }

    private var goalWeightDisplay: String? {
        guard let goal = draft.goal, goal != .maintain,
              let lbsPerWeek = OnboardingCalculator.weeklyRateLbs(for: goal, pace: draft.pace) else {
            return nil
        }
        let totalLbsDelta = lbsPerWeek * Double(paceWeeks)
        let direction: Double = goal == .lose ? -1.0 : 1.0

        let deltaInUserUnit: Double
        switch draft.units ?? .imperial {
        case .metric: deltaInUserUnit = totalLbsDelta * 0.453592
        case .imperial: deltaInUserUnit = totalLbsDelta
        }

        let goalValue = draft.weightValue + direction * deltaInUserUnit
        return "\(Int(goalValue.rounded())) \(weightUnit)"
    }

    private var goalLabel: String {
        goalWeightDisplay ?? "Maintain"
    }

    private var timelineCaption: String? {
        let dateAvailable = !metrics.projectedGoalDate.isEmpty
        let weeksAvailable = goalWeightDisplay != nil
        switch (dateAvailable, weeksAvailable) {
        case (true, true):
            return "\(paceLabel)  ·  \(metrics.projectedGoalDate)"
        case (true, false):
            return metrics.projectedGoalDate
        case (false, true):
            return "\(paceWeeks) weeks"
        case (false, false):
            return nil
        }
    }

    var body: some View {
        ZStack {
            GoalValidationBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 18)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 34) {
                        heroBlock
                            .padding(.top, 14)
                            .padding(.horizontal, 24)

                        planCard
                            .padding(.horizontal, 18)
                    }
                    .padding(.bottom, 28)
                }

                actionButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            runEntranceAnimation()
        }
    }

    private var topBar: some View {
        ZStack {
            Text("Plan preview")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(GoalValidationPalette.secondaryInk)
                .tracking(1.0)
                .textCase(.uppercase)

            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GoalValidationPalette.ink)
                        .frame(width: 46, height: 46)
                        .background(GoalValidationPalette.controlFill, in: Circle())
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(GoalValidationPalette.controlStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .frame(height: 46)
    }

    private var heroBlock: some View {
        VStack(spacing: 10) {
            Text("Your plan,\n\(Text("tuned to start").font(OnboardingTypography.instrumentSerif(style: .italic, size: 42)))")
                .font(OnboardingTypography.instrumentSerif(style: .regular, size: 42))
                .foregroundStyle(GoalValidationPalette.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Text("One quick look before we take you into logging.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(GoalValidationPalette.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.easeOut(duration: 0.45), value: appeared)
    }

    private var planCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(GoalValidationPalette.cardBackA)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(GoalValidationPalette.cardStrokeSoft, lineWidth: 1)
                )
                .frame(width: 284, height: 246)
                .rotationEffect(.degrees(-7))
                .offset(x: -4, y: 18)

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(GoalValidationPalette.cardBackB)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(GoalValidationPalette.cardStrokeSoft, lineWidth: 1)
                )
                .frame(width: 302, height: 270)
                .rotationEffect(.degrees(6))
                .offset(x: 6, y: 6)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    planTopColumn(title: "Today", value: currentWeight)
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Direction")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.0)
                            .textCase(.uppercase)
                            .foregroundStyle(GoalValidationPalette.mutedInk)
                        Text(goalLabel)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(GoalValidationPalette.ink)
                    }
                }

                timelineBeam
                    .padding(.top, 18)

                if let timelineCaption {
                    Text(timelineCaption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GoalValidationPalette.secondaryInk)
                        .padding(.top, 12)
                }

                Rectangle()
                    .fill(GoalValidationPalette.divider)
                    .frame(height: 1)
                    .padding(.top, 20)

                Text("Daily target")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(GoalValidationPalette.mutedInk)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange, GoalValidationPalette.accentWarm],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: GoalValidationPalette.accentWarm.opacity(0.28), radius: 16, y: 6)

                    RollingNumberText(value: kcalAnimatedValue, fractionDigits: 0)
                        .font(OnboardingTypography.instrumentSerif(style: .regular, size: 58))
                        .foregroundStyle(GoalValidationPalette.ink)

                    Text("kcal")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(GoalValidationPalette.secondaryInk)
                        .offset(y: -6)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Daily target \(metrics.targetKcal) kilocalories"))

                HStack(spacing: 10) {
                    macroCard(
                        icon: "bolt.fill",
                        value: metrics.proteinTarget,
                        label: "Protein",
                        color: GoalValidationPalette.protein,
                        index: 0
                    )
                    macroCard(
                        icon: "leaf.fill",
                        value: metrics.carbTarget,
                        label: "Carbs",
                        color: GoalValidationPalette.carbs,
                        index: 1
                    )
                    macroCard(
                        icon: "drop.fill",
                        value: metrics.fatTarget,
                        label: "Fat",
                        color: GoalValidationPalette.fat,
                        index: 2
                    )
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoalValidationPalette.cardFront)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [.clear, GoalValidationPalette.shine, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 84)
                .rotationEffect(.degrees(18))
                .offset(x: glowShift ? 330 : -120)
                .blendMode(.screen)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(GoalValidationPalette.cardStrokeStrong, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 28, y: 16)
        }
        .frame(height: 368)
        .opacity(cardVisible ? 1 : 0)
        .offset(y: cardVisible ? 0 : 16)
        .animation(.easeOut(duration: 0.55).delay(0.12), value: cardVisible)
    }

    private func planTopColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(GoalValidationPalette.mutedInk)
            Text(value)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(GoalValidationPalette.ink)
        }
    }

    private var timelineBeam: some View {
        Capsule()
            .fill(GoalValidationPalette.beamTrack)
            .frame(height: 10)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                GoalValidationPalette.accentGold,
                                GoalValidationPalette.accentWarm,
                                GoalValidationPalette.accentMint
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.65),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 110)
                    .offset(x: glowShift ? 280 : -120)
                    .clipShape(Capsule())
            }
    }

    private func macroCard(icon: String, value: Int, label: String, color: Color, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)

            Text("\(value)g")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(GoalValidationPalette.ink)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GoalValidationPalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(GoalValidationPalette.metricFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(GoalValidationPalette.metricStroke, lineWidth: 1)
        )
        .opacity(metricsVisible ? 1 : 0)
        .offset(y: metricsVisible ? 0 : 8)
        .animation(
            reduceMotion ? .none : .easeOut(duration: 0.42).delay(Double(index) * 0.08),
            value: metricsVisible
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label): \(value) grams"))
    }

    private var actionButtons: some View {
        VStack(spacing: 14) {
            Button(action: onContinue) {
                HStack(spacing: 8) {
                    Text("Next")
                        .font(.system(size: 17, weight: .bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(GoalValidationPalette.ctaInk)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(
                    LinearGradient(
                        colors: [GoalValidationPalette.ctaTop, GoalValidationPalette.ctaBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(GoalValidationPalette.ctaStroke, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.20), radius: 24, y: 12)
            }
            .buttonStyle(.plain)

            if let onAdjustPlan {
                Button(action: onAdjustPlan) {
                    Text("Adjust plan")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GoalValidationPalette.secondaryInk)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func runEntranceAnimation() {
        if reduceMotion {
            appeared = true
            cardVisible = true
            metricsVisible = true
            glowShift = true
            kcalAnimatedValue = Double(metrics.targetKcal)
            return
        }

        withAnimation(.easeOut(duration: 0.45)) {
            appeared = true
        }
        withAnimation(.easeOut(duration: 0.55).delay(0.12)) {
            cardVisible = true
        }
        withAnimation(.spring(response: 0.72, dampingFraction: 0.86).delay(0.34)) {
            kcalAnimatedValue = Double(metrics.targetKcal)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            metricsVisible = true
        }
        withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: false)) {
            glowShift = true
        }
    }
}

private struct GoalValidationBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    GoalValidationPalette.backgroundTop,
                    GoalValidationPalette.backgroundBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(GoalValidationPalette.glowWarm)
                .frame(width: 260, height: 260)
                .blur(radius: 26)
                .offset(x: animate ? 122 : 104, y: animate ? -282 : -250)

            Circle()
                .fill(GoalValidationPalette.glowMint)
                .frame(width: 240, height: 240)
                .blur(radius: 30)
                .offset(x: animate ? -126 : -98, y: animate ? 260 : 288)

            Circle()
                .fill(GoalValidationPalette.glowSoft)
                .frame(width: 200, height: 200)
                .blur(radius: 24)
                .offset(x: animate ? -84 : -62, y: animate ? -126 : -104)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

private enum GoalValidationPalette {
    static let ink = adaptiveColor(
        light: UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0),
        dark: UIColor(white: 0.96, alpha: 1.0)
    )
    static let secondaryInk = adaptiveColor(
        light: UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 0.76),
        dark: UIColor(white: 0.92, alpha: 0.74)
    )
    static let mutedInk = adaptiveColor(
        light: UIColor(red: 0.38, green: 0.38, blue: 0.40, alpha: 0.58),
        dark: UIColor(white: 0.88, alpha: 0.52)
    )
    static let accentInk = adaptiveColor(
        light: UIColor(red: 0.86, green: 0.42, blue: 0.12, alpha: 1.0),
        dark: UIColor(red: 0.98, green: 0.75, blue: 0.53, alpha: 1.0)
    )
    static let backgroundTop = adaptiveColor(
        light: UIColor.white,
        dark: UIColor(red: 0.06, green: 0.05, blue: 0.04, alpha: 1.0)
    )
    static let backgroundBottom = adaptiveColor(
        light: UIColor.white,
        dark: UIColor(red: 0.10, green: 0.08, blue: 0.07, alpha: 1.0)
    )
    static let glowWarm = adaptiveColor(
        light: UIColor(red: 1.0, green: 0.50, blue: 0.20, alpha: 0.10),
        dark: UIColor(red: 1.0, green: 0.54, blue: 0.26, alpha: 0.22)
    )
    static let glowMint = adaptiveColor(
        light: UIColor(red: 0.26, green: 0.78, blue: 0.62, alpha: 0.08),
        dark: UIColor(red: 0.42, green: 0.86, blue: 0.74, alpha: 0.14)
    )
    static let glowSoft = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.025),
        dark: UIColor(white: 1.0, alpha: 0.08)
    )
    static let controlFill = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.86),
        dark: UIColor(white: 1.0, alpha: 0.09)
    )
    static let controlStroke = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.07),
        dark: UIColor(white: 1.0, alpha: 0.14)
    )
    static let badgeFill = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.84),
        dark: UIColor(white: 1.0, alpha: 0.09)
    )
    static let badgeStroke = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.06),
        dark: UIColor(white: 1.0, alpha: 0.16)
    )
    static let cardBackA = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.38),
        dark: UIColor(white: 1.0, alpha: 0.04)
    )
    static let cardBackB = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.46),
        dark: UIColor(white: 1.0, alpha: 0.06)
    )
    static let cardFront = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.80),
        dark: UIColor(red: 0.19, green: 0.16, blue: 0.14, alpha: 0.84)
    )
    static let cardStrokeStrong = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.07),
        dark: UIColor(white: 1.0, alpha: 0.14)
    )
    static let cardStrokeSoft = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.045),
        dark: UIColor(white: 1.0, alpha: 0.08)
    )
    static let beamTrack = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.08),
        dark: UIColor(white: 1.0, alpha: 0.08)
    )
    static let divider = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.075),
        dark: UIColor(white: 1.0, alpha: 0.08)
    )
    static let metricFill = adaptiveColor(
        light: UIColor(white: 0.96, alpha: 0.76),
        dark: UIColor(white: 1.0, alpha: 0.06)
    )
    static let metricStroke = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 0.055),
        dark: UIColor(white: 1.0, alpha: 0.10)
    )
    static let ctaTop = adaptiveColor(
        light: UIColor(white: 0.06, alpha: 1.0),
        dark: UIColor(red: 0.98, green: 0.95, blue: 0.92, alpha: 0.96)
    )
    static let ctaBottom = adaptiveColor(
        light: UIColor(white: 0.0, alpha: 1.0),
        dark: UIColor(red: 0.92, green: 0.87, blue: 0.82, alpha: 0.94)
    )
    static let ctaInk = adaptiveColor(
        light: UIColor.white,
        dark: UIColor(red: 0.10, green: 0.08, blue: 0.07, alpha: 1.0)
    )
    static let ctaStroke = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.10),
        dark: UIColor(white: 1.0, alpha: 0.30)
    )
    static let shine = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.56),
        dark: UIColor(white: 1.0, alpha: 0.12)
    )
    static let accentGold = Color(red: 1.0, green: 0.70, blue: 0.30)
    static let accentWarm = Color(red: 1.0, green: 0.56, blue: 0.30)
    static let accentMint = Color(red: 0.40, green: 0.88, blue: 0.76)
    static let protein = Color(red: 0.52, green: 0.47, blue: 1.0)
    static let carbs = Color(red: 0.35, green: 0.84, blue: 0.48)
    static let fat = Color(red: 0.29, green: 0.66, blue: 1.0)

    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
