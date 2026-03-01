import SwiftUI

struct OB07PlanPreviewScreen: View {
    let targetKcal: Int
    let protein: Int
    let carbs: Int
    let fat: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Here is your starting target. You can adjust this later.")
                .font(.footnote)
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .padding(.horizontal, 4)

            OnboardingValueCard(
                title: "Daily calories",
                bodyText: "\(targetKcal) kcal",
                animatedNumber: Double(targetKcal),
                animatedFractionDigits: 0,
                animatedUnit: "kcal",
                isSuccess: true
            )

            OnboardingMacroTrendCard(
                protein: protein,
                carbs: carbs,
                fat: fat
            )
        }
    }
}

private struct OnboardingMacroTrendCard: View {
    let protein: Int
    let carbs: Int
    let fat: Int

    @State private var animateTrend = false

    private var slices: [MacroSlice] {
        [
            MacroSlice(
                name: "Protein",
                grams: protein,
                caloriesPerGram: 4,
                startColor: Color(red: 0.34, green: 0.56, blue: 1.00),
                endColor: Color(red: 0.60, green: 0.41, blue: 1.00)
            ),
            MacroSlice(
                name: "Carbs",
                grams: carbs,
                caloriesPerGram: 4,
                startColor: Color(red: 0.20, green: 0.90, blue: 0.62),
                endColor: Color(red: 0.71, green: 0.94, blue: 0.35)
            ),
            MacroSlice(
                name: "Fat",
                grams: fat,
                caloriesPerGram: 9,
                startColor: Color(red: 1.00, green: 0.61, blue: 0.26),
                endColor: Color(red: 1.00, green: 0.37, blue: 0.41)
            )
        ]
        .filter { $0.grams > 0 }
    }

    private var totalMacroCalories: Double {
        slices.reduce(0) { $0 + $1.calories }
    }

    var body: some View {
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
                OnboardingMacroDonutChart(
                    slices: slices,
                    totalCalories: totalMacroCalories
                )
                .frame(width: 126, height: 126)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(slices) { slice in
                        OnboardingMacroLegendRow(
                            slice: slice,
                            totalCalories: totalMacroCalories
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("7-day expected trend")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)
                Text("Steady adherence at your selected pace.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
                OnboardingTrendBarStrip(animate: animateTrend)
                    .frame(height: 46)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .onboardingGlassPanel(
            cornerRadius: OnboardingGlassMetrics.cornerRadius,
            fillOpacity: 0.07,
            strokeOpacity: 0.14
        )
        .onAppear {
            animateTrend = false
            withAnimation(.spring(response: 0.7, dampingFraction: 0.86).delay(0.12)) {
                animateTrend = true
            }
        }
    }
}

private struct OnboardingMacroDonutChart: View {
    let slices: [MacroSlice]
    let totalCalories: Double

    @State private var reveal: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 16)

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

private struct OnboardingMacroLegendRow: View {
    let slice: MacroSlice
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

private struct OnboardingTrendBarStrip: View {
    let animate: Bool
    private let values: [CGFloat] = [0.54, 0.61, 0.66, 0.72, 0.78, 0.83, 0.89]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(values.indices, id: \.self) { index in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.25), Color.white.opacity(0.86)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 10, height: max(14, 40 * values[index]))
                    .scaleEffect(y: animate ? 1 : 0.2, anchor: .bottom)
                    .opacity(animate ? 1 : 0.35)
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.83)
                            .delay(Double(index) * 0.06),
                        value: animate
                    )
            }

            Spacer(minLength: 8)

            Text("STEADY")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(OnboardingGlassTheme.textMuted)
        }
    }
}

private struct MacroSlice: Identifiable {
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
