import Foundation

enum GoalOption: String, CaseIterable, Identifiable, Codable {
    case lose
    case maintain
    case gain

    var id: String { rawValue }
}

enum UnitsOption: String, CaseIterable, Identifiable, Codable {
    case metric
    case imperial

    var id: String { rawValue }
}

enum ActivityLevelOption: String, CaseIterable, Identifiable, Codable {
    case low
    case moderate
    case high

    var id: String { rawValue }
}

struct APIErrorEnvelope: Decodable {
    let error: APIErrorPayload
}

struct APIErrorPayload: Decodable {
    let code: String
    let message: String
    let requestId: String
}

struct HealthResponse: Decodable {
    let status: String
}

struct OnboardingRequest: Encodable {
    let goal: GoalOption
    let dietPreference: String
    let allergies: [String]
    let units: UnitsOption
    let activityLevel: ActivityLevelOption
    let timezone: String
    let age: Int
    let sex: String
    let heightCm: Double
    let weightKg: Double
    let pace: String
    let activityDetail: String?
}

struct OnboardingResponse: Decodable {
    let calorieTarget: Int
    let macroTargets: MacroTargets
}

struct MacroTargets: Decodable {
    let protein: Int
    let carbs: Int
    let fat: Int
}

struct ParseLogRequest: Encodable {
    let text: String
    let loggedAt: String
}

struct ParseLogResponse: Decodable {
    let requestId: String
    let parseRequestId: String
    let parseVersion: String
    let route: String
    let cacheHit: Bool
    let sourcesUsed: [String]?
    let fallbackUsed: Bool
    let fallbackModel: String?
    let budget: ParseBudget
    let needsClarification: Bool
    let clarificationQuestions: [String]
    let reasonCodes: [String]?
    let retryAfterSeconds: Int?
    let parseDurationMs: Double
    let loggedAt: String
    let confidence: Double
    let totals: NutritionTotals
    let items: [ParsedFoodItem]
    let assumptions: [String]
    let cacheDebug: ParseCacheDebugInfo?
    let inputKind: String?
    let extractedText: String?
    let imageMeta: ParseImageMeta?
    let visionModel: String?
    let visionFallbackUsed: Bool?
}

struct ParseImageMeta: Decodable {
    let mimeType: String
    let width: Int?
    let height: Int?
    let bytes: Int
}

struct ParseCacheDebugInfo: Decodable {
    let scope: String
    let normalizedText: String
    let textHash: String
}

struct ParseBudget: Decodable {
    let dailyLimitUsd: Double
    let dailyUsedTodayUsd: Double
    let userSoftCapUsd: Double
    let userUsedTodayUsd: Double
    let userSoftCapExceeded: Bool
    let fallbackAllowed: Bool?
    let escalationAllowed: Bool?
}

struct ParsedFoodItem: Codable, Hashable {
    let name: String
    let quantity: Double
    let unit: String
    let grams: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let nutritionSourceId: String
    let originalNutritionSourceId: String?
    let sourceFamily: String?
    let matchConfidence: Double
    let amount: Double?
    let unitNormalized: String?
    let gramsPerUnit: Double?
    let needsClarification: Bool?
    let manualOverride: Bool?
    let servingOptions: [ParsedServingOption]?
    let foodDescription: String?
    let explanation: String?

    init(
        name: String,
        quantity: Double,
        unit: String,
        grams: Double,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        nutritionSourceId: String,
        originalNutritionSourceId: String? = nil,
        sourceFamily: String? = nil,
        matchConfidence: Double,
        amount: Double? = nil,
        unitNormalized: String? = nil,
        gramsPerUnit: Double? = nil,
        needsClarification: Bool? = nil,
        manualOverride: Bool? = nil,
        servingOptions: [ParsedServingOption]? = nil,
        foodDescription: String? = nil,
        explanation: String? = nil
    ) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.grams = grams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.nutritionSourceId = nutritionSourceId
        self.originalNutritionSourceId = originalNutritionSourceId
        self.sourceFamily = sourceFamily
        self.matchConfidence = matchConfidence
        self.amount = amount
        self.unitNormalized = unitNormalized
        self.gramsPerUnit = gramsPerUnit
        self.needsClarification = needsClarification
        self.manualOverride = manualOverride
        self.servingOptions = servingOptions
        self.foodDescription = foodDescription
        self.explanation = explanation
    }
}

struct ParsedServingOption: Codable, Hashable {
    let servingId: String?
    let label: String
    let quantity: Double
    let unit: String
    let grams: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let nutritionSourceId: String
}

struct NutritionTotals: Codable, Hashable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

struct EscalateParseRequest: Encodable {
    let parseRequestId: String
    let loggedAt: String
}

struct EscalateParseResponse: Decodable {
    let requestId: String
    let parseRequestId: String
    let parseVersion: String
    let route: String
    let escalationUsed: Bool
    let sourcesUsed: [String]?
    let model: String
    let budget: ParseBudget
    let parseDurationMs: Double
    let loggedAt: String
    let confidence: Double
    let totals: NutritionTotals
    let items: [ParsedFoodItem]
    let assumptions: [String]
}

struct SaveLogRequest: Codable {
    let parseRequestId: String
    let parseVersion: String
    let parsedLog: SaveLogBody
}

struct SaveLogBody: Codable {
    let rawText: String
    let loggedAt: String
    let inputKind: String?
    let imageRef: String?
    let confidence: Double
    let totals: NutritionTotals
    let sourcesUsed: [String]?
    let assumptions: [String]?
    let items: [SaveParsedFoodItem]
}

struct SaveManualOverride: Codable, Hashable {
    let enabled: Bool
    let reason: String?
    let editedFields: [String]
}

struct SaveParsedFoodItem: Codable, Hashable {
    let name: String
    let quantity: Double
    let amount: Double?
    let unit: String
    let unitNormalized: String?
    let grams: Double
    let gramsPerUnit: Double?
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let nutritionSourceId: String
    let originalNutritionSourceId: String?
    let sourceFamily: String?
    let matchConfidence: Double
    let needsClarification: Bool?
    let manualOverride: SaveManualOverride?
}

struct SaveLogResponse: Decodable {
    let logId: String
    let status: String
}

/// PATCH /v1/logs/:id — parse references are optional so the client-side
/// quantity fast path (no new parse) can reuse the same schema.
struct PatchLogRequest: Codable {
    let parseRequestId: String?
    let parseVersion: String?
    let parsedLog: PatchLogBody
}

/// Mirrors `SaveLogBody` but with `loggedAt` optional — when editing an
/// existing food_log we want the backend to preserve the original timestamp
/// instead of overwriting it with "now".
struct PatchLogBody: Codable {
    let rawText: String
    let loggedAt: String?
    let inputKind: String?
    let imageRef: String?
    let confidence: Double
    let totals: NutritionTotals
    let sourcesUsed: [String]?
    let assumptions: [String]?
    let items: [SaveParsedFoodItem]
}

struct HealthActivityRequest: Codable {
    let date: String
    let steps: Double
    let activeEnergyKcal: Double
}

struct HealthActivityResponse: Decodable {
    let date: String
    let steps: Double
    let activeEnergyKcal: Double
}

struct DaySummaryResponse: Decodable {
    let date: String
    let totals: NutritionTotals
    let targets: NutritionTotals
    let remaining: NutritionTotals
}

struct DayLogsResponse: Codable {
    let date: String
    let timezone: String
    let logs: [DayLogEntry]
}

struct DayLogEntry: Codable, Identifiable {
    let id: String
    let loggedAt: String
    let rawText: String
    let inputKind: String
    let confidence: Double
    let totals: NutritionTotals
    let items: [DayLogItem]
}

struct DayLogItem: Codable, Identifiable {
    let id: String
    let foodName: String
    let quantity: Double
    let amount: Double
    let unit: String
    let unitNormalized: String?
    let grams: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let nutritionSourceId: String
    let sourceFamily: String?
    let matchConfidence: Double
}

struct DayRangeResponse: Decodable {
    let summaries: [DaySummaryResponse]
    let logs: [DayLogsResponse]
}

struct ProgressResponse: Decodable {
    let from: String
    let to: String
    let timezone: String
    let days: [ProgressDayPoint]
    let streaks: ProgressStreaks
    let weeklyDelta: ProgressWeeklyDelta
}

struct ProgressDayPoint: Decodable, Identifiable {
    let date: String
    let totals: NutritionTotals
    let targets: NutritionTotals
    let remaining: NutritionTotals
    let hasLogs: Bool
    let logsCount: Int
    let adherence: ProgressAdherence

    var id: String { date }
}

struct ProgressAdherence: Decodable {
    let caloriesPct: Double
    let proteinPct: Double
    let carbsPct: Double
    let fatPct: Double
}

struct ProgressStreaks: Decodable {
    let currentDays: Int
    let longestDays: Int
}

struct ProgressWeeklyDelta: Decodable {
    let calories: ProgressMetricDelta
    let protein: ProgressMetricDelta
    let carbs: ProgressMetricDelta
    let fat: ProgressMetricDelta
}

struct ProgressMetricDelta: Decodable {
    let currentAvg: Double
    let previousAvg: Double
    let delta: Double
    let deltaPct: Double?
}

struct AdminFeatureFlags: Codable {
    let geminiEnabled: Bool
}

struct AdminFeatureFlagsResponse: Decodable {
    let isAdmin: Bool
    let flags: AdminFeatureFlags?
}

struct AdminFeatureFlagsUpdateRequest: Encodable {
    let geminiEnabled: Bool
}

// MARK: - Tracking Accuracy

struct TrackingAccuracyResponse: Decodable {
    let period: String
    let entryCount: Int
    let averageConfidence: Double
    let tier: String
    let lowConfidenceEntries: [LowConfidenceEntry]
}

struct LowConfidenceEntry: Decodable, Identifiable {
    var id: String { rawText + loggedAt }
    let rawText: String
    let confidence: Double
    let loggedAt: String
    let suggestion: String
}
