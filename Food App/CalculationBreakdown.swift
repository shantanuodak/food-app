import Foundation

/// A research reference surfaced in the explainer's "Sources" section.
/// Tapping a row opens `url`.
struct CalculationReference: Identifiable, Hashable {
    let id = UUID()
    /// Short human-readable title for the row.
    let title: String
    /// Full academic citation shown beneath the title.
    let citation: String
    let url: URL
}

extension CalculationReference {
    /// The four sources the calculation is built on. Kept here (not in the
    /// view) so the same list backs any future surface — and so the citations
    /// stay next to the formula they justify.
    static let all: [CalculationReference] = [
        CalculationReference(
            title: "Mifflin–St Jeor resting energy equation (1990)",
            citation: "Mifflin MD, St Jeor ST, Hill LA, Scott BJ, Daugherty SA, Koh YO. A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr. 1990.",
            url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/")!
        ),
        CalculationReference(
            title: "Accuracy of resting metabolic rate equations (2005)",
            citation: "Frankenfield D, Roth-Yousey L, Compher C. Comparison of predictive equations for resting metabolic rate in healthy nonobese and obese adults: a systematic review. J Am Diet Assoc. 2005.",
            url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/15883556/")!
        ),
        CalculationReference(
            title: "ISSN Position Stand: protein & exercise (2017)",
            citation: "Jäger R, Kerksick CM, Campbell BI, et al. International Society of Sports Nutrition Position Stand: protein and exercise. J Int Soc Sports Nutr. 2017.",
            url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/28642676/")!
        ),
        CalculationReference(
            title: "Predicting weight loss is not linear (2014)",
            citation: "Thomas DM, Martin CK, Lettieri S, et al. Time to correctly predict the amount of weight loss with dieting. J Acad Nutr Diet. 2014.",
            url: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC4035446/")!
        )
    ]
}

/// Plain-language, dynamically-valued breakdown of how a user's calorie and
/// macro targets were computed. Built from the SAME `OnboardingCalculator`
/// output that produces the saved targets (`make(from:)`), so the explainer
/// can never disagree with the numbers shown on the card it launches from.
/// Rendered by `CalculationExplainerView`.
struct CalculationBreakdown {
    // Step 1 — resting burn
    let bmrFormulaName: String
    let isMale: Bool
    let bmr: Int

    // Step 2 — activity
    let activityMultiplier: Double
    let activityLabel: String
    let maintenanceCalories: Int

    // Step 3 — goal + pace
    let goalLabel: String
    let paceLabel: String
    /// Signed daily delta: negative for Lose, positive for Gain, 0 for Maintain.
    let goalAdjustment: Int
    let targetCalories: Int

    // Step 4 — macros
    let proteinGrams: Int
    let carbGrams: Int
    let fatGrams: Int
    /// Grams of protein per kg bodyweight used (1.8 cutting, 1.6 otherwise).
    let proteinPerKg: Double
    let weightKg: Double

    /// False when the draft is missing biometrics (mid-onboarding). The view
    /// then shows a "finish your profile" state instead of a fabricated Mifflin
    /// equation.
    let isComplete: Bool
    let references: [CalculationReference]

    /// True when the calorie floor (1500 male / 1200 female) clamped the
    /// target, so `maintenance + goalAdjustment` won't visually add up to
    /// `targetCalories`. The view shows a "raised to a safe minimum" note.
    var wasFloored: Bool {
        isComplete && (maintenanceCalories + goalAdjustment) != targetCalories
    }
}

extension CalculationBreakdown {
    /// Build the breakdown from a draft using the production calculator. Pass
    /// the same draft that drives the visible targets (the profile-loaded draft
    /// on Plan & Goals).
    static func make(from draft: OnboardingDraft, now: Date = Date()) -> CalculationBreakdown {
        make(from: draft, metrics: OnboardingCalculator.metrics(from: draft, now: now))
    }

    /// Build from a draft plus already-computed metrics — used by the
    /// onboarding plan preview (OB05b), which has the metrics in hand, so the
    /// explainer is guaranteed to match the numbers on the card exactly.
    static func make(from draft: OnboardingDraft, metrics: OnboardingMetrics) -> CalculationBreakdown {
        let goal = draft.goal ?? .maintain
        return CalculationBreakdown(
            bmrFormulaName: "Mifflin–St Jeor",
            isMale: draft.sex == .male,
            bmr: metrics.bmr,
            activityMultiplier: metrics.activityMultiplier,
            activityLabel: (draft.activity ?? .mostlySitting).title,
            maintenanceCalories: metrics.estimatedMaintenanceKcal,
            goalLabel: L10n.goalLabel(goal),
            paceLabel: (draft.pace ?? .balanced).title,
            goalAdjustment: metrics.goalAdjustment,
            targetCalories: metrics.targetKcal,
            proteinGrams: metrics.proteinTarget,
            carbGrams: metrics.carbTarget,
            fatGrams: metrics.fatTarget,
            proteinPerKg: goal == .lose ? 1.8 : 1.6,
            weightKg: draft.weightInKg,
            isComplete: metrics.hasCompleteBaseline,
            references: CalculationReference.all
        )
    }
}
