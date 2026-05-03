import Foundation

// Save / autosave / patch flow extracted from MainLoggingShellView.
// Move-only refactor — function bodies and signatures unchanged.
// See docs/CLAUDE_PHASE_7A_REMAINING_HANDOFF.md Part 1.

extension MainLoggingShellView {
    func startSaveFlow() {
        guard appStore.isNetworkReachable else {
            saveError = L10n.noNetworkSave
            return
        }

        guard let request = buildSaveDraftRequest() else {
            saveError = L10n.parseBeforeSave
            return
        }

        let fingerprint = saveRequestFingerprint(request)
        let requestToSave = request
        let idempotencyKey: UUID
        let isRetry: Bool

        if let pendingSaveIdempotencyKey, pendingSaveFingerprint == fingerprint {
            idempotencyKey = pendingSaveIdempotencyKey
            isRetry = true
        } else {
            idempotencyKey = UUID()
            pendingSaveFingerprint = fingerprint
            pendingSaveRequest = requestToSave
            pendingSaveIdempotencyKey = idempotencyKey
            persistPendingSaveContext(rowID: activeEditingRowID)
            isRetry = false
        }

        Task {
            await submitSave(
                request: requestToSave,
                idempotencyKey: idempotencyKey,
                isRetry: isRetry,
                intent: .manual
            )
        }
    }

    // MARK: - Quantity Fast-Path Persistence

    /// Called from the composer after the client-side quantity fast path
    /// rescales a row's items. Routes persistence based on whether the row
    /// was loaded from the server (serverLogId present → PATCH) or is a
    /// newly-composed row the user is still typing (serverLogId nil → let
    /// the existing auto-save/POST flow pick up the scaled items via
    /// buildRowSaveRequest).

    func cancelAutoSaveTask() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
    }

    func scheduleAutoSaveTask(
        after delayNs: UInt64,
        forceReschedule: Bool = false
    ) {
        if forceReschedule {
            cancelAutoSaveTask()
        } else if autoSaveTask != nil {
            return
        }

        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                autoSaveTask = nil
            }
            await autoSaveIfNeeded()
        }
    }

    func retryLastSave() {
        guard appStore.isNetworkReachable else {
            saveError = L10n.noNetworkRetry
            return
        }
        guard let pendingSaveRequest, let pendingSaveIdempotencyKey else {
            saveError = L10n.noPreviousRetry
            return
        }

        Task {
            await submitSave(
                request: pendingSaveRequest,
                idempotencyKey: pendingSaveIdempotencyKey,
                isRetry: true,
                intent: .retry
            )
        }
    }

    func scheduleAutoSave() {
        // Persist each pending row's context immediately so drafts survive
        // an app close during the auto-save delay window.
        let saveableEntries = activeParseSnapshots.filter(isAutoSaveEligibleEntry(_:))

        for entry in saveableEntries {
            guard let request = buildRowSaveRequest(for: entry) else { continue }
            let key = resolveIdempotencyKey(forRowID: entry.rowID)
            upsertPendingSaveQueueItem(
                request: request,
                fingerprint: saveRequestFingerprint(request),
                idempotencyKey: key,
                rowID: entry.rowID
            )
            saveAttemptTelemetry.emit(
                parseRequestId: entry.parseRequestId,
                rowID: entry.rowID,
                outcome: .attempted,
                errorCode: nil,
                latencyMs: nil,
                source: .auto
            )
        }
        scheduleAutoSaveTask(after: autoSaveDelayNs)
    }

    func rescheduleAutoSaveAfterActiveSave() {
        scheduleAutoSaveTask(after: 500_000_000, forceReschedule: true)
    }

    func autoSaveIfNeeded() async {
        guard appStore.isNetworkReachable else { return }
        guard !isSaving else {
            if hasSaveableRowsPending {
                rescheduleAutoSaveAfterActiveSave()
            }
            return
        }

        if await flushQueuedPendingSavesIfNeeded() {
            return
        }

        // Save each completed row independently using the per-row rawText.
        // This fixes the 422 mismatch: each save request uses the exact rawText
        // that was stored in parse_requests on the backend.
        let snapshots = activeParseSnapshots
        let rowsToSave = snapshots.filter(isAutoSaveEligibleEntry(_:))
        let saveableRowIDs = Set(rowsToSave.map(\.rowID))
        for entry in snapshots {
            guard let row = inputRows.first(where: { $0.id == entry.rowID }),
                  row.calories != nil,
                  !saveableRowIDs.contains(entry.rowID) else {
                continue
            }
            let skippedOutcome: SaveAttemptOutcome = autoSavedParseIDs.contains(entry.parseRequestId)
                ? .skippedDuplicate
                : .skippedNoEligibleState
            saveAttemptTelemetry.emit(
                parseRequestId: entry.parseRequestId,
                rowID: entry.rowID,
                outcome: skippedOutcome,
                errorCode: nil,
                latencyMs: nil,
                source: .auto
            )
        }

        for entry in rowsToSave {
            guard let request = buildRowSaveRequest(for: entry) else { continue }

            // If the row was loaded from the server (has a serverLogId),
            // this is an EDIT — not a new entry. Route through PATCH so the
            // backend updates the existing food_log instead of POSTing a
            // duplicate. Covers the case where the user opens a saved row,
            // changes more than just the quantity (triggering a full
            // re-parse), and the standard auto-save fires.
            let row = inputRows.first(where: { $0.id == entry.rowID })
            if let serverLogId = row?.serverLogId ?? pendingQueueItem(forRowID: entry.rowID)?.serverLogId {
                autoSavedParseIDs.insert(entry.parseRequestId)
                await submitRowPatch(
                    serverLogId: serverLogId,
                    saveRequest: request,
                    rowID: entry.rowID
                )
                continue
            }

            // Reuse the queued key for this row so retries / repeated auto-save
            // passes cannot create duplicate rows with new idempotency keys.
            let idempotencyKey = resolveIdempotencyKey(forRowID: entry.rowID)
            pendingSaveFingerprint = saveRequestFingerprint(request)
            pendingSaveRequest = request
            pendingSaveIdempotencyKey = idempotencyKey
            persistPendingSaveContext(rowID: entry.rowID)

            // Mark before the call so a retry loop can't stack up (idempotency key
            // on the backend is the real guard against duplicate writes).
            autoSavedParseIDs.insert(entry.parseRequestId)

            await submitSave(
                request: request,
                idempotencyKey: idempotencyKey,
                isRetry: false,
                intent: .auto
            )
        }

        // Fall back to the single-request image path when no row snapshots exist.
        if snapshots.isEmpty {
            guard parseResult != nil else { return }
            guard hasVisibleUnsavedCalorieRows else { return }
            guard let request = buildSaveDraftRequest() else { return }
            let contentFingerprint = autoSaveContentFingerprint(request)
            if contentFingerprint == lastAutoSavedContentFingerprint { return }
            let pendingImageRowID = inputRows.first(where: { !$0.isSaved && $0.imagePreviewData != nil })?.id
            let idempotencyKey = resolveIdempotencyKey(forRowID: pendingImageRowID)
            pendingSaveFingerprint = saveRequestFingerprint(request)
            pendingSaveRequest = request
            pendingSaveIdempotencyKey = idempotencyKey
            persistPendingSaveContext(
                rowID: pendingImageRowID,
                imageUploadData: pendingImageData,
                imagePreviewData: pendingImagePreviewData,
                imageMimeType: pendingImageMimeType
            )
            await submitSave(request: request, idempotencyKey: idempotencyKey, isRetry: false, intent: .auto)
        }
    }

    @discardableResult

    func flushQueuedPendingSavesIfNeeded() async -> Bool {
        let candidates = saveCoordinator.consumeSubmissionCandidates()
        syncPendingQueueFromCoordinator(refreshRetryState: true)

        guard !candidates.isEmpty else { return false }

        var refreshDates: Set<String> = []

        for candidate in candidates {
            let result = await submitSave(
                request: candidate.item.request,
                idempotencyKey: candidate.idempotencyKey,
                isRetry: (candidate.item.attemptCount ?? 0) > 0,
                intent: .auto,
                deferRefresh: true
            )
            if let savedDay = result.savedDay {
                refreshDates.insert(savedDay)
            }
        }

        for savedDay in refreshDates.sorted() {
            await refreshDayAfterMutation(savedDay)
        }

        return true
    }

    /// Forces a pending auto-save to fire RIGHT NOW instead of waiting for the
    /// 10-second debounce. Called before a date change so typed entries aren't
    /// lost when the user swipes away mid-debounce. Safe to call even if nothing
    /// is eligible — it just returns quickly.

    func flushPendingAutoSaveIfEligible() async {
        // Bail early if nothing to save
        let snapshots = activeParseSnapshots
        let hasCompletedRow = snapshots.contains(where: { isAutoSaveEligibleEntry($0) })
        let hasLegacyParse = snapshots.isEmpty &&
            parseResult != nil &&
            hasVisibleUnsavedCalorieRows

        guard hasCompletedRow || hasLegacyParse || hasQueuedPendingSaves else { return }

        // Cancel the debounced auto-save task and run immediately
        cancelAutoSaveTask()
        await autoSaveIfNeeded()
    }

    func isAutoSaveEligibleEntry(_ entry: ParseSnapshot) -> Bool {
        SaveEligibility.isRowEligible(
            row: inputRows.first(where: { $0.id == entry.rowID }),
            snapshot: entry,
            autoSavedParseIDs: autoSavedParseIDs
        )
    }

    func buildRowSaveRequest(for entry: ParseSnapshot) -> SaveLogRequest? {
        let response = entry.response
        let currentRow = inputRows.first(where: { $0.id == entry.rowID })
        let sourceItems: [ParsedFoodItem]
        if let row = currentRow, !row.parsedItems.isEmpty {
            sourceItems = row.parsedItems
        } else if let row = currentRow, let singleItem = row.parsedItem {
            sourceItems = [singleItem]
        } else if !entry.rowItems.isEmpty {
            sourceItems = entry.rowItems
        } else {
            sourceItems = response.items
        }
        let effectiveLoggedAt = entry.loggedAt
        let items: [SaveParsedFoodItem]
        if sourceItems.isEmpty {
            let hasDisplayedCalories = currentRow?.calories != nil || response.totals.calories > 0
            guard hasDisplayedCalories else { return nil }
            let fallbackTotals = NutritionTotals(
                calories: Double(currentRow?.calories ?? Int(response.totals.calories.rounded())),
                protein: response.totals.protein,
                carbs: response.totals.carbs,
                fat: response.totals.fat
            )
            items = [
                fallbackSaveItem(
                    rawText: entry.rawText,
                    totals: fallbackTotals,
                    confidence: response.confidence,
                    nutritionSourceId: currentRow?.parsedItem?.nutritionSourceId ?? response.items.first?.nutritionSourceId
                )
            ]
        } else {
            items = sourceItems.map { item in
                SaveParsedFoodItem(
                    name: item.name,
                    quantity: item.amount ?? item.quantity,
                    amount: item.amount ?? item.quantity,
                    unit: item.unitNormalized ?? item.unit,
                    unitNormalized: item.unitNormalized ?? item.unit,
                    grams: item.grams,
                    gramsPerUnit: item.gramsPerUnit,
                    calories: item.calories,
                    protein: item.protein,
                    carbs: item.carbs,
                    fat: item.fat,
                    nutritionSourceId: item.nutritionSourceId,
                    originalNutritionSourceId: item.originalNutritionSourceId,
                    sourceFamily: item.sourceFamily,
                    matchConfidence: item.matchConfidence,
                    // Product rule: persist visible calorie rows without blocking on clarification.
                    needsClarification: false,
                    manualOverride: (item.manualOverride == true)
                        ? SaveManualOverride(enabled: true, reason: nil, editedFields: [])
                        : nil
                )
            }
        }
        guard !items.isEmpty else { return nil }
        let rowTotals = NutritionTotals(
            calories: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.calories }),
            protein: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.protein }),
            carbs: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.carbs }),
            fat: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.fat })
        )

        return SaveLogRequest(
            parseRequestId: entry.parseRequestId,
            parseVersion: entry.parseVersion,
            parsedLog: SaveLogBody(
                rawText: entry.rawText,
                loggedAt: effectiveLoggedAt,
                inputKind: normalizedInputKind(response.inputKind, fallback: "text"),
                imageRef: nil,
                confidence: response.confidence,
                totals: rowTotals,
                sourcesUsed: response.sourcesUsed,
                assumptions: response.assumptions,
                items: items
            )
        )
    }

    func buildDateChangeDraftSaveRequest(
        draft: DateChangeDraftRow,
        response: ParseLogResponse
    ) -> SaveLogRequest? {
        let sourceItems = response.items
        let items: [SaveParsedFoodItem]

        if sourceItems.isEmpty {
            guard response.totals.calories > 0 || isTrustedZeroNutritionResponse(response) else {
                return nil
            }
            items = [
                fallbackSaveItem(
                    rawText: draft.text,
                    totals: response.totals,
                    confidence: response.confidence,
                    nutritionSourceId: response.items.first?.nutritionSourceId
                )
            ]
        } else {
            items = sourceItems.map { item in
                SaveParsedFoodItem(
                    name: item.name,
                    quantity: item.amount ?? item.quantity,
                    amount: item.amount ?? item.quantity,
                    unit: item.unitNormalized ?? item.unit,
                    unitNormalized: item.unitNormalized ?? item.unit,
                    grams: item.grams,
                    gramsPerUnit: item.gramsPerUnit,
                    calories: item.calories,
                    protein: item.protein,
                    carbs: item.carbs,
                    fat: item.fat,
                    nutritionSourceId: item.nutritionSourceId,
                    originalNutritionSourceId: item.originalNutritionSourceId,
                    sourceFamily: item.sourceFamily,
                    matchConfidence: item.matchConfidence,
                    needsClarification: false,
                    manualOverride: (item.manualOverride == true)
                        ? SaveManualOverride(enabled: true, reason: nil, editedFields: [])
                        : nil
                )
            }
        }

        guard !items.isEmpty else { return nil }

        let rowTotals = NutritionTotals(
            calories: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.calories }),
            protein: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.protein }),
            carbs: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.carbs }),
            fat: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.fat })
        )

        return SaveLogRequest(
            parseRequestId: response.parseRequestId,
            parseVersion: response.parseVersion,
            parsedLog: SaveLogBody(
                rawText: canonicalParseRawText(response: response, fallbackRawText: draft.text),
                loggedAt: draft.loggedAt,
                inputKind: draft.inputKind,
                imageRef: nil,
                confidence: response.confidence,
                totals: rowTotals,
                sourcesUsed: response.sourcesUsed,
                assumptions: response.assumptions,
                items: items
            )
        )
    }

    func fallbackSaveItem(
        rawText: String,
        totals: NutritionTotals,
        confidence: Double,
        nutritionSourceId: String?
    ) -> SaveParsedFoodItem {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemName = trimmedText.isEmpty ? "Meal estimate" : trimmedText
        let sourceId = nutritionSourceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSourceId = (sourceId?.isEmpty == false) ? sourceId! : kUnresolvedPlaceholderSourceId

        let calories = HomeLoggingDisplayText.roundOneDecimal(max(0, totals.calories))
        let protein = HomeLoggingDisplayText.roundOneDecimal(max(0, totals.protein))
        let carbs = HomeLoggingDisplayText.roundOneDecimal(max(0, totals.carbs))
        let fat = HomeLoggingDisplayText.roundOneDecimal(max(0, totals.fat))
        let clampedConfidence = min(max(confidence, 0), 1)

        return SaveParsedFoodItem(
            name: itemName,
            quantity: 1,
            amount: 1,
            unit: "serving",
            unitNormalized: "serving",
            // This is a synthetic fallback item for a displayed calorie
            // estimate, not a real serving-weight measurement. Persist a
            // neutral placeholder instead of corrupting grams with calorie
            // values (e.g. 650 cal -> 650 g).
            grams: 1,
            gramsPerUnit: 1,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            nutritionSourceId: resolvedSourceId,
            originalNutritionSourceId: resolvedSourceId,
            sourceFamily: nil,
            matchConfidence: clampedConfidence,
            needsClarification: false,
            manualOverride: nil
        )
    }

    func autoSaveContentFingerprint(_ request: SaveLogRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        struct Payload: Codable {
            let parseRequestId: String
            let rawText: String
            let inputKind: String?
            let imageRef: String?
            let totals: NutritionTotals
            let items: [SaveParsedFoodItem]
        }
        let payload = Payload(
            parseRequestId: request.parseRequestId,
            rawText: request.parsedLog.rawText,
            inputKind: request.parsedLog.inputKind,
            imageRef: request.parsedLog.imageRef,
            totals: request.parsedLog.totals,
            items: request.parsedLog.items
        )
        guard let data = try? encoder.encode(payload) else {
            return UUID().uuidString
        }
        return data.base64EncodedString()
    }

    func normalizedInputKind(_ rawValue: String?, fallback: String = "text") -> String {
        HomeLoggingRowFactory.normalizedInputKind(rawValue, fallback: fallback)
    }

    func requestWithImageRef(_ request: SaveLogRequest, imageRef: String?) -> SaveLogRequest {
        SaveLogRequest(
            parseRequestId: request.parseRequestId,
            parseVersion: request.parseVersion,
            parsedLog: SaveLogBody(
                rawText: request.parsedLog.rawText,
                loggedAt: request.parsedLog.loggedAt,
                inputKind: normalizedInputKind(request.parsedLog.inputKind, fallback: latestParseInputKind),
                imageRef: imageRef,
                confidence: request.parsedLog.confidence,
                totals: request.parsedLog.totals,
                sourcesUsed: request.parsedLog.sourcesUsed,
                assumptions: request.parsedLog.assumptions,
                items: request.parsedLog.items
            )
        )
    }

    func prepareSaveRequestForNetwork(_ request: SaveLogRequest, idempotencyKey: UUID) async throws -> SaveLogRequest {
        var prepared = request
        let kind = normalizedInputKind(prepared.parsedLog.inputKind, fallback: latestParseInputKind)
        let queuedItem = pendingQueueItem(for: idempotencyKey)

        if kind == "image" {
            if let existingRef = pendingImageStorageRef ?? prepared.parsedLog.imageRef,
               !existingRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prepared = requestWithImageRef(prepared, imageRef: existingRef)
            } else if let imageData = pendingImageData ?? queuedItem?.imageUploadData ?? inputRows.compactMap(\.imagePreviewData).first {
                // Image upload is decoupled from save: nutrition data must
                // never be lost just because Supabase Storage is unhappy.
                // We attempt the upload inline so the food_log can land
                // with image_ref populated on the happy path; if anything
                // throws (missing bucket, expired Supabase JWT, network
                // blip, RLS misconfig…), we stash the bytes and retry the
                // upload + PATCH /v1/logs/:id/image-ref once the save
                // succeeds. The user gets their meal logged either way.
                do {
                    let imageRef = try await appStore.imageStorageService.uploadJPEG(
                        imageData,
                        userIdentifierHint: appStore.authSessionStore.session?.userID
                    )
                    pendingImageStorageRef = imageRef
                    prepared = requestWithImageRef(prepared, imageRef: imageRef)
                    for index in inputRows.indices where inputRows[index].imagePreviewData != nil {
                        inputRows[index].imageRef = imageRef
                    }
                } catch {
                    let queueKey = idempotencyKey.uuidString.lowercased()
                    deferredImageUploads[queueKey] = imageData
                    NSLog("[MainLogging] Inline image upload failed; deferring to post-save retry: \(error)")
                    // Leave prepared with imageRef = nil so the save proceeds.
                }
            }
        }

        if pendingSaveIdempotencyKey == idempotencyKey {
            pendingSaveRequest = prepared
            pendingSaveFingerprint = saveRequestFingerprint(prepared)
            persistPendingSaveContext()
        }
        if containsPendingQueueItem(for: idempotencyKey) {
            upsertPendingSaveQueueItem(
                request: prepared,
                fingerprint: saveRequestFingerprint(prepared),
                idempotencyKey: idempotencyKey,
                rowID: queuedItem?.rowID,
                imageUploadData: queuedItem?.imageUploadData,
                imagePreviewData: queuedItem?.imagePreviewData,
                imageMimeType: queuedItem?.imageMimeType,
                serverLogId: queuedItem?.serverLogId
            )
        }

        return prepared
    }

    @discardableResult

    func submitSave(
        request: SaveLogRequest,
        idempotencyKey: UUID,
        isRetry: Bool,
        intent: SaveIntent,
        deferRefresh: Bool = false
    ) async -> SaveSubmissionResult {
        let queueKey = idempotencyKey.uuidString.lowercased()
        let submittedRowID = pendingQueueItem(for: idempotencyKey)?.rowID
        let telemetryRowID = submittedRowID ?? UUID()
        let startedAt = Date()
        saveAttemptTelemetry.emit(
            parseRequestId: request.parseRequestId,
            rowID: telemetryRowID,
            outcome: .attempted,
            errorCode: nil,
            latencyMs: nil,
            source: telemetrySource(for: intent)
        )
        isSaving = true
        saveError = nil
        markPendingSaveAttemptStarted(idempotencyKey: idempotencyKey)
        defer { isSaving = false }

        let executionResult = await saveCoordinator.executeSaveResult(
            request: request,
            idempotencyKey: idempotencyKey,
            prepareForNetwork: { request, key in
                try await prepareSaveRequestForNetwork(request, idempotencyKey: key)
            }
        )

        switch executionResult {
        case .success(let success):
            let savedDay = await handleSubmitSaveSuccess(
                success,
                queueKey: queueKey,
                submittedRowID: submittedRowID,
                telemetryRowID: telemetryRowID,
                idempotencyKey: idempotencyKey,
                intent: intent,
                isRetry: isRetry,
                startedAt: startedAt,
                deferRefresh: deferRefresh
            )
            return SaveSubmissionResult(didSucceed: true, savedDay: savedDay)
        case .failure(let failure):
            await handleSubmitSaveFailure(
                failure,
                telemetryRowID: telemetryRowID,
                idempotencyKey: idempotencyKey,
                intent: intent,
                isRetry: isRetry,
                startedAt: startedAt
            )
            return SaveSubmissionResult(didSucceed: false, savedDay: nil)
        }
    }

    func handleSubmitSaveSuccess(
        _ success: SaveExecutionSuccess,
        queueKey: String,
        submittedRowID: UUID?,
        telemetryRowID: UUID,
        idempotencyKey: UUID,
        intent: SaveIntent,
        isRetry: Bool,
        startedAt: Date,
        deferRefresh: Bool
    ) async -> String {
        let effectiveRequest = success.preparedRequest
        let response = success.response
        let savedDay = HomeLoggingDateUtils.summaryDayString(
            fromLoggedAt: effectiveRequest.parsedLog.loggedAt,
            fallback: summaryDateString
        )
        if shouldDiscardCompletedSave(queueKey: queueKey, rowID: submittedRowID) {
            await deleteLateArrivingSave(logId: response.logId, savedDay: savedDay, queueKey: queueKey, rowID: submittedRowID)
            return savedDay
        }

        let prefix = isRetry ? L10n.retrySucceededPrefix : L10n.savedSuccessfullyPrefix
        let timeToLogMs = flowStartedAt.map { elapsedMs(since: $0) }
        if intent == .auto {
            saveSuccessMessage = nil
            lastAutoSavedContentFingerprint = autoSaveContentFingerprint(effectiveRequest)
        } else if intent == .dateChangeBackground {
            saveSuccessMessage = nil
        } else {
            if let timeToLogMs {
                saveSuccessMessage = L10n.saveSuccessWithTTL(prefix: prefix, logID: response.logId, day: savedDay, ttlSeconds: timeToLogMs / 1000)
                lastTimeToLogMs = timeToLogMs
            } else {
                saveSuccessMessage = L10n.saveSuccessWithoutTTL(prefix: prefix, logID: response.logId, day: savedDay)
            }
        }

        let syncedToHealth = await syncSavedLogToAppleHealthIfEnabled(effectiveRequest, response: response)
        if syncedToHealth {
            if intent == .auto {
                saveSuccessMessage = nil
            } else if let current = saveSuccessMessage, !current.isEmpty {
                saveSuccessMessage = "\(current) • Synced to Apple Health"
            }
        }

        saveError = nil
        appStore.setError(nil)
        emitSaveTelemetrySuccess(
            request: effectiveRequest,
            durationMs: elapsedMs(since: startedAt),
            isRetry: isRetry,
            logId: response.logId,
            timeToLogMs: timeToLogMs
        )
        saveAttemptTelemetry.emit(
            parseRequestId: effectiveRequest.parseRequestId,
            rowID: telemetryRowID,
            outcome: .succeeded,
            errorCode: nil,
            latencyMs: Int(elapsedMs(since: startedAt)),
            source: telemetrySource(for: intent)
        )
        markPendingSaveSucceeded(
            idempotencyKey: idempotencyKey,
            logId: response.logId,
            preparedRequest: effectiveRequest
        )
        if let submittedRowID {
            removePreservedDateDraft(rowID: submittedRowID, for: savedDay)
        }
        // If the inline image upload failed during
        // prepareSaveRequestForNetwork (Supabase storage unhappy, network
        // blip, expired storage JWT, missing bucket), the bytes were
        // stashed in deferredImageUploads. Now that the food_log row is
        // durable, retry the upload + PATCH the image_ref in a detached
        // task so the user's meal is saved and the photo attaches when
        // storage cooperates.
        scheduleDeferredImageUploadRetry(
            idempotencyKey: idempotencyKey,
            logId: response.logId,
            inputKind: effectiveRequest.parsedLog.inputKind ?? latestParseInputKind
        )
        if intent != .dateChangeBackground {
            clearPendingSaveContext()
        }
        if intent == .manual || intent == .retry {
            flowStartedAt = nil
            draftLoggedAt = nil
        }
        if intent != .dateChangeBackground,
           let parsedDate = HomeLoggingDateUtils.summaryRequestFormatter.date(from: savedDay) {
            selectedSummaryDate = parsedDate
        }
        if intent != .dateChangeBackground || savedDay == summaryDateString {
            promoteSavedRow(
                for: effectiveRequest,
                idempotencyKey: idempotencyKey,
                logId: response.logId
            )
        }
        // Cancel prefetch to prevent it from re-populating cache with stale data
        prefetchTask?.cancel()
        if intent == .dateChangeBackground, savedDay != summaryDateString {
            invalidateDayCache(for: savedDay)
            NotificationCenter.default.post(
                name: .nutritionProgressDidChange,
                object: nil,
                userInfo: ["savedDay": savedDay]
            )
        } else if deferRefresh {
            invalidateDayCache(for: savedDay)
        } else {
            await refreshDayAfterMutation(savedDay)
        }
        return savedDay
    }

    func handleSubmitSaveFailure(
        _ failure: SaveExecutionFailure,
        telemetryRowID: UUID,
        idempotencyKey: UUID,
        intent: SaveIntent,
        isRetry: Bool,
        startedAt: Date
    ) async {
        let effectiveRequest = failure.effectiveRequest
        let error = failure.error
        saveSuccessMessage = nil
        handleAuthFailureIfNeeded(error)
        let message: String
        if error is ImageStorageServiceError {
            message = (error as? LocalizedError)?.errorDescription ?? "Image upload failed."
        } else {
            message = userFriendlySaveError(error)
        }
        if intent == .dateChangeBackground {
            _ = saveCoordinator.handleFailure(
                idempotencyKey: idempotencyKey,
                message: message,
                error: error
            )
            syncPendingQueueFromCoordinator(refreshRetryState: true)
            emitSaveTelemetryFailure(
                request: effectiveRequest,
                error: error,
                durationMs: elapsedMs(since: startedAt),
                isRetry: isRetry
            )
            saveAttemptTelemetry.emit(
                parseRequestId: effectiveRequest.parseRequestId,
                rowID: telemetryRowID,
                outcome: .failed,
                errorCode: saveAttemptErrorCode(error),
                latencyMs: Int(elapsedMs(since: startedAt)),
                source: telemetrySource(for: intent)
            )
            return
        }
        saveError = message
        appStore.setError(message)
        await handlePendingSaveFailure(
            idempotencyKey: idempotencyKey,
            request: effectiveRequest,
            error: error,
            message: message
        )
        emitSaveTelemetryFailure(
            request: effectiveRequest,
            error: error,
            durationMs: elapsedMs(since: startedAt),
            isRetry: isRetry
        )
        saveAttemptTelemetry.emit(
            parseRequestId: effectiveRequest.parseRequestId,
            rowID: telemetryRowID,
            outcome: .failed,
            errorCode: saveAttemptErrorCode(error),
            latencyMs: Int(elapsedMs(since: startedAt)),
            source: telemetrySource(for: intent)
        )
    }

    func shouldDiscardCompletedSave(queueKey: String, rowID: UUID?) -> Bool {
        locallyDeletedPendingSaveKeys.contains(queueKey) ||
            rowID.map { locallyDeletedPendingRowIDs.contains($0) } == true
    }

    func deleteLateArrivingSave(logId: String, savedDay: String, queueKey: String, rowID: UUID?) async {
        removePendingSave(idempotencyKey: queueKey)
        locallyDeletedPendingSaveKeys.remove(queueKey)
        if let rowID {
            locallyDeletedPendingRowIDs.remove(rowID)
        }

        do {
            try await saveCoordinator.deleteLog(id: logId)
            await refreshDayAfterMutation(savedDay)
        } catch {
            handleAuthFailureIfNeeded(error)
            saveError = userFriendlySaveError(error)
        }
    }

    /// Retries an image upload that failed during the inline path inside
    /// `prepareSaveRequestForNetwork`. By the time this runs, the food_log
    /// row is already saved without an image_ref — we just need to attach
    /// the photo when storage cooperates.
    ///
    /// Persistence model:
    ///
    ///   1. The bytes are written to the on-disk
    ///      `DeferredImageUploadStore` keyed by `logId` BEFORE the retry
    ///      task fires, so a force-quit between save success and the
    ///      detached upload doesn't lose the photo.
    ///   2. The detached task tries the upload + `PATCH /image-ref`. On
    ///      success it removes the disk entry. On failure the entry stays;
    ///      `AppStore.drainDeferredImageUploads()` picks it up at the next
    ///      launch (or whenever the user re-auths).
    ///   3. If the disk store is unavailable (init failed), behavior
    ///      degrades to in-memory-only — same as before this commit.
    ///
    /// The meal is already logged; the photo is a best-effort attachment.

    func promoteSavedRow(for request: SaveLogRequest, idempotencyKey: UUID, logId: String) {
        let queuedItem = pendingQueueItem(for: idempotencyKey)
        let savedLoggedAt = request.parsedLog.loggedAt
        var promotedRowID: UUID?

        if let rowID = queuedItem?.rowID,
           let index = inputRows.firstIndex(where: { $0.id == rowID }) {
            promoteInputRow(at: index, logId: logId, loggedAt: savedLoggedAt, imageRef: request.parsedLog.imageRef)
            promotedRowID = rowID
        }

        if promotedRowID == nil {
            let requestText = HomeLoggingTextMatch.normalizedRowText(request.parsedLog.rawText)
            let isImageSave = normalizedInputKind(request.parsedLog.inputKind, fallback: latestParseInputKind) == "image"
            if let index = inputRows.firstIndex(where: { row in
                guard !row.isSaved else { return false }
                if isImageSave, row.imagePreviewData != nil || row.imageRef != nil {
                    return true
                }
                return !requestText.isEmpty && HomeLoggingTextMatch.normalizedRowText(row.text) == requestText
            }) {
                promoteInputRow(at: index, logId: logId, loggedAt: savedLoggedAt, imageRef: request.parsedLog.imageRef)
                promotedRowID = inputRows[index].id
            }
        }

        if promotedRowID == nil, let queuedItem {
            let optimisticRow = HomeLoggingRowFactory.makePendingSaveRow(from: queuedItem)
            if !inputRows.contains(where: { $0.serverLogId == logId }) {
                let trailingEmptyIndex = inputRows.lastIndex { row in
                    !row.isSaved && row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                inputRows.insert(optimisticRow, at: trailingEmptyIndex ?? inputRows.count)
            }
        }

        if inputRows.allSatisfy({ $0.isSaved }) {
            inputRows.append(.empty())
        }
    }

    func promoteInputRow(at index: Int, logId: String, loggedAt: String, imageRef: String?) {
        guard inputRows.indices.contains(index) else { return }
        inputRows[index].isSaved = true
        inputRows[index].serverLogId = logId
        inputRows[index].serverLoggedAt = loggedAt
        inputRows[index].parsePhase = .idle
        if inputRows[index].imageRef == nil {
            inputRows[index].imageRef = imageRef
        }
        if inputRows[index].imageRef != nil {
            inputRows[index].imagePreviewData = nil
        }
    }

    func syncSavedLogToAppleHealthIfEnabled(_ request: SaveLogRequest, response: SaveLogResponse) async -> Bool {
        guard appStore.isHealthSyncEnabled else { return false }

        let loggedAtDate = HomeLoggingDateUtils.loggedAtFormatter.date(from: request.parsedLog.loggedAt) ??
            ISO8601DateFormatter().date(from: request.parsedLog.loggedAt) ??
            Date()
        do {
            return try await appStore.syncNutritionToAppleHealth(
                totals: request.parsedLog.totals,
                loggedAt: loggedAtDate,
                logId: response.logId,
                healthWriteKey: response.healthSync?.healthWriteKey ?? response.logId
            )
        } catch {
            if let healthError = error as? HealthKitServiceError,
               case .notAuthorized = healthError {
                appStore.disconnectAppleHealth()
            }
            return false
        }
    }

    func deleteSavedLogFromAppleHealthIfEnabled(row: HomeLogRow, healthSync: HealthSyncResponse?) async {
        guard appStore.isHealthSyncEnabled else { return }
        guard let serverLogId = row.serverLogId else { return }

        let loggedAtText = row.serverLoggedAt ?? HomeLoggingDateUtils.loggedAtFormatter.string(from: selectedSummaryDate)
        let loggedAtDate = HomeLoggingDateUtils.loggedAtFormatter.date(from: loggedAtText) ??
            ISO8601DateFormatter().date(from: loggedAtText) ??
            selectedSummaryDate
        let totals = NutritionTotals(
            calories: row.parsedItems.isEmpty ? Double(row.calories ?? 0) : row.parsedItems.reduce(0) { $0 + $1.calories },
            protein: row.parsedItems.reduce(0) { $0 + $1.protein },
            carbs: row.parsedItems.reduce(0) { $0 + $1.carbs },
            fat: row.parsedItems.reduce(0) { $0 + $1.fat }
        )

        do {
            _ = try await appStore.deleteNutritionFromAppleHealth(
                totals: totals,
                loggedAt: loggedAtDate,
                logId: serverLogId,
                healthWriteKey: healthSync?.healthWriteKey ?? serverLogId
            )
        } catch {
            if let healthError = error as? HealthKitServiceError,
               case .notAuthorized = healthError {
                appStore.disconnectAppleHealth()
            }
            // Apple Health cleanup is best-effort and must not resurrect a log
            // after the backend delete has already succeeded.
        }
    }
}
