import Foundation

/// L10n — user-facing strings.
///
/// Voice rules (locked 2026-05-01, see `docs/CONTENT_AUDIT_2026-05-01.md`):
/// - Plain, direct, with a warm undertone.
/// - No exclamation points.
/// - No marketing buzz ("smart AI-powered", "unlock your potential").
/// - No engineer jargon (idempotency, parse reference, save contract,
///   route, schema). The user doesn't care.
/// - Sentence case for everything except branded nouns. iOS 2026
///   convention.
/// - Errors describe what happened from the user's POV, then what to do
///   about it. Never blame the user.
///
/// Hardcoded inline strings still living in `OB*.swift` screens are being
/// migrated here over the same content-refresh sweep.
enum L10n {
    static func tr(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, value: fallback, comment: "")
    }

    static func format(_ key: String, _ fallback: String, _ args: CVarArg...) -> String {
        String(format: tr(key, fallback), locale: Locale.current, arguments: args)
    }

    static let networkOnline = tr("network.status.online", "Online")
    static let networkOffline = tr("network.status.offline", "Offline")
    static let networkLimited = tr("network.status.limited", "Limited connection")

    static let onboardingTitle = tr("onboarding.title", "Welcome")
    static let onboardingGoalSection = tr("onboarding.goal.section", "Goal")
    static let onboardingGoalLabel = tr("onboarding.goal.label", "Goal")
    static let onboardingPreferencesSection = tr("onboarding.preferences.section", "Preferences")
    static let onboardingDietPreferencePlaceholder = tr("onboarding.diet.placeholder", "Diet preference (e.g., vegetarian)")
    static let onboardingDietPreferenceLabel = tr("onboarding.diet.label", "Diet preference")
    static let onboardingAllergiesPlaceholder = tr("onboarding.allergies.placeholder", "Allergies — separate with commas")
    static let onboardingAllergiesLabel = tr("onboarding.allergies.label", "Allergies")
    static let onboardingUnitsLabel = tr("onboarding.units.label", "Units")
    static let onboardingActivityLabel = tr("onboarding.activity.label", "Activity level")
    static let onboardingCompleteButton = tr("onboarding.complete.button", "Finish setup")
    static let onboardingStatusSection = tr("onboarding.status.section", "Status")
    static let onboardingSubmitA11yHint = tr("onboarding.submit.a11y_hint", "Saves your preferences and finishes setup.")
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
    static let onboardingSplashTrackingLabel = tr("onboarding.splash.tracking_label", "AI-powered tracking")
    static let onboardingSplashTitle = tr("onboarding.splash.title", "Log your food.\nWithout the effort.")
    static let onboardingSplashSubtitle = tr("onboarding.splash.subtitle", "")
    static let onboardingSplashStartButton = tr("onboarding.splash.start_button", "Get started")
    static let onboardingSplashStartHint = tr("onboarding.splash.start_hint", "Sets your goals and preferences.")
    static let onboardingSplashImageA11y = tr("onboarding.splash.image_a11y", "Healthy food bowl")
    static let onboardingSplashExistingAccountButton = tr("onboarding.splash.existing_account_button", "Sign in")

    // MARK: - OB08 Account screen
    static let onboardingAccountSubtitle = tr("onboarding.account.subtitle", "Save your progress.\nUnlock your plan.")
    static let onboardingAccountFeatureLoggingTitle = tr("onboarding.account.feature.logging.title", "AI-powered logging")
    static let onboardingAccountFeatureLoggingSubtitle = tr("onboarding.account.feature.logging.subtitle", "Snap, scan, or speak — tracked instantly")
    static let onboardingAccountFeatureProgressTitle = tr("onboarding.account.feature.progress.title", "Progress that adapts")
    static let onboardingAccountFeatureProgressSubtitle = tr("onboarding.account.feature.progress.subtitle", "Your plan updates as your results do")
    static let onboardingAccountFeatureSecureTitle = tr("onboarding.account.feature.secure.title", "Private & secure")
    static let onboardingAccountFeatureSecureSubtitle = tr("onboarding.account.feature.secure.subtitle", "Your data is encrypted and only yours")
    static let onboardingAccountSocialProof = tr("onboarding.account.social_proof", "Trusted by 5,000+ people")
    static let onboardingAccountGoogleLabel = tr("onboarding.account.button.google", "Google")
    static let onboardingAccountAppleLabel = tr("onboarding.account.button.apple", "Apple")
    static let onboardingAccountAppleUnavailable = tr("onboarding.account.apple_unavailable", "Apple sign-in is coming soon. Use Google for now.")
    static let onboardingAccountConnecting = tr("onboarding.account.connecting", "Connecting…")

    static let foodLogTitle = tr("main.title", "Food Log")
    static let foodInputPrompt = tr("main.food_input.prompt", "What did you eat?")
    static let foodInputHint = tr("main.food_input.hint", "Type what you ate, plain English.")
    static let parseNowButton = tr("main.parse_now.button", "Estimate")
    static let parseNowHint = tr("main.parse_now.hint", "Estimates calories and macros for what you typed.")
    static let openDetailsButton = tr("main.open_details.button", "View details")
    static let openDetailsHint = tr("main.open_details.hint", "Shows each food item — edit if needed.")
    static let saveLogButton = tr("main.save_log.button", "Save")
    static let saveLogHint = tr("main.save_log.hint", "Saves this meal.")
    static let retryLastSaveButton = tr("main.retry_last_save.button", "Retry")
    static let retryLastSaveHint = tr("main.retry_last_save.hint", "Retries the last save without duplicating it.")
    static let retryParseButton = tr("main.retry_parse.button", "Retry estimate")
    static let retryParseHint = tr("main.retry_parse.hint", "Re-estimates calories and macros.")
    static let parseInProgress = tr("main.parse.in_progress", "Estimating…")
    static let saveInProgress = tr("main.save.in_progress", "Saving…")
    static let retrySucceededPrefix = tr("main.save.prefix.retry", "Retry succeeded")
    static let savedSuccessfullyPrefix = tr("main.save.prefix.saved", "Saved")
    static let saveSuccessWithTtlFormat = tr("main.save.success.with_ttl.format", "%@. Log ID: %@ • Day: %@ • TTL %.1fs")
    static let saveSuccessWithoutTtlFormat = tr("main.save.success.without_ttl.format", "%@. Log ID: %@ • Day: %@")
    static let saveDisabledNeedsClarification = tr("main.save.disabled_needs_clarification", "Resolve the questions below before saving.")
    static let offlineBanner = tr("main.network.offline_banner", "You're offline. Your draft is safe — we'll send it when you're back online.")
    static let environmentLabelFormat = tr("main.debug.environment.format", "Environment: %@")
    static let baseURLLabelFormat = tr("main.debug.base_url.format", "Base URL: %@")
    static let startTypingHint = tr("main.start_typing_hint", "Start typing — we'll estimate the calories and macros.")
    static let timeToLogFormat = tr("main.time_to_log.format", "Time to log: %.1fs")
    static let idempotencyKeyFormat = tr("main.idempotency_key.format", "Idempotency key: %@")
    static let estimatedTotalsTitle = tr("main.estimated_totals.title", "Estimated for this meal")
    static let totalsCalories = tr("main.totals.calories", "Calories")
    static let totalsProtein = tr("main.totals.protein", "Protein")
    static let totalsCarbs = tr("main.totals.carbs", "Carbs")
    static let totalsFat = tr("main.totals.fat", "Fat")
    static let totalsEditedHint = tr("main.totals.edited_hint", "Showing your edited values.")
    static let clarificationNeededTitle = tr("main.clarification_needed.title", "Need a bit more info")
    static let escalateParseButton = tr("main.escalate_parse.button", "Get a closer look")
    static let escalateParseHint = tr("main.escalate_parse.hint", "Uses our deeper AI when the quick estimate isn't sure.")
    static let escalatingInProgress = tr("main.escalate.in_progress", "Taking a closer look…")
    static let parseClarificationHint = tr("main.parse.clarification_hint", "We need a few details. Tap View details to answer.")
    static let escalationBudgetReason = tr("main.escalation.disabled_reason.budget", "AI is at its daily limit. Try again tomorrow.")
    static let escalationConfigReason = tr("main.escalation.disabled_reason.config", "AI assistance is off right now.")
    static let escalationCompleted = tr("main.info.escalation_completed", "Got it. Review the updated values and save.")
    static let daySummaryTitle = tr("main.day_summary.title", "Day Summary")
    static let daySummaryDateLabel = tr("main.day_summary.date.label", "Date")
    static let retrySummaryButton = tr("main.day_summary.retry_button", "Retry summary")
    static let loadingDaySummary = tr("main.day_summary.loading", "Loading…")
    static let daySummaryZeroTotals = tr("main.day_summary.zero_totals", "Nothing logged yet today.")
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
    static let parseFirstHint = tr("main.parse_first_hint", "Type a meal first.")
    static let resetOnboardingButton = tr("main.reset_onboarding.button", "Reset onboarding")
    static let confidenceLabel = tr("main.confidence.label", "Confidence")
    static let fallbackUsedLabel = tr("main.route.fallback", "Fallback used")
    static let cacheEstimateLabel = tr("main.route.cache", "From cache")
    static let deterministicEstimateLabel = tr("main.route.deterministic", "Quick estimate")
    static let aliasEstimateLabel = tr("main.route.alias", "Quick estimate")
    static let aiEstimateLabel = tr("main.route.ai", "AI estimate")
    static let unresolvedEstimateLabel = tr("main.route.unresolved", "Awaiting estimate")
    static let escalatedEstimateLabel = tr("main.route.escalated", "Closer look")
    static let lowConfidenceLabel = tr("main.route.low_confidence", "Less sure")
    static let parseConnectivityIssueLabel = tr("main.route.parse_connectivity_issue", "No connection")
    static let parseStillProcessingLabel = tr("main.parse.still_processing", "Still estimating — keep typing or wait a sec.")
    static let parseQueuedLabel = tr("main.parse.queued", "Finishing one estimate. New rows are next.")
    static let parseQueuedShortLabel = tr("main.parse.queued_short", "Queued")
    static let parseRetryShortLabel = tr("main.parse.retry_short", "Retry")

    static let noNetworkParse = tr("main.error.no_network_parse", "You're offline. Your text is safe — reconnect to estimate.")
    static let noNetworkSave = tr("main.error.no_network_save", "You're offline. Keep editing — we'll save when you reconnect.")
    static let noNetworkRetry = tr("main.error.no_network_retry", "Still offline. Reconnect, then tap Retry.")
    static let noNetworkEscalate = tr("main.error.no_network_escalate", "You're offline. Reconnect, then take a closer look.")
    static let noNetworkSummary = tr("main.error.no_network_summary", "You're offline. Reconnect to refresh.")
    static let parseBeforeEscalation = tr("main.error.parse_before_escalation", "Parse something first before escalation.")
    static let escalationNotRequired = tr("main.error.escalation_not_required", "Escalation is only needed when clarification is required.")
    static let escalationBudgetBlocked = tr("main.error.escalation_budget_blocked", "AI is at its daily limit. Try again tomorrow.")
    static let parseNeedsClarificationBeforeSave = tr("main.error.parse_needs_clarification_before_save", "Answer the questions below, then save.")
    static let parseBeforeSave = tr("main.error.parse_before_save", "Type something to save.")
    static let noPreviousRetry = tr("main.error.no_previous_retry", "Nothing to retry.")
    static let authSessionExpired = tr("main.error.auth_session_expired", "You've been signed out. Sign in to keep going.")
    static let daySummaryProfileNotFound = tr("main.error.day_summary_profile_not_found", "Finish setup to see your day.")
    static let daySummaryInvalidInput = tr("main.error.day_summary_invalid_input", "That date isn't valid. Pick another.")
    static let daySummaryNetworkFailure = tr("main.error.day_summary_network_failure", "Couldn't load — connection issue.")
    static let daySummaryFailure = tr("main.error.day_summary_failure", "Couldn't load your day. Tap Retry.")
    static let saveIdempotencyConflict = tr("main.error.save_idempotency_conflict", "Something changed since the last attempt. Tap Save to send the new version.")
    static let saveInvalidParseReference = tr("main.error.save_invalid_parse_reference", "This estimate is out of date. Tap Estimate to refresh, then save.")
    static let saveMissingIdempotency = tr("main.error.save_missing_idempotency", "Tap Save again to send your meal.")
    static let saveFailure = tr("main.error.save_failure", "Couldn't save. Tap Retry.")
    static let parseNetworkFailure = tr("main.error.parse_network_failure", "Couldn't reach the server — your text is safe. Tap Estimate when you're back online.")
    static let parseRateLimited = tr("main.error.parse_rate_limited", "We're moving fast. Try again in a few seconds.")
    static let parseFailure = tr("main.error.parse_failure", "Couldn't estimate. Tap Retry.")
    static let escalationDisabledNow = tr("main.error.escalation_disabled_now", "AI assistance is off right now.")
    static let escalationBudgetExceeded = tr("main.error.escalation_budget_exceeded", "AI is at its daily limit. Try again tomorrow.")
    static let escalationNoLongerNeeded = tr("main.error.escalation_no_longer_needed", "We've got enough — no closer look needed.")
    static let escalationInvalidParseReference = tr("main.error.escalation_invalid_parse_reference", "This estimate is out of date. Tap Estimate to refresh.")
    static let escalationNetworkFailure = tr("main.error.escalation_network_failure", "Couldn't reach the server. Tap again to retry.")
    static let escalationFailure = tr("main.error.escalation_failure", "Couldn't take a closer look. Tap Retry.")
    static let saveNetworkFailure = tr("main.error.save_network_failure", "We couldn't save your meal — connection issue. Your draft is safe. Tap Retry to send it.")
    static let recoveredPendingSave = tr("main.info.recovered_pending_save", "Restored your unsent meal. Tap Retry when you're ready.")
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
