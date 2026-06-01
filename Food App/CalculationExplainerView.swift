import SwiftUI

/// "How we calculate this" — a plain-language, dynamically-valued explanation
/// of the user's calorie + macro targets, with tappable research sources.
/// Presented as a sheet from the Plan & Goals editor and the onboarding plan
/// preview (OB05b). All numbers come from `CalculationBreakdown`, which is
/// built from the same calculator that produces the saved targets, so this
/// view can never disagree with the card it was launched from.
struct CalculationExplainerView: View {
    let breakdown: CalculationBreakdown

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private static let proteinColor = Color(red: 0.420, green: 0.369, blue: 1.0)
    private static let carbsColor = Color(red: 0.106, green: 0.620, blue: 0.353)
    private static let fatColor = Color(red: 0.000, green: 0.478, blue: 1.0)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    disclaimer

                    if breakdown.isComplete {
                        restingBurnStep
                        activityStep
                        goalStep
                        macrosStep
                    } else {
                        incompleteState
                    }

                    sourcesSection

                    Text("Calories and macros are planning estimates, not medical advice. For personalized guidance, talk to a registered dietitian or your doctor.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .navigationTitle("How we calculate this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var disclaimer: some View {
        Text("These targets are evidence-informed estimates. Your actual needs can vary based on metabolism, activity tracking accuracy, sleep, stress, and consistency.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var incompleteState: some View {
        stepCard(number: nil, title: "Finish your profile") {
            Text("Add your age, sex, height, and weight to see a personalized breakdown. Until then we use a default estimate, so these numbers may not reflect your body.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 1: resting burn

    private var restingBurnStep: some View {
        stepCard(number: 1, title: "We estimate your resting burn") {
            Text("We use the **Mifflin–St Jeor** equation — the resting-energy formula a systematic review found most accurate for healthy adults.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            formulaBox(breakdown.isMale
                ? "BMR = 10 × weight(kg) + 6.25 × height(cm) − 5 × age + 5"
                : "BMR = 10 × weight(kg) + 6.25 × height(cm) − 5 × age − 161")

            resultLine("BMR", "\(breakdown.bmr.formatted()) kcal/day")
        }
    }

    // MARK: - Step 2: activity

    private var activityStep: some View {
        stepCard(number: 2, title: "We adjust for activity") {
            Text("Your resting burn is scaled by an activity factor to estimate the calories you burn on a typical day (your maintenance level).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            formulaBox("Maintenance = BMR × activity factor")

            HStack(spacing: 6) {
                Text(breakdown.activityLabel)
                    .font(.subheadline.weight(.semibold))
                Text("→ ×\(multiplierString)")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }

            resultLine(
                "Maintenance",
                "\(breakdown.bmr.formatted()) × \(multiplierString) ≈ \(breakdown.maintenanceCalories.formatted()) kcal/day"
            )
        }
    }

    // MARK: - Step 3: goal + pace

    private var goalStep: some View {
        stepCard(number: 3, title: "We adjust for your goal") {
            Text(goalSentence)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            resultLine("Daily target", goalEquation)

            Text("The 250 / 500 / 750 kcal adjustments are simple planning estimates. Real weight change isn't perfectly linear, so treat this as a starting point — your numbers may need tuning as you log and your weight changes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private var goalSentence: String {
        if breakdown.goalAdjustment == 0 {
            return "Because your goal is \(breakdown.goalLabel), we keep your target at your maintenance level — no deficit or surplus."
        }
        let verb = breakdown.goalAdjustment < 0 ? "subtract" : "add"
        return "Because your goal is \(breakdown.goalLabel) at a \(breakdown.paceLabel) pace, we \(verb) \(abs(breakdown.goalAdjustment)) kcal/day."
    }

    private var goalEquation: String {
        if breakdown.wasFloored {
            return "raised to a safe minimum of \(breakdown.targetCalories.formatted()) kcal/day"
        }
        if breakdown.goalAdjustment == 0 {
            return "\(breakdown.targetCalories.formatted()) kcal/day"
        }
        let op = breakdown.goalAdjustment < 0 ? "−" : "+"
        return "\(breakdown.maintenanceCalories.formatted()) \(op) \(abs(breakdown.goalAdjustment)) = \(breakdown.targetCalories.formatted()) kcal/day"
    }

    // MARK: - Step 4: macros

    private var macrosStep: some View {
        stepCard(number: 4, title: "We set your macros") {
            Text("Protein is based on your body weight to support fullness and muscle retention. Fat is kept above a minimum to support normal body function. Carbs fill the remaining calories for energy and flexibility.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                macroRow("Protein", grams: breakdown.proteinGrams, color: Self.proteinColor,
                         note: "≈ \(proteinPerKgString) g per kg body weight")
                macroRow("Fat", grams: breakdown.fatGrams, color: Self.fatColor,
                         note: "30% of calories, with a floor")
                macroRow("Carbs", grams: breakdown.carbGrams, color: Self.carbsColor,
                         note: "fills the remaining calories")
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        stepCard(number: nil, title: "Sources") {
            VStack(spacing: 0) {
                ForEach(Array(breakdown.references.enumerated()), id: \.element.id) { index, reference in
                    Button {
                        openURL(reference.url)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(reference.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(reference.citation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.tint)
                        }
                        .multilineTextAlignment(.leading)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if index < breakdown.references.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Building blocks

    private func stepCard<Content: View>(
        number: Int?,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let number {
                    Text("\(number)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor, in: Circle())
                }
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formulaBox(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func resultLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private func macroRow(_ name: String, grams: Int, color: Color, note: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(grams) g")
                .font(.callout.weight(.bold))
                .monospacedDigit()
        }
    }

    private var multiplierString: String {
        String(format: "%g", breakdown.activityMultiplier)
    }

    private var proteinPerKgString: String {
        String(format: "%g", breakdown.proteinPerKg)
    }
}
