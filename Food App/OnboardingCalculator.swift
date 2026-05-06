import Foundation

struct OnboardingMetrics {
    let estimatedMaintenanceKcal: Int
    let targetKcal: Int
    let projectedGoalDate: String
    let proteinTarget: Int
    let carbTarget: Int
    let fatTarget: Int
}

enum OnboardingCalculator {
    static func metrics(from draft: OnboardingDraft, now: Date = Date()) -> OnboardingMetrics {
        let maintenance = estimatedMaintenanceKcal(from: draft)
        let target = targetKcal(from: draft, maintenance: maintenance)
        let projectedDate = projectedGoalDate(from: draft, now: now)
        let macros = macroTargets(for: target)

        return OnboardingMetrics(
            estimatedMaintenanceKcal: maintenance,
            targetKcal: target,
            projectedGoalDate: projectedDate,
            proteinTarget: macros.protein,
            carbTarget: macros.carbs,
            fatTarget: macros.fat
        )
    }

    private static func macroTargets(for targetKcal: Int) -> (protein: Int, carbs: Int, fat: Int) {
        let desiredProtein = Double(targetKcal) * 0.30 / 4.0
        let desiredCarbs = Double(targetKcal) * 0.40 / 4.0
        let desiredFat = Double(targetKcal) * 0.30 / 9.0

        let baseProtein = max(0, Int(desiredProtein.rounded()))
        let baseCarbs = max(0, Int(desiredCarbs.rounded()))
        let baseFat = max(0, Int(desiredFat.rounded()))

        var best: (protein: Int, carbs: Int, fat: Int, score: Double)?
        let proteinSearch = max(0, baseProtein - 18)...(baseProtein + 18)
        let carbSearch = max(0, baseCarbs - 24)...(baseCarbs + 24)

        for protein in proteinSearch {
            for carbs in carbSearch {
                let remainingKcal = targetKcal - (4 * protein) - (4 * carbs)
                if remainingKcal < 0 || remainingKcal % 9 != 0 {
                    continue
                }

                let fat = remainingKcal / 9
                if fat < 0 {
                    continue
                }

                let score =
                    pow(Double(protein) - desiredProtein, 2) +
                    pow(Double(carbs) - desiredCarbs, 2) +
                    pow(Double(fat) - desiredFat, 2)

                if let currentBest = best {
                    if score < currentBest.score {
                        best = (protein, carbs, fat, score)
                    }
                } else {
                    best = (protein, carbs, fat, score)
                }
            }
        }

        if let best {
            return (best.protein, best.carbs, best.fat)
        }

        return (baseProtein, baseCarbs, baseFat)
    }

    private static func estimatedMaintenanceKcal(from draft: OnboardingDraft) -> Int {
        guard draft.hasBaselineValues else { return 2200 }
        let age = Double(draft.age) ?? 30
        let weight = draft.weightInKg
        let height = draft.heightInCm
        let sexOffset = draft.sex == .male ? 5 : -161
        let bmr = (10 * weight) + (6.25 * height) - (5 * age) + Double(sexOffset)

        // Activity multiplier (same scale as MyFitnessPal)
        let activityMultiplier: Double
        switch draft.activity {
        case .mostlySitting:    activityMultiplier = 1.2
        case .lightlyActive:    activityMultiplier = 1.375
        case .moderatelyActive: activityMultiplier = 1.55
        case .veryActive:       activityMultiplier = 1.725
        case .none:             activityMultiplier = 1.2
        }

        let minFloor = draft.sex == .male ? 1500 : 1200
        return max(minFloor, Int((bmr * activityMultiplier).rounded()))
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

    private static func targetKcal(from draft: OnboardingDraft, maintenance: Int) -> Int {
        let deficit = dailyDeficitForPace(draft.pace)

        let target: Int
        switch draft.goal ?? .maintain {
        case .lose:     target = maintenance - deficit
        case .maintain: target = maintenance
        case .gain:     target = maintenance + deficit
        }

        let minFloor = draft.sex == .male ? 1500 : 1200
        return max(minFloor, target)
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

