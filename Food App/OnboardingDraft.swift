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

