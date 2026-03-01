import Foundation

enum L10n {
    static func tr(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, value: fallback, comment: "")
    }

    static func format(_ key: String, _ fallback: String, _ args: CVarArg...) -> String {
        String(format: tr(key, fallback), locale: Locale.current, arguments: args)
    }

    static let networkOnline = tr("network.status.online", "Online")
    static let networkOffline = tr("network.status.offline", "Offline")
    static let networkLimited = tr("network.status.limited", "Connected (limited network)")
    static let themeToggleLabel = tr("theme.toggle.label", "Toggle appearance")
    static let themeDarkLabel = tr("theme.mode.dark", "Dark")
    static let themeLightLabel = tr("theme.mode.light", "Light")

    static let onboardingTitle = tr("onboarding.title", "Welcome")
    static let onboardingGoalSection = tr("onboarding.goal.section", "Goal")
    static let onboardingGoalLabel = tr("onboarding.goal.label", "Goal")
    static let onboardingPreferencesSection = tr("onboarding.preferences.section", "Preferences")
    static let onboardingDietPreferencePlaceholder = tr("onboarding.diet.placeholder", "Diet preference (e.g. vegetarian)")
    static let onboardingDietPreferenceLabel = tr("onboarding.diet.label", "Diet preference")
    static let onboardingAllergiesPlaceholder = tr("onboarding.allergies.placeholder", "Allergies (comma-separated)")
    static let onboardingAllergiesLabel = tr("onboarding.allergies.label", "Allergies")
    static let onboardingUnitsLabel = tr("onboarding.units.label", "Units")
    static let onboardingActivityLabel = tr("onboarding.activity.label", "Activity level")
    static let onboardingCompleteButton = tr("onboarding.complete.button", "Complete Onboarding")
    static let onboardingStatusSection = tr("onboarding.status.section", "Status")
    static let onboardingSubmitA11yHint = tr("onboarding.submit.a11y_hint", "Submits your preferences and finishes onboarding.")
    static let onboardingSavedTargetsFormat = tr("onboarding.saved_targets.format", "Saved targets: %d kcal/day")
    static let onboardingGoalLose = tr("onboarding.goal.option.lose", "Lose")
    static let onboardingGoalMaintain = tr("onboarding.goal.option.maintain", "Maintain")
    static let onboardingGoalGain = tr("onboarding.goal.option.gain", "Gain")
    static let onboardingUnitsMetric = tr("onboarding.units.option.metric", "Metric")
    static let onboardingUnitsImperial = tr("onboarding.units.option.imperial", "Imperial")
    static let onboardingActivityLow = tr("onboarding.activity.option.low", "Low")
    static let onboardingActivityModerate = tr("onboarding.activity.option.moderate", "Moderate")
    static let onboardingActivityHigh = tr("onboarding.activity.option.high", "High")
    static let onboardingSplashBrandName = tr("onboarding.splash.brand", "NutriLog")
    static let onboardingSplashTrackingLabel = tr("onboarding.splash.tracking_label", "AI-POWERED TRACKING")
    static let onboardingSplashTitle = tr("onboarding.splash.title", "Log food like\na note.")
    static let onboardingSplashSubtitle = tr("onboarding.splash.subtitle", "Simply snap a photo or type what you ate. We handle the math instantly.")
    static let onboardingSplashStartButton = tr("onboarding.splash.start_button", "Start Tracking")
    static let onboardingSplashStartHint = tr("onboarding.splash.start_hint", "Opens onboarding questions to configure your goals and preferences.")
    static let onboardingSplashImageA11y = tr("onboarding.splash.image_a11y", "Healthy food bowl")

    static let foodLogTitle = tr("main.title", "Food Log")
    static let foodInputPrompt = tr("main.food_input.prompt", "What did you eat?")
    static let foodInputHint = tr("main.food_input.hint", "Enter your meal in plain text.")
    static let parseNowButton = tr("main.parse_now.button", "Parse Now")
    static let parseNowHint = tr("main.parse_now.hint", "Parses the current note to estimate nutrition.")
    static let openDetailsButton = tr("main.open_details.button", "Open Details Drawer")
    static let openDetailsHint = tr("main.open_details.hint", "Shows parsed items and editable details.")
    static let saveLogButton = tr("main.save_log.button", "Save Log")
    static let saveLogHint = tr("main.save_log.hint", "Saves this parsed log using an idempotency key.")
    static let retryLastSaveButton = tr("main.retry_last_save.button", "Retry Last Save")
    static let retryLastSaveHint = tr("main.retry_last_save.hint", "Retries the previous save safely using the same idempotency key.")
    static let parseInProgress = tr("main.parse.in_progress", "Parsing...")
    static let saveInProgress = tr("main.save.in_progress", "Saving...")
    static let retrySucceededPrefix = tr("main.save.prefix.retry", "Retry succeeded safely")
    static let savedSuccessfullyPrefix = tr("main.save.prefix.saved", "Saved successfully")
    static let saveSuccessWithTtlFormat = tr("main.save.success.with_ttl.format", "%@. Log ID: %@ • Day: %@ • TTL %.1fs")
    static let saveSuccessWithoutTtlFormat = tr("main.save.success.without_ttl.format", "%@. Log ID: %@ • Day: %@")
    static let saveDisabledNeedsClarification = tr("main.save.disabled_needs_clarification", "Save is disabled until clarification is resolved or escalated.")
    static let offlineBanner = tr("main.network.offline_banner", "You are offline. Keep editing safely. Reconnect, then tap Retry Last Save (same idempotency key) to avoid duplicate logs.")
    static let environmentLabelFormat = tr("main.debug.environment.format", "Environment: %@")
    static let baseURLLabelFormat = tr("main.debug.base_url.format", "Base URL: %@")
    static let startTypingHint = tr("main.start_typing_hint", "Start typing and we'll estimate calories/macros here.")
    static let timeToLogFormat = tr("main.time_to_log.format", "Time to log: %.1fs")
    static let idempotencyKeyFormat = tr("main.idempotency_key.format", "Idempotency key: %@")
    static let estimatedTotalsTitle = tr("main.estimated_totals.title", "Estimated Totals")
    static let totalsCalories = tr("main.totals.calories", "Calories")
    static let totalsProtein = tr("main.totals.protein", "Protein")
    static let totalsCarbs = tr("main.totals.carbs", "Carbs")
    static let totalsFat = tr("main.totals.fat", "Fat")
    static let totalsEditedHint = tr("main.totals.edited_hint", "Totals currently reflect your edits in the details drawer.")
    static let clarificationNeededTitle = tr("main.clarification_needed.title", "Clarification Needed")
    static let escalateParseButton = tr("main.escalate_parse.button", "Escalate Parse")
    static let escalateParseHint = tr("main.escalate_parse.hint", "Uses escalation AI route when clarification is needed.")
    static let escalatingInProgress = tr("main.escalate.in_progress", "Escalating parse...")
    static let parseClarificationHint = tr("main.parse.clarification_hint", "Clarification needed. Open Details Drawer to review questions.")
    static let escalationBudgetReason = tr("main.escalation.disabled_reason.budget", "Escalation is currently unavailable because daily AI budget is exhausted.")
    static let escalationConfigReason = tr("main.escalation.disabled_reason.config", "Escalation is disabled on the backend configuration.")
    static let escalationCompleted = tr("main.info.escalation_completed", "Escalation completed. Review updated items and save.")
    static let daySummaryTitle = tr("main.day_summary.title", "Day Summary")
    static let daySummaryDateLabel = tr("main.day_summary.date.label", "Date")
    static let retrySummaryButton = tr("main.day_summary.retry_button", "Retry Summary")
    static let loadingDaySummary = tr("main.day_summary.loading", "Loading day summary...")
    static let daySummaryZeroTotals = tr("main.day_summary.zero_totals", "Totals are currently zero for this day.")
    static let remainingFormat = tr("main.day_summary.remaining.format", "Remaining: %.1f %@")
    static let parseDetailsTitle = tr("main.parse_details.title", "Parse Details")
    static let doneButton = tr("common.done.button", "Done")
    static let parseMetadataTitle = tr("main.parse_metadata.title", "Parse Metadata")
    static let routeFormat = tr("main.parse_metadata.route.format", "Route: %@")
    static let parseRequestIdFormat = tr("main.parse_metadata.request_id.format", "Parse Request ID: %@")
    static let parseVersionFormat = tr("main.parse_metadata.version.format", "Parse Version: %@")
    static let confidenceFormat = tr("main.parse_metadata.confidence.format", "Confidence: %.3f")
    static let clarificationQuestionsTitle = tr("main.clarification_questions.title", "Clarification Questions")
    static let editableItemsTitle = tr("main.editable_items.title", "Editable Items")
    static let itemNamePlaceholder = tr("main.editable_items.item_name.placeholder", "Item name")
    static let quantityFormat = tr("main.editable_items.quantity.format", "Quantity: %.2f")
    static let unitPlaceholder = tr("main.editable_items.unit.placeholder", "Unit")
    static let nutritionLineFormat = tr("main.editable_items.nutrition.format", "%d kcal • P %.1fg • C %.1fg • F %.1fg")
    static let saveActionsTitle = tr("main.save_actions.title", "Save Actions")
    static let saveContractPreviewTitle = tr("main.save_contract_preview.title", "Save Contract Preview")
    static let parseFirstHint = tr("main.parse_first_hint", "Parse something first to open details.")
    static let resetOnboardingButton = tr("main.reset_onboarding.button", "Reset Onboarding State")
    static let confidenceLabel = tr("main.confidence.label", "Confidence")
    static let fallbackUsedLabel = tr("main.route.fallback", "Fallback used")
    static let cacheEstimateLabel = tr("main.route.cache", "Cached estimate")
    static let deterministicEstimateLabel = tr("main.route.deterministic", "Deterministic estimate")
    static let aliasEstimateLabel = tr("main.route.alias", "Alias estimate")
    static let aiEstimateLabel = tr("main.route.ai", "AI estimate")
    static let fatSecretEstimateLabel = tr("main.route.fatsecret", "Food Database estimate")
    static let unresolvedEstimateLabel = tr("main.route.unresolved", "Awaiting estimate")
    static let escalatedEstimateLabel = tr("main.route.escalated", "Escalated estimate")
    static let lowConfidenceLabel = tr("main.route.low_confidence", "Low confidence")
    static let parseConnectivityIssueLabel = tr("main.route.parse_connectivity_issue", "Can't reach backend")
    static let parseStillProcessingLabel = tr("main.parse.still_processing", "Still parsing. Keep typing or retry in a moment.")

    static let noNetworkParse = tr("main.error.no_network_parse", "No network connection. Your note is safe. Reconnect and tap Parse Now.")
    static let noNetworkSave = tr("main.error.no_network_save", "No network connection. Keep editing; when back online tap Retry Last Save.")
    static let noNetworkRetry = tr("main.error.no_network_retry", "Still offline. Reconnect, then tap Retry Last Save.")
    static let noNetworkEscalate = tr("main.error.no_network_escalate", "No network connection. Reconnect and tap Escalate Parse.")
    static let noNetworkSummary = tr("main.error.no_network_summary", "Offline. Reconnect and tap Retry Summary to refresh.")
    static let parseBeforeEscalation = tr("main.error.parse_before_escalation", "Parse something first before escalation.")
    static let escalationNotRequired = tr("main.error.escalation_not_required", "Escalation is only needed when clarification is required.")
    static let escalationBudgetBlocked = tr("main.error.escalation_budget_blocked", "Escalation is unavailable because budget is exceeded.")
    static let parseNeedsClarificationBeforeSave = tr("main.error.parse_needs_clarification_before_save", "This parse still needs clarification. Resolve clarification first, then save.")
    static let parseBeforeSave = tr("main.error.parse_before_save", "Parse the note first before saving.")
    static let noPreviousRetry = tr("main.error.no_previous_retry", "No previous save attempt is available to retry.")
    static let authSessionExpired = tr("main.error.auth_session_expired", "Session expired. Please sign in again.")
    static let daySummaryProfileNotFound = tr("main.error.day_summary_profile_not_found", "Complete onboarding first to view day summary.")
    static let daySummaryInvalidInput = tr("main.error.day_summary_invalid_input", "Selected date is invalid. Please pick another date.")
    static let daySummaryNetworkFailure = tr("main.error.day_summary_network_failure", "Network issue while loading day summary.")
    static let daySummaryFailure = tr("main.error.day_summary_failure", "Failed to load day summary.")
    static let saveIdempotencyConflict = tr("main.error.save_idempotency_conflict", "Save key conflict: this retry key was used with different data. Tap Save Log to create a fresh key.")
    static let saveInvalidParseReference = tr("main.error.save_invalid_parse_reference", "This parsed draft is stale. Parse again, then save.")
    static let saveMissingIdempotency = tr("main.error.save_missing_idempotency", "Save request is missing idempotency key. Tap Save Log again.")
    static let saveFailure = tr("main.error.save_failure", "Save failed.")
    static let parseNetworkFailure = tr("main.error.parse_network_failure", "Network issue while parsing. Your note is safe. Reconnect and tap Parse Now.")
    static let parseFailure = tr("main.error.parse_failure", "Parse failed.")
    static let escalationDisabledNow = tr("main.error.escalation_disabled_now", "Escalation is disabled on backend right now.")
    static let escalationBudgetExceeded = tr("main.error.escalation_budget_exceeded", "Escalation blocked: daily AI budget is exhausted.")
    static let escalationNoLongerNeeded = tr("main.error.escalation_no_longer_needed", "Escalation is no longer needed. Parse already has enough confidence.")
    static let escalationInvalidParseReference = tr("main.error.escalation_invalid_parse_reference", "This parse reference is stale. Parse again, then escalate if still needed.")
    static let escalationNetworkFailure = tr("main.error.escalation_network_failure", "Network issue during escalation. Please retry.")
    static let escalationFailure = tr("main.error.escalation_failure", "Escalation failed.")
    static let saveNetworkFailure = tr("main.error.save_network_failure", "Network issue while saving. Draft was preserved. Use Retry Last Save to safely retry without duplicate logs.")
    static let recoveredPendingSave = tr("main.info.recovered_pending_save", "Recovered pending save draft. Tap Retry Last Save when ready.")
    static let apiErrorBannerHint = tr("content.error_banner.hint", "API error banner")

    static func goalLabel(_ option: GoalOption) -> String {
        switch option {
        case .lose: onboardingGoalLose
        case .maintain: onboardingGoalMaintain
        case .gain: onboardingGoalGain
        }
    }

    static func unitsLabel(_ option: UnitsOption) -> String {
        switch option {
        case .metric: onboardingUnitsMetric
        case .imperial: onboardingUnitsImperial
        }
    }

    static func activityLabel(_ option: ActivityLevelOption) -> String {
        switch option {
        case .low: onboardingActivityLow
        case .moderate: onboardingActivityModerate
        case .high: onboardingActivityHigh
        }
    }

    static func onboardingSavedTargets(_ calorieTarget: Int) -> String {
        format("onboarding.saved_targets.format", "Saved targets: %d kcal/day", calorieTarget)
    }

    static func environmentLabel(_ environment: String) -> String {
        format("main.debug.environment.format", "Environment: %@", environment)
    }

    static func baseURLLabel(_ baseURL: String) -> String {
        format("main.debug.base_url.format", "Base URL: %@", baseURL)
    }

    static func timeToLog(_ seconds: Double) -> String {
        format("main.time_to_log.format", "Time to log: %.1fs", seconds)
    }

    static func idempotencyKey(_ key: String) -> String {
        format("main.idempotency_key.format", "Idempotency key: %@", key)
    }

    static func remainingLabel(_ remaining: Double, unit: String) -> String {
        format("main.day_summary.remaining.format", "Remaining: %.1f %@", remaining, unit)
    }

    static func routeDisplayName(_ route: String) -> String {
        switch route {
        case "cache":
            return cacheEstimateLabel
        case "deterministic":
            return deterministicEstimateLabel
        case "alias":
            return aliasEstimateLabel
        case "fatsecret":
            return fatSecretEstimateLabel
        case "gemini":
            return aiEstimateLabel
        case "unresolved":
            return unresolvedEstimateLabel
        case "escalation":
            return escalatedEstimateLabel
        default:
            return route
        }
    }

    static func routeLabel(_ route: String) -> String {
        let displayName = routeDisplayName(route)
        return format("main.parse_metadata.route.format", "Route: %@", displayName)
    }

    static func parseRequestIDLabel(_ parseRequestID: String) -> String {
        format("main.parse_metadata.request_id.format", "Parse Request ID: %@", parseRequestID)
    }

    static func parseVersionLabel(_ parseVersion: String) -> String {
        format("main.parse_metadata.version.format", "Parse Version: %@", parseVersion)
    }

    static func parseConfidenceLabel(_ confidence: Double) -> String {
        format("main.parse_metadata.confidence.format", "Confidence: %.3f", confidence)
    }

    static func quantityLabel(_ quantity: Double) -> String {
        format("main.editable_items.quantity.format", "Quantity: %.2f", quantity)
    }

    static func nutritionLine(calories: Int, protein: Double, carbs: Double, fat: Double) -> String {
        format(
            "main.editable_items.nutrition.format",
            "%d kcal • P %.1fg • C %.1fg • F %.1fg",
            calories,
            protein,
            carbs,
            fat
        )
    }

    static func saveSuccessWithTTL(prefix: String, logID: String, day: String, ttlSeconds: Double) -> String {
        format(
            "main.save.success.with_ttl.format",
            "%@. Log ID: %@ • Day: %@ • TTL %.1fs",
            prefix,
            logID,
            day,
            ttlSeconds
        )
    }

    static func saveSuccessWithoutTTL(prefix: String, logID: String, day: String) -> String {
        format(
            "main.save.success.without_ttl.format",
            "%@. Log ID: %@ • Day: %@",
            prefix,
            logID,
            day
        )
    }
}
