# Content audit — `L10n.swift` + onboarding

Date: 2026-05-01
Branch: `chore/content-audit-and-voice-sample`
Plan reference: Tier 1 item #1 (Content refresh)

---

## What's in scope

`Food App/Food App/L10n.swift` has **155 strings** today, plus inline copy in 17 onboarding screens. This audit classifies every `L10n.swift` entry into one of three buckets:

- **Fine** — leave alone. Generic UI labels, format scaffolds, enum option names. ~80 strings.
- **Tighten** — copy is OK but dev-heavy or wordy. Quick edits. ~40 strings.
- **Rewrite** — feels engineer-y, exposes internals, or doesn't match the brand voice. Full rewrites. ~35 strings.

The bulk-edit phase rewrites only "tighten" + "rewrite" (~75 strings). "Fine" stays untouched.

---

## Voice direction (proposed)

Before any rewrites land, you need to approve the voice. I'm proposing:

> **Plain, direct, warm undertone — no exclamation points, no marketing language, no engineer jargon.**
>
> The user doesn't care about parse routes, idempotency keys, or save contracts. They care that their meal logged. Copy should respect their attention by being short and concrete. No "Smart AI-powered logging!" — just "Log your meal."

**Reference axis:**

| Tone | Example | Use? |
|---|---|---|
| Marketing-buzzy | *"Unlock your personalized AI-powered nutrition coach!"* | ❌ never |
| Engineer-jargon | *"Save key conflict: this retry key was used with different data."* | ❌ never (current state in many places) |
| Playful | *"Whoops, looks like you're offline! We'll catch up when you're back online 👋"* | ❌ avoid emoji + cute |
| **Plain warm** | *"You're offline. Your draft is safe — we'll save it when you reconnect."* | ✅ this voice |
| Clinical | *"Network unavailable. Draft cached locally."* | ❌ too cold |

---

## 15 voice samples for approval

This is the gate. Approve, edit, or reject these and I'll do the bulk rewrite.

| # | ID | Now | Proposed | Why |
|---|---|---|---|---|
| 1 | `onboardingSplashTitle` | "Log your food with\nless Effort" | "Log your food.\nWithout the effort." | Cleaner break; consistent capitalization; mirrors how people actually pause in the read. |
| 2 | `onboardingSplashStartButton` | "Get Started" | "Get started" | Sentence case throughout the app, not Title Case. Industry-standard for iOS in 2026. |
| 3 | `onboardingSplashExistingAccountButton` | "I already have an account" | "Sign in" | Two words for what was eight. The user's existing account is implied. |
| 4 | `onboardingAccountSocialProof` | "5,000+ people eating smarter" | "Trusted by 5,000+ people" | "Eating smarter" is a marketing phrase that doesn't actually mean anything. |
| 5 | `saveLogButton` | "Save Log" | "Save" | The user is on a logging screen. "Log" is redundant. |
| 6 | `parseNowButton` | "Parse Now" | "Estimate" | "Parse" is engineer language. The user wants an estimate of their meal. |
| 7 | `estimatedTotalsTitle` | "Estimated Totals" | "Today so far" or "Estimated for this meal" (depends on placement) | Drop the engineer word "totals." Actual phrase depends on where this surface is — flag for manual review. |
| 8 | `startTypingHint` | "Start typing and we'll estimate calories/macros here." | "Start typing — we'll estimate the calories and macros." | Em-dash for warmth instead of "and"; spell out "calories and macros" instead of slash. |
| 9 | `savedSuccessfullyPrefix` | "Saved successfully" | "Saved" | "Successfully" adds nothing. The fact that it appears means it worked. |
| 10 | `saveNetworkFailure` | "Network issue while saving. Draft was preserved. Use Retry Last Save to safely retry without duplicate logs." | "We couldn't save your meal — connection issue. Your draft is safe. Tap Retry to send it." | Removes "duplicate logs" engineer-fear-voice; speaks to the actual user concern. |
| 11 | `noPreviousRetry` | "No previous save attempt is available to retry." | "Nothing to retry." | Three words, same information. The longer version implies the user did something wrong. |
| 12 | `authSessionExpired` | "Session expired. Please sign in again." | "You've been signed out. Sign in to keep going." | "Session" is engineer language; "Please" reads like a help-desk script. |
| 13 | `daySummaryZeroTotals` | "Totals are currently zero for this day." | "Nothing logged yet today." | "Totals are currently zero" is a database read; "nothing logged" is what the human sees. |
| 14 | `offlineBanner` | "You are offline. Keep editing safely. Reconnect, then tap Retry Last Save (same idempotency key) to avoid duplicate logs." | "You're offline. Your draft is safe — we'll send it when you're back online." | The current copy mentions "idempotency key" to the user. That's the bug. |
| 15 | `recoveredPendingSave` | "Recovered pending save draft. Tap Retry Last Save when ready." | "Restored your unsent meal. Tap Retry when you're ready." | "Pending save draft" is engineer English. "Unsent meal" is human. |

---

## Classification of all 155 strings

This is for transparency — you don't need to read it line-by-line, but it's the working document for the bulk rewrite phase.

### Fine — leave alone (80)

Generic UI scaffolding, enum labels, format strings:

`networkOnline`, `networkOffline`, `onboardingTitle`, `onboardingGoalSection`, `onboardingGoalLabel`, `onboardingPreferencesSection`, `onboardingDietPreferenceLabel`, `onboardingAllergiesLabel`, `onboardingUnitsLabel`, `onboardingActivityLabel`, `onboardingStatusSection`, `onboardingGoalLose`, `onboardingGoalMaintain`, `onboardingGoalGain`, `onboardingUnitsMetric`, `onboardingUnitsImperial`, `onboardingActivityLow`, `onboardingActivityModerate`, `onboardingActivityHigh`, `onboardingSplashBrandName`, `onboardingSplashImageA11y`, `onboardingAccountFeatureLoggingTitle`, `onboardingAccountFeatureLoggingSubtitle`, `onboardingAccountFeatureProgressTitle`, `onboardingAccountFeatureProgressSubtitle`, `onboardingAccountFeatureSecureTitle`, `onboardingAccountFeatureSecureSubtitle`, `onboardingAccountGoogleLabel`, `onboardingAccountAppleLabel`, `foodLogTitle`, `foodInputPrompt`, `parseInProgress`, `saveInProgress`, `totalsCalories`, `totalsProtein`, `totalsCarbs`, `totalsFat`, `daySummaryTitle`, `daySummaryDateLabel`, `parseDetailsTitle`, `doneButton`, `clarificationQuestionsTitle`, `editableItemsTitle`, `itemNamePlaceholder`, `unitPlaceholder`, `saveActionsTitle`, `confidenceLabel`, `parseQueuedShortLabel`, `parseRetryShortLabel`, `parseBeforeEscalation`, `escalationNotRequired`, `parseBeforeSave`

…plus all numeric format strings (`saveSuccessWithTtlFormat`, `quantityFormat`, `nutritionLineFormat`, `remainingFormat`, `timeToLogFormat`, `idempotencyKeyFormat`, `confidenceFormat`, `parseRequestIdFormat`, `parseVersionFormat`, `routeFormat`, `environmentLabelFormat`, `baseURLLabelFormat`, `onboardingSavedTargetsFormat`).

### Tighten — wordy or dev-heavy (40)

These work but read as too long, too formal, or too hedged. Quick edits:

| String | Current | Direction |
|---|---|---|
| `networkLimited` | "Connected (limited network)" | "Limited connection" |
| `onboardingDietPreferencePlaceholder` | "Diet preference (e.g. vegetarian)" | "Diet preference (e.g., vegetarian)" — Oxford comma |
| `onboardingAllergiesPlaceholder` | "Allergies (comma-separated)" | "Allergies — separate with commas" |
| `onboardingCompleteButton` | "Complete Onboarding" | "Finish setup" |
| `onboardingSubmitA11yHint` | "Submits your preferences and finishes onboarding." | "Saves your preferences and finishes setup." |
| `onboardingSplashTrackingLabel` | "AI-POWERED TRACKING" | "AI-powered tracking" — drop the all-caps shout |
| `onboardingSplashTitle` | (sample 1 above) | (sample 1) |
| `onboardingSplashStartButton` | (sample 2) | (sample 2) |
| `onboardingSplashStartHint` | "Opens onboarding questions to configure your goals and preferences." | "Sets your goals and preferences." |
| `onboardingSplashExistingAccountButton` | (sample 3) | (sample 3) |
| `onboardingAccountSubtitle` | "Save your progress to unlock\nyour personalized plan." | "Save your progress.\nUnlock your plan." |
| `onboardingAccountSocialProof` | (sample 4) | (sample 4) |
| `onboardingAccountAppleUnavailable` | "Google sign-in is enabled right now. Apple sign-in is coming soon." | "Apple sign-in is coming soon. Use Google for now." |
| `onboardingAccountConnecting` | "Connecting account…" | "Connecting…" |
| `foodInputHint` | "Enter your meal in plain text." | "Type what you ate, plain English." |
| `parseNowButton` | (sample 6) | (sample 6) |
| `parseNowHint` | "Parses the current note to estimate nutrition." | "Estimates calories and macros for what you typed." |
| `openDetailsButton` | "Open Details Drawer" | "View details" |
| `openDetailsHint` | "Shows parsed items and editable details." | "Shows each food item — edit if needed." |
| `saveLogButton` | (sample 5) | (sample 5) |
| `saveLogHint` | "Saves this parsed log using an idempotency key." | "Saves this meal." |
| `retryLastSaveButton` | "Retry Last Save" | "Retry" |
| `retryLastSaveHint` | "Retries the previous save safely using the same idempotency key." | "Retries the last save without duplicating it." |
| `retryParseButton` | "Retry Parse" | "Retry estimate" |
| `retryParseHint` | "Retries nutrition parsing for the current text." | "Re-estimates calories and macros." |
| `retrySucceededPrefix` | "Retry succeeded safely" | "Retry succeeded" |
| `savedSuccessfullyPrefix` | (sample 9) | (sample 9) |
| `saveDisabledNeedsClarification` | "Save is disabled until clarification is resolved or escalated." | "Resolve the questions below before saving." |
| `startTypingHint` | (sample 8) | (sample 8) |
| `estimatedTotalsTitle` | (sample 7) | (sample 7) |
| `totalsEditedHint` | "Totals currently reflect your edits in the details drawer." | "Showing your edited values." |
| `clarificationNeededTitle` | "Clarification Needed" | "Need a bit more info" |
| `escalateParseButton` | "Escalate Parse" | "Get a closer look" |
| `escalateParseHint` | "Uses escalation AI route when clarification is needed." | "Uses our deeper AI when the quick estimate isn't sure." |
| `escalatingInProgress` | "Escalating parse..." | "Taking a closer look…" |
| `parseClarificationHint` | "Clarification needed. Open Details Drawer to review questions." | "We need a few details. Tap View details to answer." |
| `escalationCompleted` | "Escalation completed. Review updated items and save." | "Got it. Review the updated values and save." |
| `daySummaryZeroTotals` | (sample 13) | (sample 13) |
| `loadingDaySummary` | "Loading day summary..." | "Loading…" |
| `parseFirstHint` | "Parse something first to open details." | "Type a meal first." |
| `resetOnboardingButton` | "Reset Onboarding State" | "Reset onboarding" |

### Rewrite — engineer-y or off-voice (35)

Visible to the user but contains dev jargon (idempotency, parse reference, contract preview), or makes the user feel they did something wrong. Full rewrites:

| String | Current | Direction |
|---|---|---|
| `offlineBanner` | (sample 14) | (sample 14) |
| `noNetworkParse` | "No network connection. Your note is safe. Reconnect and tap Parse Now." | "You're offline. Your text is safe — reconnect to estimate." |
| `noNetworkSave` | "No network connection. Keep editing; when back online tap Retry Last Save." | "You're offline. Keep editing — we'll save when you reconnect." |
| `noNetworkRetry` | "Still offline. Reconnect, then tap Retry Last Save." | "Still offline. Reconnect, then tap Retry." |
| `noNetworkEscalate` | "No network connection. Reconnect and tap Escalate Parse." | "You're offline. Reconnect, then take a closer look." |
| `noNetworkSummary` | "Offline. Reconnect and tap Retry Summary to refresh." | "You're offline. Reconnect to refresh." |
| `escalationBudgetReason` | "Escalation is currently unavailable because daily AI budget is exhausted." | "AI is at its daily limit. Try again tomorrow." |
| `escalationConfigReason` | "Escalation is disabled on the backend configuration." | "AI assistance is off right now." |
| `parseNeedsClarificationBeforeSave` | "This parse still needs clarification. Resolve clarification first, then save." | "Answer the questions below, then save." |
| `parseBeforeSave` | "Parse the note first before saving." | "Type something to save." |
| `noPreviousRetry` | (sample 11) | (sample 11) |
| `authSessionExpired` | (sample 12) | (sample 12) |
| `daySummaryProfileNotFound` | "Complete onboarding first to view day summary." | "Finish setup to see your day." |
| `daySummaryInvalidInput` | "Selected date is invalid. Please pick another date." | "That date isn't valid. Pick another." |
| `daySummaryNetworkFailure` | "Network issue while loading day summary." | "Couldn't load — connection issue." |
| `daySummaryFailure` | "Failed to load day summary." | "Couldn't load your day. Tap Retry." |
| `saveIdempotencyConflict` | "Save key conflict: this retry key was used with different data. Tap Save Log to create a fresh key." | "Something changed since the last attempt. Tap Save to send the new version." |
| `saveInvalidParseReference` | "This parsed draft is stale. Parse again, then save." | "This estimate is out of date. Tap Estimate to refresh, then save." |
| `saveMissingIdempotency` | "Save request is missing idempotency key. Tap Save Log again." | "Tap Save again to send your meal." |
| `saveFailure` | "Save failed." | "Couldn't save. Tap Retry." |
| `parseNetworkFailure` | "Network issue while parsing. Your note is safe. Reconnect and tap Parse Now." | "Couldn't reach the server — your text is safe. Tap Estimate when you're back online." |
| `parseRateLimited` | "Parsing is busy. Wait a few seconds and try again." | "We're moving fast. Try again in a few seconds." |
| `parseFailure` | "Parse failed." | "Couldn't estimate. Tap Retry." |
| `escalationDisabledNow` | "Escalation is disabled on backend right now." | "AI assistance is off right now." |
| `escalationBudgetExceeded` | "Escalation blocked: daily AI budget is exhausted." | "AI is at its daily limit. Try again tomorrow." |
| `escalationNoLongerNeeded` | "Escalation is no longer needed. Parse already has enough confidence." | "We've got enough — no closer look needed." |
| `escalationInvalidParseReference` | "This parse reference is stale. Parse again, then escalate if still needed." | "This estimate is out of date. Tap Estimate to refresh." |
| `escalationNetworkFailure` | "Network issue during escalation. Please retry." | "Couldn't reach the server. Tap again to retry." |
| `escalationFailure` | "Escalation failed." | "Couldn't take a closer look. Tap Retry." |
| `saveNetworkFailure` | (sample 10) | (sample 10) |
| `recoveredPendingSave` | (sample 15) | (sample 15) |
| `parseConnectivityIssueLabel` | "Can't reach backend" | "No connection" |
| `parseStillProcessingLabel` | "Still parsing. Keep typing or retry in a moment." | "Still estimating — keep typing or wait a sec." |
| `parseQueuedLabel` | "Finishing current parse. New rows are queued." | "Finishing one estimate. New rows are next." |
| `lowConfidenceLabel` | "Low confidence" | "Less sure" — flag for review (this label is shown next to a row) |

### Internal/debug — likely admin-only, separate decision (5)

These appear visible in the L10n file but might only render in admin/debug surfaces. **I will leave these for the bulk rewrite to confirm context before touching:**

- `environmentLabelFormat`, `baseURLLabelFormat` — debug overlay only?
- `parseMetadataTitle`, `parseRequestIdFormat`, `parseVersionFormat`, `confidenceFormat`, `idempotencyKeyFormat` — these expose internal IDs; if they ever ship to non-admin builds, that's a leak. Audit needed.
- `routeFormat` + the route display labels (`cacheEstimateLabel`, `deterministicEstimateLabel`, `aliasEstimateLabel`, `aiEstimateLabel`, `unresolvedEstimateLabel`, `escalatedEstimateLabel`) — if these are user-visible (e.g., on a meal row), they need rewriting from "Cached estimate" → "From cache" / "From AI" / etc.

---

## What happens after you approve

1. **Approve voice direction** (the table at the top) — I'll lock voice rules in a comment at the top of `L10n.swift`.
2. **Approve or edit any of the 15 samples** — I'll apply your edits.
3. **Bulk rewrite** runs on the ~75 strings in Tighten + Rewrite buckets. Single PR.
4. **Onboarding inline copy** (17 OB*.swift screens) — I'll grep for hardcoded strings that should be in `L10n.swift` and either move them or rewrite in place.
5. **Manual review** of the 5 internal/debug-suspect strings — flag any that are user-visible.

Estimated time after approval: ~1 day for the bulk rewrite. Will ship as PR #6.

---

## What I'm NOT touching in this audit

- Backend error codes / API responses (separate concern; users don't see these).
- L10n entries that are purely debug surfaces (build env, base URL).
- Any string that reads as Apple-platform conventional UI ("Done", "Cancel", "OK"-style labels — these should match iOS expectations).
- Localization to non-English languages. The audit only covers English voice; other locales follow the existing onboarding cadence.
