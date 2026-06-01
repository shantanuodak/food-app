import Foundation

struct OnboardingMetrics {
    let estimatedMaintenanceKcal: Int
    let targetKcal: Int
    let projectedGoalDate: String
    let proteinTarget: Int
    let carbTarget: Int
    let fatTarget: Int

    // V5 (2026-05-31) breakdown intermediates for the "How we calculate this"
    // explainer. `bmr` is the raw Mifflin–St Jeor resting estimate;
    // `goalAdjustment` is the signed pace delta (negative for Lose, positive
    // for Gain, 0 for Maintain). When `hasCompleteBaseline` is false the draft
    // is mid-onboarding and the explainer shows its "finish your profile" state
    // instead of a fabricated equation.
    let bmr: Int
    let activityMultiplier: Double
    let goalAdjustment: Int
    let hasCompleteBaseline: Bool
}

enum OnboardingCalculator {
    static func metrics(from draft: OnboardingDraft, now: Date = Date()) -> OnboardingMetrics {
        let baseline = baselineEnergy(from: draft)
        let goalAdjustment = goalAdjustmentKcal(from: draft)
        let minFloor = draft.sex == .male ? 1500 : 1200
        let target = max(minFloor, baseline.maintenance + goalAdjustment)
        let macros = macroTargets(for: target, weightKg: draft.weightInKg, goal: draft.goal ?? .maintain)
        let projectedDate = projectedGoalDate(from: draft, now: now)

        return OnboardingMetrics(
            estimatedMaintenanceKcal: baseline.maintenance,
            targetKcal: target,
            projectedGoalDate: projectedDate,
            proteinTarget: macros.protein,
            carbTarget: macros.carbs,
            fatTarget: macros.fat,
            bmr: baseline.bmr,
            activityMultiplier: baseline.multiplier,
            goalAdjustment: goalAdjustment,
            hasCompleteBaseline: draft.hasBaselineValues
        )
    }

    /// V5 (2026-05-31) bodyweight-anchored macro split. Mirrors the backend
    /// `resolveMacroTargets` in onboardingService.ts byte-for-byte (a backend
    /// test asserts the shared fixtures). Protein scales with total bodyweight
    /// (1.8 g/kg while cutting to protect lean mass, 1.6 g/kg otherwise — ISSN
    /// Position Stand, Jäger 2017), fat is 30% of calories with a 0.6 g/kg
    /// essential-fat floor, carbs take the remainder. Whole-gram macros can't
    /// always sum exactly to the calorie target, so the result lands within
    /// ~2 kcal. `Int(x.rounded())` matches JS `Math.round` for the non-negative
    /// values used here, and the clamp uses `floor()` to match `Math.floor`.
    static func macroTargets(
        for targetKcal: Int,
        weightKg: Double,
        goal: GoalOption
    ) -> (protein: Int, carbs: Int, fat: Int) {
        let proteinPerKg = goal == .lose ? 1.8 : 1.6
        var protein = max(0, Int((weightKg * proteinPerKg).rounded()))

        let fatFloorGrams = Int((weightKg * 0.6).rounded())
        var fat = max(Int((Double(targetKcal) * 0.30 / 9.0).rounded()), fatFloorGrams)

        // Heavy person on a low target: protein + fat can exceed the budget.
        // Keep the essential-fat floor, trim any fat above it first, then cap
        // protein so carbs never go negative. (No real profile hits this — DB
        // audit 2026-05-31 — but the calculator must stay total.)
        if protein * 4 + fat * 9 > targetKcal {
            let maxFatGrams = max(fatFloorGrams, Int(floor(Double(targetKcal - protein * 4) / 9.0)))
            fat = max(0, min(fat, maxFatGrams))
            if protein * 4 + fat * 9 > targetKcal {
                protein = max(0, Int(floor(Double(targetKcal - fat * 9) / 4.0)))
            }
        }

        let carbs = max(0, Int((Double(targetKcal - protein * 4 - fat * 9) / 4.0).rounded()))
        return (protein, carbs, fat)
    }

    private static func activityMultiplier(for activity: ActivityChoice?) -> Double {
        // Activity multiplier (same scale as MyFitnessPal).
        switch activity {
        case .mostlySitting:    return 1.2
        case .lightlyActive:    return 1.375
        case .moderatelyActive: return 1.55
        case .veryActive:       return 1.725
        case .none:             return 1.2
        }
    }

    /// Returns the Mifflin–St Jeor BMR, the activity multiplier, and the
    /// resulting maintenance (TDEE) estimate. For an incomplete draft (live
    /// onboarding preview before biometrics are entered) it mirrors the legacy
    /// 2200 fallback so the preview calorie number stays stable; `bmr` is 0 and
    /// `metrics(from:)` flags the breakdown incomplete so the explainer never
    /// renders a fabricated Mifflin equation.
    private static func baselineEnergy(from draft: OnboardingDraft) -> (bmr: Int, multiplier: Double, maintenance: Int) {
        let multiplier = activityMultiplier(for: draft.activity)
        guard draft.hasBaselineValues else {
            return (bmr: 0, multiplier: multiplier, maintenance: 2200)
        }
        let age = Double(draft.age) ?? 30
        let weight = draft.weightInKg
        let height = draft.heightInCm
        let sexOffset = draft.sex == .male ? 5.0 : -161.0
        let bmr = (10 * weight) + (6.25 * height) - (5 * age) + sexOffset

        let minFloor = draft.sex == .male ? 1500 : 1200
        let maintenance = max(minFloor, Int((bmr * multiplier).rounded()))
        return (bmr: Int(bmr.rounded()), multiplier: multiplier, maintenance: maintenance)
    }

    /// Single source of truth for "what does this pace mean in pounds per
    /// week?" — used by the daily-deficit math, the projected-goal-date
    /// estimate, and the pace-screen chip. Kept here so the three readouts
    /// the user sees during onboarding can never disagree with each other.
    /// Returns nil for goals that don't move the user's weight (Maintain).
    static func weeklyRateLbs(for goal: GoalOption?, pace: PaceChoice?) -> Double? {
        switch goal ?? .maintain {
        case .maintain:
            return nil
        case .lose, .gain:
            switch pace ?? .balanced {
            case .conservative: return 0.5
            case .balanced:     return 1.0
            case .aggressive:   return 1.5
            }
        }
    }

    /// Daily calorie deficit/surplus based on pace (3,500 cal ≈ 1 lb body fat):
    /// - Conservative: 0.5 lb/week = 250 cal/day
    /// - Balanced:     1.0 lb/week = 500 cal/day
    /// - Aggressive:   1.5 lb/week = 750 cal/day
    private static func dailyDeficitForPace(_ pace: PaceChoice?) -> Int {
        // Derive from weeklyRateLbs so the chip, projected date, and target
        // calorie math stay in lockstep — change weekly rates in one place.
        let weekly = weeklyRateLbs(for: .lose, pace: pace) ?? 1.0
        return Int((weekly * 3500.0 / 7.0).rounded())
    }

    /// Signed daily calorie delta applied to maintenance: negative for Lose,
    /// positive for Gain, zero for Maintain. The calorie floor is applied by
    /// the caller (`metrics(from:)`).
    private static func goalAdjustmentKcal(from draft: OnboardingDraft) -> Int {
        let deficit = dailyDeficitForPace(draft.pace)
        switch draft.goal ?? .maintain {
        case .lose:     return -deficit
        case .gain:     return deficit
        case .maintain: return 0
        }
    }

    /// Projected weeks based on a 10 lb (4.5 kg) goal using the pace's weekly rate.
    private static func projectedGoalDate(from draft: OnboardingDraft, now: Date) -> String {
        // Maintain has no rate; fall back to balanced for the projection.
        let lbsPerWeek = weeklyRateLbs(for: draft.goal, pace: draft.pace) ?? 1.0
        // Assume a 10 lb goal if we can't compute actual delta
        let targetLbs: Double = 10
        let weeksToGoal = max(4, Int((targetLbs / lbsPerWeek).rounded(.up)))
        let date = Calendar.current.date(byAdding: .weekOfYear, value: weeksToGoal, to: now) ?? now
        return goalDateFormatter.string(from: date)
    }

    private static let goalDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

