# AUDIT FINDINGS — End-to-End Review

Base: `e71e52d`. Status: **candidates** from wave-1 fan-out — not yet adversarially verified or applied.
Legend: `[CATEGORY | confidence/severity]`. **HV** = human-verify (save-path/auth — do NOT auto-fix per CLAUDE.md).

---

## BACKEND — verifiable via `tsc --noEmit` + `vitest` (apply candidates)

### Dead code
- `services/geminiFlashClient.ts:325` `streamGeminiJson` (+`extractCompleteJsonObjects`) — [DEAD High] zero refs in src/scripts/tests. **~130 LOC**. Remove.
- `services/foodTextCandidates.ts:54` `tokenOverlapRatio` — [DEAD High] zero refs. ~14 LOC. Remove.
- `services/nutritionDatabaseService.ts:521` `lookupByName` — [DEAD Med] zero external refs. ~27 LOC. Remove.
- `services/aiCostService.ts:29` `getTodayEstimatedCostUsd` — [DEAD Med] zero refs. ~17 LOC. Remove.
- `routes/logSchemas.ts:136` `isUnresolvedPlaceholderItem` — [DEAD Low] used only in-file. Drop `export`.
- `routes/logs.ts:79` `resolvedStatus` — [DEAD Low] `x==='saved'?'saved':'saved'`. Inline `'saved'`.
- `services/recipeQualityScore.ts:485` `__testing` — [DEAD Low, confirm] not referenced by tests.
- **KEEP (verified test seams, NOT dead):** extractFoodTextInventoryForTests, get/resetGeminiCircuitBreakerStateForTests, resolveThinkingBudget, hydrationAmountToMl, ImageParse{Coverage,UsageEvent}/ImagePart, resetParseRateLimitStateForTests, resetRecipeImportRateLimitStateForTests, setRecipeHostResolverForTests, parseFoodTextCandidates, normalizeFoodUnit.

### Bugs
- `routes/logs.ts:209` — [BUG Med] `safeRecordSaveAttempt` not awaited/`void`ed in catch → dropped telemetry. Add `void`.
- `routes/parse.ts:800` — [BUG Med] SSE error path never logs / `next(err)`; failures invisible. Add structured log.
- `render.yaml:34` — [BUG Low] `AI_IMAGE_PRIMARY_MODEL` not read by config.ts (no effect). Rename/wire to `AI_IMAGE_INVENTORY_MODEL`.
- `routes/notifications.ts:90` — [BUG Low] DELETE `/devices/:token` validates `min(1)` vs registration `min(32)`.
- `routes/evalDashboard.ts:535` — [BUG Low] `||`→`??` (empty cases array shows maxCases).

### Security
- `routes/internalMetrics.ts:31` + evalDashboard/notifications/feedback/roadmap/internalImageParseTest + `app.ts:175` — [SEC High] internal-key compared with `!==` (timing attack) on 6+ admin endpoints; dashboard login also unthrottled. Use `timingSafeEqual`.
- `services/recipeImportService.ts:481` — [SEC High] Jina reader fetch uses `redirect:'follow'` with no SSRF re-validation (direct path uses `manual`+assert). Switch to manual+validate or document trust boundary.
- `services/parseRateLimiterService.ts` + `recipeImportRateLimiterService.ts` — [SEC Med] in-memory bucket map unbounded between prunes. Add size cap.
- `services/recipeImportService.ts:332` — [SEC Med] DNS resolve has no timeout (slow-DNS DoS). Wrap with timeout.
- `app.ts:139` — [SEC Med] CSP disabled globally. Re-enable, scope dashboard override.
- `routes/notifications.ts:39` — [SEC Med] timezone accepted without IANA validation (onboarding validates it). Add `isValidTimezone` refine.

### Simplify
- `requireInternalKey` duplicated ×6 routes — extract `utils/internalKey.ts` (fix timing bug once). ~20 LOC.
- `authContext(res)` duplicated ×3 (hydration/savedMeals/recipes) — extract `utils/authContext.ts`. ~14 LOC.
- parse + recipeImport rate limiters ~95% identical — factor `createFixedWindowRateLimiter`. ~50 LOC.

---

## iOS — needs green `xcodebuild` to verify (apply candidates)

### Dead code
- `MainLoggingPresentationViews.swift:1316` `MainLoggingHomeStatusStrip.saveSuccessMessage` + `shouldShowLoggingTipsButton`/`onLoggingTips` — [DEAD Med] passed, never rendered. ~12 LOC.
- `MainLoggingDockViews.swift:729` `TutorialVideoItem.lightResourceName` — [DEAD Med] always nil/never read. ~4.
- `MainLoggingDockViews.swift:250` `bottomDockButton.tintStrength` — [DEAD Low] always default 1.0. ~8.
- `SaveCoordinator.swift:358` `executeSave` throwing overload — [DEAD Med] no callers (all use `executeSaveResult`). ~10.
- `SaveCoordinator.swift:243` `handleAuthRestored` — [DEAD Med] no callers. ~5.
- `SaveCoordinator.swift:85` `telemetry` prop — [DEAD Low] stored, never read. ~4.
- `FoodNotificationRouting.swift:78` `FoodNotificationCategory.configure` — [DEAD Low] no callers. ~5.
- `FoodLoggingTipsView.swift:476` cooldown stubs (`skipCooldownKey`,`isWithinSkipCooldown`) — [DEAD Low] no-op since 2026-05-23. ~15.
- `AppFlowCoordinator.swift:125` `normalizedForActiveFlow` (identity) + `planPreview` route — [DEAD Low] maps self; EmptyView. ~18.
- `MainLoggingPresentationViews.swift:107` `MainLoggingManualAddDrawerContent`/`.manualAdd` — [DEAD Low — DEFER] scaffolding for a planned feature; do not delete.

### Bugs (non-save-path, candidate fixes)
- `MainLoggingRowMutationFlow.swift:148` — [BUG Med/High] `_ = removePendingSaveQueueItems(forRowID:)` discards returned keys → not unioned into `locallyDeletedPendingSaveKeys` → ghost rows after delete. (localized; verify)
- `LoggingResultDrawerBody.swift:256` + `MindfulPauseSheet.swift:92` — [BUG Med perf] `DateFormatter` rebuilt every call/render. Make `static let`.
- `AuthService.swift:930` mirroring `Task` not stored/cancelled — [BUG Med] leaks for non-singleton instances. Store + cancel in deinit.
- `AuthService.swift:224` `runWithStartupTimeout` detached task strong-captures self — [BUG Med] use `[weak self]`.
- `ImageStorageService.swift:97,151` — [BUG Low] `message!` force-unwrap; use `?? "Unknown storage error"`.

### Bugs — SAVE-PATH / AUTH, **HV (document only, do NOT auto-fix)**
- `MainLoggingSaveFlow.swift:598` deferred-image bytes not disk-persisted on save FAILURE → `image_ref=NULL` risk (matches prior incident).
- `SaveCoordinator.swift:150` `upsertPendingItem` matches `rowID OR idempotencyKey` → can overwrite promoted item with edit data.
- `MainLoggingSaveFlow.swift:219` `autoSavedParseIDs.insert` before await; never cleared on failure → blocks future auto-save retry.
- `MainLoggingParseFlow.swift:281` `clearPendingSaveContext()` on parse-success can drop in-flight save context (retry tap swallowed; queue durable).
- `SaveCoordinator.swift:339` reconcile compares `loggedAt` by exact string → format skew leaves sync pill stuck.
- `MainLoggingDrawerFlow.swift:38/253` double-tap `presentSaveMealSheet` race (asyncAfter) → possible duplicate sheet/save.
- `AuthService.swift:837` single-flight joiner reuses first caller's metadata session (latent, multi-provider).

### Simplify
- `roundOneDecimal` duplicated ×4: CameraResultDrawerView:652, HomeLoggingSupportViews:539, FoodLogSaveRequestBuilder:87 vs canonical HomeLoggingDisplayText:174. Consolidate. ~9.
- `SaveParsedFoodItem(...)` init repeated ×3 (MainLoggingSaveFlow:352, DateChange draft, Patch:64) — extract `init(from: ParsedFoodItem)`. ~45.
- totals-reduction duplicated ×3 — extract `computedTotals(from:)`. ~25.
- `presentSaveMealSheet` overloads share 12 lines — extract scheduler helper. ~10.
- `refreshNutritionState*` duplicate same-day branch — MainLoggingRowMutationFlow:66. ~7.
- `AuthSessionDisplayName.swift:117/162` JWT base64url decode duplicated ×2. ~15.
- `NotificationScheduler.swift:179` unused `challenge`/`hasLoggedToday` params. ~6.
- `SavedMealsViews.swift:740` hardcoded hex colors → `AppColor` tokens (+dark-mode fix). ~8.
- `AppFlowCoordinator.swift:58` `debugRoutes == activeFlow` (redundant). ~2.
- Minor force-unwraps: `MainLoggingSaveFlow:489 sourceId!`, `AppConfiguration:135 URL(string:)!`.
