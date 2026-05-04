import Foundation

enum OnboardingScreenLoadState: String, Codable {
    case `default`
    case loading
    case disabled
    case error
}

struct OnboardingScreenState: Codable, Equatable {
    var loadState: OnboardingScreenLoadState = .default
    var errorMessage: String? = nil
}

enum OnboardingBaselineRange {
    static let age = 13 ... 90
    static let heightCm = 122 ... 218
    static let minImperialHeightInches = 48
    static let maxImperialHeightInches = 86
    static let minImperialFeet = 4
    static let maxImperialFeet = 7
    static let maxInchesForMaxFeet = 2
    static let weightKg = 35.0 ... 227.0
    static let weightLb = 77.0 ... 500.0
    static let weightStep = 0.5

    static let defaultAge = 25
    static let defaultHeightCm = 170
    static let defaultImperialHeightInches = 67
    static let defaultWeightKg = 70.0
    static let defaultWeightLb = 154.0
}

struct OnboardingDraft: Codable, Equatable {
    var goal: GoalOption?
    var age: String = ""
    var sex: SexOption?
    var height: String = ""
    var weight: String = ""
    var units: UnitsOption? = .imperial
    var baselineTouchedAge = false
    var baselineTouchedSex = false
    var baselineTouchedHeight = false
    var baselineTouchedWeight = false
    var activity: ActivityChoice?
    var pace: PaceChoice?
    var experience: ExperienceChoice?
    var challenge: ChallengeChoice?
    var preferences: Set<PreferenceChoice> = []
    var allergies: Set<AllergyChoice> = []
    var accountProvider: AccountProvider?
    var connectHealth = false
    var enableNotifications = false
    var savedCalorieTarget: Int?
    var savedMacroTargets: MacroTargets?

    var hasBaselineValues: Bool {
        guard sex != nil, units != nil else { return false }

        let ageValue = Double(age) ?? 0
        let heightRaw = Double(height) ?? 0
        let weightRaw = Double(weight) ?? 0
        guard ageValue > 0, heightRaw > 0, weightRaw > 0 else { return false }

        let normalizedAge = Int(ageValue.rounded())
        guard OnboardingBaselineRange.age.contains(normalizedAge) else { return false }

        switch units ?? .imperial {
        case .metric:
            let cm = Int(heightRaw.rounded())
            return OnboardingBaselineRange.heightCm.contains(cm) &&
                OnboardingBaselineRange.weightKg.contains(weightRaw)
        case .imperial:
            let inches = Int(heightRaw.rounded())
            return (OnboardingBaselineRange.minImperialHeightInches ... OnboardingBaselineRange.maxImperialHeightInches).contains(inches) &&
                OnboardingBaselineRange.weightLb.contains(weightRaw)
        }
    }

    var isBaselineValid: Bool {
        hasBaselineValues &&
            baselineTouchedAge &&
            baselineTouchedSex &&
            baselineTouchedHeight &&
            baselineTouchedWeight &&
            sex != nil &&
            units != nil
    }

    var weightInKg: Double {
        let value = parseCurrentWeightOrDefault()
        switch units ?? .imperial {
        case .metric: return value
        case .imperial: return value * 0.453592
        }
    }

    var heightInCm: Double {
        let value = parseCurrentHeightCmOrDefault()
        switch units ?? .imperial {
        case .metric: return value
        case .imperial: return value
        }
    }

    var ageValue: Double {
        get {
            let parsed = Int((Double(age) ?? Double(OnboardingBaselineRange.defaultAge)).rounded())
            let clamped = min(max(parsed, OnboardingBaselineRange.age.lowerBound), OnboardingBaselineRange.age.upperBound)
            return Double(clamped)
        }
        set {
            let rounded = Int(newValue.rounded())
            let clamped = min(max(rounded, OnboardingBaselineRange.age.lowerBound), OnboardingBaselineRange.age.upperBound)
            age = String(clamped)
        }
    }

    var weightValue: Double {
        get {
            switch units ?? .imperial {
            case .metric:
                return roundToStep(parseCurrentWeightOrDefault(), step: OnboardingBaselineRange.weightStep)
            case .imperial:
                return roundToStep(parseCurrentWeightOrDefault(), step: OnboardingBaselineRange.weightStep)
            }
        }
        set {
            let range = (units ?? .imperial) == .metric ? OnboardingBaselineRange.weightKg : OnboardingBaselineRange.weightLb
            let clamped = min(max(newValue, range.lowerBound), range.upperBound)
            let stepped = roundToStep(clamped, step: OnboardingBaselineRange.weightStep)
            weight = displayString(for: stepped, alwaysShowDecimal: stepped.truncatingRemainder(dividingBy: 1) != 0)
        }
    }

    var heightMetricValue: Double {
        get {
            let cm: Double
            switch units ?? .imperial {
            case .metric:
                cm = Double(height) ?? Double(OnboardingBaselineRange.defaultHeightCm)
            case .imperial:
                let inches = parseTotalInchesOrDefault()
                cm = Double(inches) * 2.54
            }
            let clamped = min(
                max(Int(cm.rounded()), OnboardingBaselineRange.heightCm.lowerBound),
                OnboardingBaselineRange.heightCm.upperBound
            )
            return Double(clamped)
        }
        set {
            let rounded = Int(newValue.rounded())
            let clampedCm = min(max(rounded, OnboardingBaselineRange.heightCm.lowerBound), OnboardingBaselineRange.heightCm.upperBound)
            switch units ?? .imperial {
            case .metric:
                height = String(clampedCm)
            case .imperial:
                let inches = Int((Double(clampedCm) / 2.54).rounded())
                height = String(
                    min(
                        max(inches, OnboardingBaselineRange.minImperialHeightInches),
                        OnboardingBaselineRange.maxImperialHeightInches
                    )
                )
            }
        }
    }

    var imperialHeightFeetInches: (feet: Int, inches: Int) {
        get {
            let totalInches = parseTotalInchesOrDefault()
            let feet = totalInches / 12
            let inches = totalInches % 12
            return (feet, inches)
        }
        set {
            var feet = min(max(newValue.feet, OnboardingBaselineRange.minImperialFeet), OnboardingBaselineRange.maxImperialFeet)
            var inches = min(max(newValue.inches, 0), 11)
            if feet == OnboardingBaselineRange.maxImperialFeet {
                inches = min(inches, OnboardingBaselineRange.maxInchesForMaxFeet)
            }

            var totalInches = (feet * 12) + inches
            if totalInches < OnboardingBaselineRange.minImperialHeightInches {
                totalInches = OnboardingBaselineRange.minImperialHeightInches
                feet = totalInches / 12
                inches = totalInches % 12
            }
            if totalInches > OnboardingBaselineRange.maxImperialHeightInches {
                totalInches = OnboardingBaselineRange.maxImperialHeightInches
                feet = totalInches / 12
                inches = totalInches % 12
            }

            height = String((feet * 12) + inches)
        }
    }

    mutating func setUnitsPreservingBaseline(_ newUnits: UnitsOption) {
        let previousUnits = units ?? .imperial
        guard previousUnits != newUnits else {
            units = newUnits
            return
        }

        let preservedWeightKg: Double
        switch previousUnits {
        case .metric:
            let kg = Double(weight) ?? OnboardingBaselineRange.defaultWeightKg
            preservedWeightKg = min(max(kg, OnboardingBaselineRange.weightKg.lowerBound), OnboardingBaselineRange.weightKg.upperBound)
        case .imperial:
            let lb = Double(weight) ?? OnboardingBaselineRange.defaultWeightLb
            let clamped = min(max(lb, OnboardingBaselineRange.weightLb.lowerBound), OnboardingBaselineRange.weightLb.upperBound)
            preservedWeightKg = clamped * 0.453592
        }

        let preservedHeightCm: Double
        switch previousUnits {
        case .metric:
            let cm = Double(height) ?? Double(OnboardingBaselineRange.defaultHeightCm)
            let clamped = min(max(Int(cm.rounded()), OnboardingBaselineRange.heightCm.lowerBound), OnboardingBaselineRange.heightCm.upperBound)
            preservedHeightCm = Double(clamped)
        case .imperial:
            let inches = parseTotalInchesOrDefault()
            preservedHeightCm = Double(inches) * 2.54
        }

        units = newUnits
        switch newUnits {
        case .metric:
            let cm = Int(preservedHeightCm.rounded())
            let clampedCm = min(max(cm, OnboardingBaselineRange.heightCm.lowerBound), OnboardingBaselineRange.heightCm.upperBound)
            height = String(clampedCm)

            let kg = min(max(preservedWeightKg, OnboardingBaselineRange.weightKg.lowerBound), OnboardingBaselineRange.weightKg.upperBound)
            weight = displayString(for: roundToStep(kg, step: OnboardingBaselineRange.weightStep), alwaysShowDecimal: false)
        case .imperial:
            let inches = Int((preservedHeightCm / 2.54).rounded())
            let clampedInches = min(
                max(inches, OnboardingBaselineRange.minImperialHeightInches),
                OnboardingBaselineRange.maxImperialHeightInches
            )
            height = String(clampedInches)

            let lbs = preservedWeightKg / 0.453592
            let clampedLb = min(max(lbs, OnboardingBaselineRange.weightLb.lowerBound), OnboardingBaselineRange.weightLb.upperBound)
            weight = displayString(for: roundToStep(clampedLb, step: OnboardingBaselineRange.weightStep), alwaysShowDecimal: false)
        }
    }

    mutating func migrateLegacyBaselineTouchStateIfNeeded() {
        let ageLegacy = (Double(age) ?? 0) > 0
        let heightLegacy = (Double(height) ?? 0) > 0
        let weightLegacy = (Double(weight) ?? 0) > 0

        if ageLegacy && !baselineTouchedAge {
            baselineTouchedAge = true
        }
        if heightLegacy && !baselineTouchedHeight {
            baselineTouchedHeight = true
        }
        if weightLegacy && !baselineTouchedWeight {
            baselineTouchedWeight = true
        }
    }

    private func parseCurrentWeightOrDefault() -> Double {
        let parsed = Double(weight)
        switch units ?? .imperial {
        case .metric:
            return min(
                max(parsed ?? OnboardingBaselineRange.defaultWeightKg, OnboardingBaselineRange.weightKg.lowerBound),
                OnboardingBaselineRange.weightKg.upperBound
            )
        case .imperial:
            return min(
                max(parsed ?? OnboardingBaselineRange.defaultWeightLb, OnboardingBaselineRange.weightLb.lowerBound),
                OnboardingBaselineRange.weightLb.upperBound
            )
        }
    }

    private func parseCurrentHeightCmOrDefault() -> Double {
        switch units ?? .imperial {
        case .metric:
            let cm = Int((Double(height) ?? Double(OnboardingBaselineRange.defaultHeightCm)).rounded())
            let clamped = min(max(cm, OnboardingBaselineRange.heightCm.lowerBound), OnboardingBaselineRange.heightCm.upperBound)
            return Double(clamped)
        case .imperial:
            let cm = Double(parseTotalInchesOrDefault()) * 2.54
            let clamped = min(max(Int(cm.rounded()), OnboardingBaselineRange.heightCm.lowerBound), OnboardingBaselineRange.heightCm.upperBound)
            return Double(clamped)
        }
    }

    private func parseTotalInchesOrDefault() -> Int {
        switch units ?? .imperial {
        case .metric:
            let cm = Int((Double(height) ?? Double(OnboardingBaselineRange.defaultHeightCm)).rounded())
            let clampedCm = min(max(cm, OnboardingBaselineRange.heightCm.lowerBound), OnboardingBaselineRange.heightCm.upperBound)
            let inches = Int((Double(clampedCm) / 2.54).rounded())
            return min(max(inches, OnboardingBaselineRange.minImperialHeightInches), OnboardingBaselineRange.maxImperialHeightInches)
        case .imperial:
            let inches = Int((Double(height) ?? Double(OnboardingBaselineRange.defaultImperialHeightInches)).rounded())
            return min(max(inches, OnboardingBaselineRange.minImperialHeightInches), OnboardingBaselineRange.maxImperialHeightInches)
        }
    }

    private func roundToStep(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    private func displayString(for value: Double, alwaysShowDecimal: Bool) -> String {
        if !alwaysShowDecimal && abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}

extension OnboardingDraft {
    private enum CodingKeys: String, CodingKey {
        case goal
        case age
        case sex
        case height
        case weight
        case units
        case baselineTouchedAge
        case baselineTouchedSex
        case baselineTouchedHeight
        case baselineTouchedWeight
        case activity
        case pace
        case experience
        case challenge
        case preferences
        case allergies
        case accountProvider
        case connectHealth
        case enableNotifications
        case savedCalorieTarget
        case savedMacroTargets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goal = try container.decodeIfPresent(GoalOption.self, forKey: .goal)
        age = try container.decodeIfPresent(String.self, forKey: .age) ?? ""
        sex = try container.decodeIfPresent(SexOption.self, forKey: .sex)
        height = try container.decodeIfPresent(String.self, forKey: .height) ?? ""
        weight = try container.decodeIfPresent(String.self, forKey: .weight) ?? ""
        units = try container.decodeIfPresent(UnitsOption.self, forKey: .units) ?? .imperial
        baselineTouchedAge = try container.decodeIfPresent(Bool.self, forKey: .baselineTouchedAge) ?? false
        baselineTouchedSex = try container.decodeIfPresent(Bool.self, forKey: .baselineTouchedSex) ?? false
        baselineTouchedHeight = try container.decodeIfPresent(Bool.self, forKey: .baselineTouchedHeight) ?? false
        baselineTouchedWeight = try container.decodeIfPresent(Bool.self, forKey: .baselineTouchedWeight) ?? false
        activity = try container.decodeIfPresent(ActivityChoice.self, forKey: .activity)
        pace = try container.decodeIfPresent(PaceChoice.self, forKey: .pace)
        experience = try container.decodeIfPresent(ExperienceChoice.self, forKey: .experience)
        challenge = try container.decodeIfPresent(ChallengeChoice.self, forKey: .challenge)
        preferences = try container.decodeIfPresent(Set<PreferenceChoice>.self, forKey: .preferences) ?? []
        allergies = try container.decodeIfPresent(Set<AllergyChoice>.self, forKey: .allergies) ?? []
        accountProvider = try container.decodeIfPresent(AccountProvider.self, forKey: .accountProvider)
        connectHealth = try container.decodeIfPresent(Bool.self, forKey: .connectHealth) ?? false
        enableNotifications = try container.decodeIfPresent(Bool.self, forKey: .enableNotifications) ?? false
        savedCalorieTarget = try container.decodeIfPresent(Int.self, forKey: .savedCalorieTarget)
        savedMacroTargets = try container.decodeIfPresent(MacroTargets.self, forKey: .savedMacroTargets)
    }

    init(profile: OnboardingProfileResponse, accountProvider: AccountProvider?) {
        goal = profile.goal
        units = profile.units
        age = profile.age.map(String.init) ?? ""
        sex = profile.sex.flatMap(SexOption.init(rawValue:))
        baselineTouchedAge = profile.age != nil
        baselineTouchedSex = sex != nil
        baselineTouchedHeight = profile.heightCm != nil
        baselineTouchedWeight = profile.weightKg != nil
        activity = profile.activityDetail.flatMap(ActivityChoice.init(rawValue:)) ??
            Self.activityChoice(from: profile.activityLevel)
        pace = profile.pace.flatMap(PaceChoice.init(rawValue:))
        experience = nil
        challenge = nil
        preferences = Self.preferenceSet(from: profile.dietPreference)
        allergies = Set(profile.allergies.compactMap(AllergyChoice.init(rawValue:)))
        self.accountProvider = accountProvider
        connectHealth = false
        enableNotifications = false
        savedCalorieTarget = profile.calorieTarget
        savedMacroTargets = profile.macroTargets

        let heightCm = profile.heightCm ?? Double(OnboardingBaselineRange.defaultHeightCm)
        let weightKg = profile.weightKg ?? OnboardingBaselineRange.defaultWeightKg
        switch profile.units {
        case .metric:
            height = String(Int(heightCm.rounded()))
            weight = Self.displayString(weightKg)
        case .imperial:
            height = String(Int((heightCm / 2.54).rounded()))
            weight = Self.displayString(weightKg / 0.453592)
        }
    }

    private static func activityChoice(from level: ActivityLevelOption) -> ActivityChoice {
        switch level {
        case .low: return .mostlySitting
        case .moderate: return .lightlyActive
        case .high: return .veryActive
        }
    }

    private static func preferenceSet(from payload: String) -> Set<PreferenceChoice> {
        let values = payload
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let resolved = Set(values.compactMap(PreferenceChoice.init(rawValue:)))
        return resolved.isEmpty ? [.noPreference] : resolved
    }

    private static func displayString(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}

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

enum OnboardingPersistence {
    private static let draftKey = "app.onboarding.draft.v1"
    private static let routeKey = "app.onboarding.route.v1"

    static func save(draft: OnboardingDraft, route: OnboardingRoute, defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(draft) {
            defaults.set(data, forKey: draftKey)
        }
        defaults.set(route.rawValue, forKey: routeKey)
    }

    static func load(defaults: UserDefaults = .standard) -> (draft: OnboardingDraft, route: OnboardingRoute)? {
        let decoder = JSONDecoder()
        var draft: OnboardingDraft

        if let data = defaults.data(forKey: draftKey),
           let decoded = try? decoder.decode(OnboardingDraft.self, from: data) {
            draft = decoded
        } else {
            return nil
        }

        draft.migrateLegacyBaselineTouchStateIfNeeded()

        let routeRaw = defaults.integer(forKey: routeKey)
        let route = OnboardingRoute(rawValue: routeRaw) ?? .welcome
        return (draft, route)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: draftKey)
        defaults.removeObject(forKey: routeKey)
    }
}

extension OnboardingRoute {
    var headline: String {
        switch self {
        case .welcome:
            return "Log your food with less effort"
        case .goal:
            return "What’s your goal right now?"
        case .age:
            return "How young are you?"
        case .baseline:
            return "Let’s set your baseline"
        case .activity:
            return "How active are you most days?"
        case .pace:
            return "Choose your pace"
        case .preferencesOptional:
            return "Food Preferences"
        case .planPreview:
            return "Your plan is ready"
        case .account:
            return "Save your setup"
        case .permissions:
            return "Apple Health"
        case .notificationsPermission:
            return "Notifications"
        case .ready:
            return "You’re all set"
        case .goalValidation:
            return "Your plan is ready"
        case .socialProof:
            return "Food App provides long-term results"
        case .challenge:
            return "What's your biggest challenge?"
        case .experience:
            return "Have you tried calorie counting before?"
        case .howItWorks:
            return "Why Food App's approach works"
        case .challengeInsight:
            return ""
        }
    }

    var subhead: String {
        switch self {
        case .welcome:
            return "Set up tracking in under 2 minutes."
        case .goal:
            return "We’ll use this to set your calorie and macro direction."
        case .age:
            return "We will use this to calulate BMI"
        case .baseline:
            return "Add your profile details so calorie estimates are personalized."
        case .activity:
            return "Choose your typical day, not your best day."
        case .pace:
            return "Consistency beats speed. Pick a pace you can sustain."
        case .preferencesOptional:
            return ""
        case .planPreview:
            return "Here is your starting target. You can adjust this later."
        case .account:
            return "Create or connect an account to keep your progress synced."
        case .permissions:
            return "Optional. Sync activity automatically — you can change this later in Settings."
        case .notificationsPermission:
            return "Optional. Helpful reminders to stay consistent — you can change this later in Settings."
        case .ready:
            return "You’re ready to log your first meal."
        case .goalValidation:
            return "Based on your profile, here’s your starting target."
        case .socialProof:
            return ""
        case .challenge:
            return ""
        case .experience:
            return ""
        case .howItWorks:
            return ""
        case .challengeInsight:
            return ""
        }
    }
}

enum SexOption: String, CaseIterable, Identifiable, Codable {
    case male
    case female
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .other: return "Other"
        }
    }
}

enum ActivityChoice: String, CaseIterable, Identifiable, Codable {
    case mostlySitting
    case lightlyActive
    case moderatelyActive
    case veryActive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mostlySitting: return "Mostly sitting"
        case .lightlyActive: return "Lightly active"
        case .moderatelyActive: return "Moderately active"
        case .veryActive: return "Very active"
        }
    }

    var apiValue: ActivityLevelOption {
        switch self {
        case .mostlySitting: return .low
        case .lightlyActive, .moderatelyActive: return .moderate
        case .veryActive: return .high
        }
    }
}

enum PaceChoice: String, CaseIterable, Identifiable, Codable {
    case conservative
    case balanced
    case aggressive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conservative: return "Conservative"
        case .balanced: return "Balanced"
        case .aggressive: return "Aggressive"
        }
    }
}

/// A multi-select chip option that can be rendered by `OnboardingChipSelector`.
/// Both diet preferences and allergies conform.
protocol ChipOption: Identifiable, Hashable {
    var title: String { get }
}

enum PreferenceChoice: String, CaseIterable, Identifiable, Hashable, Codable, ChipOption {
    case highProtein = "high_protein"
    case vegetarian
    case vegan
    case pescatarian
    case lowCarb = "low_carb"
    case keto
    case glutenFree = "gluten_free"
    case dairyFree = "dairy_free"
    case halal
    case lowSodium = "low_sodium"
    case mediterranean
    case noPreference = "no_preference"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highProtein: return "High protein"
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .pescatarian: return "Pescatarian"
        case .lowCarb: return "Low carb"
        case .keto: return "Keto"
        case .glutenFree: return "Gluten free"
        case .dairyFree: return "Dairy free"
        case .halal: return "Halal"
        case .lowSodium: return "Low sodium"
        case .mediterranean: return "Mediterranean"
        case .noPreference: return "No preference"
        }
    }
}

/// Common food allergens shown as multi-select chips in OB06 and the Profile.
///
/// IMPORTANT: the `matchTokens` here are mirrored on the backend in
/// `backend/src/services/dietaryConflictService.ts`. Backend is the
/// authoritative source for actual conflict detection; the iOS list is
/// used only for client-side preview before the backend response lands.
/// If you edit one list, edit the other.
enum AllergyChoice: String, CaseIterable, Identifiable, Hashable, Codable, ChipOption {
    case peanuts
    case treeNuts = "tree_nuts"
    case gluten
    case dairy
    case eggs
    case shellfish
    case fish
    case soy
    case sesame

    var id: String { rawValue }

    var title: String {
        switch self {
        case .peanuts: return "Peanuts"
        case .treeNuts: return "Tree nuts"
        case .gluten: return "Gluten / wheat"
        case .dairy: return "Dairy"
        case .eggs: return "Eggs"
        case .shellfish: return "Shellfish"
        case .fish: return "Fish"
        case .soy: return "Soy"
        case .sesame: return "Sesame"
        }
    }

    /// SF Symbol icon for chip/list rendering. One per case so users can
    /// scan the list visually rather than reading every label.
    var systemImage: String {
        switch self {
        case .peanuts:   return "circle.hexagongrid.fill"
        case .treeNuts:  return "tree.fill"
        case .gluten:    return "leaf.fill"
        case .dairy:     return "drop.fill"
        case .eggs:      return "oval.portrait.fill"
        case .shellfish: return "drop.triangle.fill"
        case .fish:      return "fish.fill"
        case .soy:       return "leaf.circle.fill"
        case .sesame:    return "circle.grid.3x3.fill"
        }
    }

    /// Lowercase substrings used for client-side conflict preview against parsed
    /// food item names. The backend has the authoritative version.
    var matchTokens: [String] {
        switch self {
        case .peanuts: return ["peanut"]
        case .treeNuts: return ["almond", "walnut", "cashew", "pecan", "pistachio", "hazelnut", "macadamia", "brazil nut"]
        case .gluten: return ["bread", "pasta", "wheat", "flour", "noodle", "barley", "rye", "couscous", "cracker", "pita", "tortilla", "bagel", "pretzel"]
        case .dairy: return ["milk", "cheese", "butter", "cream", "yogurt", "yoghurt", "ice cream", "whey", "paneer", "ghee"]
        case .eggs: return ["egg", "omelet", "omelette", "frittata", "quiche"]
        case .shellfish: return ["shrimp", "prawn", "lobster", "crab", "crawfish", "scallop", "clam", "oyster", "mussel"]
        case .fish: return ["salmon", "tuna", "cod", "tilapia", "mackerel", "trout", "halibut", "sardine", "anchovy", "bass"]
        case .soy: return ["soy", "tofu", "edamame", "tempeh", "miso", "soybean"]
        case .sesame: return ["sesame", "tahini"]
        }
    }
}

enum ExperienceChoice: String, CaseIterable, Identifiable, Codable {
    case newToIt
    case triedButQuit
    case currentlyCounting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newToIt: return "I'm new to calorie counting"
        case .triedButQuit: return "I've tried it before but quit"
        case .currentlyCounting: return "I'm currently counting"
        }
    }

    var icon: String {
        switch self {
        case .newToIt: return "flame"
        case .triedButQuit: return "arrow.uturn.backward.circle"
        case .currentlyCounting: return "number.square"
        }
    }
}

enum ChallengeChoice: String, CaseIterable, Identifiable, Codable {
    case portionControl
    case snacking
    case eatingOut
    case inconsistentMeals
    case emotionalEating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portionControl: return "Portion control"
        case .snacking: return "Late-night snacking"
        case .eatingOut: return "Eating out too often"
        case .inconsistentMeals: return "Inconsistent meals"
        case .emotionalEating: return "Emotional eating"
        }
    }

    var subtitle: String {
        switch self {
        case .portionControl: return "Hard to know the right serving size"
        case .snacking: return "Cravings that undo my progress"
        case .eatingOut: return "Restaurant meals are hard to track"
        case .inconsistentMeals: return "I skip meals or eat at random times"
        case .emotionalEating: return "I eat when stressed or bored"
        }
    }

    var icon: String {
        switch self {
        case .portionControl: return "chart.pie"
        case .snacking: return "moon.stars"
        case .eatingOut: return "fork.knife.circle"
        case .inconsistentMeals: return "clock.arrow.2.circlepath"
        case .emotionalEating: return "heart.circle"
        }
    }
}

enum AccountProvider: String, Codable {
    case apple
    case google
}
