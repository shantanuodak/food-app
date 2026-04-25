import SwiftUI

struct OB05bGoalValidationScreen: View {
    let draft: OnboardingDraft
    let metrics: OnboardingMetrics
    let onBack: () -> Void
    let onContinue: () -> Void
    var onAdjustPlan: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var pathProgress: CGFloat = 0
    @State private var checkmarkScale: CGFloat = 0

    private var paceWeeks: Int {
        switch draft.pace ?? .balanced {
        case .conservative: return 16
        case .balanced: return 12
        case .aggressive: return 8
        }
    }

    private var paceLabel: String {
        (draft.pace ?? .balanced).title.lowercased()
    }

    private var weightUnit: String {
        (draft.units ?? .imperial) == .metric ? "kg" : "lbs"
    }

    private var currentWeight: String {
        "\(Int(draft.weightValue)) \(weightUnit)"
    }

    private var goalDirection: String {
        switch draft.goal {
        case .lose: return "lose weight"
        case .gain: return "gain muscle"
        case .maintain: return "maintain weight"
        case .none: return "reach your goal"
        }
    }

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Headline
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(red: 0.20, green: 0.83, blue: 0.60), Color(red: 0.10, green: 0.70, blue: 0.50)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .scaleEffect(checkmarkScale)

                            Text("Your plan is ready")
                                .font(OnboardingTypography.instrumentSerif(style: .regular, size: 38))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                                .multilineTextAlignment(.center)

                            Text("Based on your profile, here's your starting target.")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 36)
                        .padding(.horizontal, 20)
                        .opacity(appeared ? 1 : 0)

                        // Journey Timeline Card
                        journeyCard
                            .padding(.top, 32)
                            .padding(.horizontal, 16)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)

                        // Daily Target Card
                        dailyTargetCard
                            .padding(.top, 16)
                            .padding(.horizontal, 16)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)

                        // Macro Distribution Card
                        macroDistributionCard
                            .padding(.top, 16)
                            .padding(.horizontal, 16)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                    }
                    .padding(.bottom, 24)
                }

                VStack(spacing: 10) {
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

                    if let onAdjustPlan {
                        Button(action: onAdjustPlan) {
                            Text("Adjust plan")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5).delay(0.3)) {
                checkmarkScale = 1.0
            }
            withAnimation(.easeInOut(duration: 1.2).delay(0.5)) {
                pathProgress = 1.0
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        ZStack {
            Text("Your Plan")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

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

    // MARK: - Journey Card

    private var journeyCard: some View {
        VStack(spacing: 20) {
            // Weight labels
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(OnboardingGlassTheme.textMuted)
                    Text(currentWeight)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OnboardingGlassTheme.textMuted)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("GOAL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(OnboardingGlassTheme.textMuted)
                    Text("\(paceWeeks) weeks")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(red: 0.20, green: 0.83, blue: 0.60))
                }
            }

            // Animated progress path
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(OnboardingGlassTheme.panelStroke)
                        .frame(height: 6)

                    // Filled progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.20, green: 0.83, blue: 0.60),
                                    Color(red: 0.10, green: 0.70, blue: 0.85)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * pathProgress, height: 6)

                    // Milestone dots
                    HStack {
                        timelineDot(filled: pathProgress > 0)
                        Spacer()
                        timelineDot(filled: pathProgress > 0.5)
                        Spacer()
                        timelineDot(filled: pathProgress >= 1.0)
                    }
                }
            }
            .frame(height: 20)

            // Timeline labels
            HStack {
                Text("Start")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(OnboardingGlassTheme.textMuted)
                Spacer()
                Text("Midpoint")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(OnboardingGlassTheme.textMuted)
                Spacer()
                Text("Target")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.20, green: 0.83, blue: 0.60))
            }

            // Projected date
            if !metrics.projectedGoalDate.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13))
                        .foregroundStyle(OnboardingGlassTheme.textMuted)
                    Text("Projected: \(metrics.projectedGoalDate)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OnboardingGlassTheme.textSecondary)
                }
            }
        }
        .padding(20)
        .onboardingGlassPanel(cornerRadius: 22, fillOpacity: 0.06, strokeOpacity: 0.12)
    }

    private func timelineDot(filled: Bool) -> some View {
        Circle()
            .fill(filled
                ? Color(red: 0.20, green: 0.83, blue: 0.60)
                : OnboardingGlassTheme.panelStroke
            )
            .frame(width: 14, height: 14)
            .overlay(
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                    .opacity(filled ? 1 : 0)
            )
            .scaleEffect(filled ? 1.0 : 0.8)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: filled)
    }

    // MARK: - Daily Target Card

    private var dailyTargetCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "flame.fill")
                .font(.system(size: 28))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Your daily target")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Text("\(metrics.targetKcal) kcal/day — with \(metrics.proteinTarget)g protein, \(metrics.carbTarget)g carbs, \(metrics.fatTarget)g fat.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .onboardingGlassPanel(cornerRadius: 18, fillOpacity: 0.06, strokeOpacity: 0.12)
    }

    // MARK: - Macro Distribution Card

    private var macroSlices: [GoalValidationMacroSlice] {
        [
            GoalValidationMacroSlice(
                name: "Protein",
                grams: metrics.proteinTarget,
                caloriesPerGram: 4,
                startColor: Color(red: 0.34, green: 0.56, blue: 1.00),
                endColor: Color(red: 0.60, green: 0.41, blue: 1.00)
            ),
            GoalValidationMacroSlice(
                name: "Carbs",
                grams: metrics.carbTarget,
                caloriesPerGram: 4,
                startColor: Color(red: 0.20, green: 0.90, blue: 0.62),
                endColor: Color(red: 0.71, green: 0.94, blue: 0.35)
            ),
            GoalValidationMacroSlice(
                name: "Fat",
                grams: metrics.fatTarget,
                caloriesPerGram: 9,
                startColor: Color(red: 1.00, green: 0.61, blue: 0.26),
                endColor: Color(red: 1.00, green: 0.37, blue: 0.41)
            )
        ]
        .filter { $0.grams > 0 }
    }

    private var totalMacroCalories: Double {
        macroSlices.reduce(0) { $0 + $1.calories }
    }

    private var macroDistributionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(OnboardingGlassTheme.textPrimary.opacity(0.95))
                    .frame(width: 7, height: 7)
                Text("MACRO DISTRIBUTION")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary.opacity(0.9))
            }

            HStack(alignment: .center, spacing: 14) {
                GoalValidationDonutChart(
                    slices: macroSlices,
                    totalCalories: totalMacroCalories
                )
                .frame(width: 126, height: 126)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(macroSlices) { slice in
                        GoalValidationMacroLegendRow(
                            slice: slice,
                            totalCalories: totalMacroCalories
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .onboardingGlassPanel(
            cornerRadius: OnboardingGlassMetrics.cornerRadius,
            fillOpacity: 0.07,
            strokeOpacity: 0.14
        )
    }
}

// MARK: - Macro Supporting Types

private struct GoalValidationMacroSlice: Identifiable {
    let id = UUID()
    let name: String
    let grams: Int
    let caloriesPerGram: Double
    let startColor: Color
    let endColor: Color

    var calories: Double {
        Double(grams) * caloriesPerGram
    }

    func fraction(totalCalories: Double) -> Double {
        guard totalCalories > 0 else { return 0 }
        return calories / totalCalories
    }
}

private struct GoalValidationDonutChart: View {
    let slices: [GoalValidationMacroSlice]
    let totalCalories: Double

    @State private var reveal: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(OnboardingGlassTheme.panelStroke.opacity(0.6), lineWidth: 16)

            ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                let start = startFraction(at: index)
                let end = start + slice.fraction(totalCalories: totalCalories) * reveal

                Circle()
                    .trim(from: start, to: end)
                    .stroke(
                        AngularGradient(
                            colors: [slice.startColor, slice.endColor],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: slice.endColor.opacity(0.42), radius: 4, y: 1)
            }

            VStack(spacing: 2) {
                RollingNumberText(
                    value: totalCalories.rounded(),
                    fractionDigits: 0,
                    suffix: " kcal"
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingGlassTheme.textPrimary)

                Text("macro energy")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(OnboardingGlassTheme.textMuted)
            }
        }
        .onAppear {
            reveal = 0
            withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) {
                reveal = 1
            }
        }
    }

    private func startFraction(at index: Int) -> Double {
        guard totalCalories > 0 else { return 0 }
        let priorCalories = slices.prefix(index).reduce(0) { $0 + $1.calories }
        return priorCalories / totalCalories
    }
}

private struct GoalValidationMacroLegendRow: View {
    let slice: GoalValidationMacroSlice
    let totalCalories: Double

    private var percentText: String {
        guard totalCalories > 0 else { return "0%" }
        let percent = Int((slice.calories / totalCalories * 100).rounded())
        return "\(percent)%"
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [slice.startColor, slice.endColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 1) {
                Text(slice.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)
                Text("\(slice.grams)g")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Text(percentText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
        }
    }
}
