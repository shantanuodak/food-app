import Foundation

extension MainLoggingShellView {
    func canonicalParseRawText(
        response: ParseLogResponse,
        fallbackRawText: String
    ) -> String {
        let extracted = (response.extractedText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !extracted.isEmpty {
            return String(extracted.prefix(500))
        }

        let fallback = fallbackRawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty {
            return String(fallback.prefix(500))
        }

        let itemFallback = response.items.map(\.name).joined(separator: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(itemFallback.prefix(500))
    }

    func upsertParseSnapshot(
        rowID: UUID,
        response: ParseLogResponse,
        fallbackRawText: String,
        loggedAt: String? = nil,
        rowItems: [ParsedFoodItem]? = nil
    ) {
        let rowItemsSnapshot = rowItems
            ?? inputRows.first(where: { $0.id == rowID })?.parsedItems
            ?? response.items
        let rowEntry = ParseSnapshot(
            rowID: rowID,
            parseRequestId: response.parseRequestId,
            parseVersion: response.parseVersion,
            rawText: canonicalParseRawText(response: response, fallbackRawText: fallbackRawText),
            loggedAt: loggedAt ?? currentDraftLoggedAtString(),
            response: response,
            rowItems: rowItemsSnapshot,
            capturedAt: Date()
        )
        parseCoordinator.commit(snapshot: rowEntry)
    }


    @MainActor
    func scheduleDebouncedParse(for newValue: String) {
        debounceTask?.cancel()
        cancelAutoSaveTask()
        unresolvedRetryTask?.cancel()
        // Only mutate @State if the value is actually changing — avoids unnecessary re-renders
        if unresolvedRetryCount != 0 { unresolvedRetryCount = 0 }
        if parseError != nil { parseError = nil }
        if parseInfoMessage != nil { parseInfoMessage = nil }
        if saveError != nil { saveError = nil }
        if escalationError != nil { escalationError = nil }
        if escalationInfoMessage != nil { escalationInfoMessage = nil }
        if escalationBlockedCode != nil { escalationBlockedCode = nil }

        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parseResult = nil
            editableItems = []
            isEscalating = false
            flowStartedAt = nil
            draftLoggedAt = nil
            lastTimeToLogMs = nil
            lastAutoSavedContentFingerprint = nil
            autoSavedParseIDs = []
            parseCoordinator.clearAll()
            clearParseSchedulerState()
            let clearedRowIDs = Set(inputRows.filter { !$0.isSaved }.map(\.id))
            if !clearedRowIDs.isEmpty {
                let filteredQueue = pendingSaveQueue.filter { item in
                    guard item.serverLogId == nil, let rowID = item.rowID else {
                        return true
                    }
                    return !clearedRowIDs.contains(rowID)
                }
                if filteredQueue.count != pendingSaveQueue.count {
                    saveCoordinator.setPendingItems(filteredQueue, persist: true)
                    syncPendingQueueFromCoordinator(refreshRetryState: true)
                } else {
                    refreshRetryStateFromPendingQueue()
                }
            }
            // Preserve saved (history) rows — only reset the active input row
            let savedRows = inputRows.filter { $0.isSaved }
            inputRows = savedRows + [HomeLogRow.empty()]
            clearImageContext()
            clearPendingSaveContext()
            return
        }

        ensureDraftTimingStarted()

        if shouldDeferDebouncedParse(for: newValue) {
            // Defer ownership sync to after debounce — running it per-keystroke
            // iterates all rows, calls predictedLoadingRouteHint (regex), and
            // mutates parsePhase on every row, which tanks typing performance.
            return
        }

        let dirtyRowIDs = orderedDirtyRowIDsForCurrentInput()
        guard !dirtyRowIDs.isEmpty else {
            if !hasActiveParseRequest {
                clearParseSchedulerState()
            } else {
                queuedParseRowIDs = []
                latestQueuedNoteText = nil
                pendingFollowupRequested = false
                // Defer synchronizeParseOwnership to debounce callback
            }
            return
        }

        if !hasActiveParseRequest {
            activeParseRowID = dirtyRowIDs.first
            queuedParseRowIDs = Array(dirtyRowIDs.dropFirst())
        } else {
            queuedParseRowIDs = dirtyRowIDs.filter { $0 != activeParseRowID }
        }
        // Defer synchronizeParseOwnership to debounce callback
        let nonEmptyRowCount = inputRows.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let debounceNanos: UInt64 = nonEmptyRowCount > 1 ? 1_500_000_000 : 1_000_000_000

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                handleQueuedOrImmediateParseRequest(for: trimmed)
            }
        }
    }

    @MainActor
    func triggerParseNow() {
        debounceTask?.cancel()
        unresolvedRetryTask?.cancel()
        let trimmed = trimmedNoteText
        guard !trimmed.isEmpty else { return }
        ensureDraftTimingStarted()

        let dirtyRowIDs = orderedDirtyRowIDsForCurrentInput()
        guard !dirtyRowIDs.isEmpty else {
            if !hasActiveParseRequest {
                clearParseSchedulerState()
            } else {
                queuedParseRowIDs = []
                latestQueuedNoteText = nil
                pendingFollowupRequested = false
                synchronizeParseOwnership()
            }
            return
        }

        if !hasActiveParseRequest {
            activeParseRowID = dirtyRowIDs.first
            queuedParseRowIDs = Array(dirtyRowIDs.dropFirst())
        }
        handleQueuedOrImmediateParseRequest(for: trimmed)
    }

    @MainActor
    func parseCurrentText(_ text: String, requestSequence: Int) async {
        guard !text.isEmpty else { return }
        guard let snapshot = inFlightParseSnapshot, snapshot.requestSequence == requestSequence else { return }
        var shouldAdvanceToNextRow = true
        if !appStore.isNetworkReachable {
            parseInfoMessage = nil
            parseError = L10n.noNetworkParse
            parseTask = nil
            inFlightParseSnapshot = nil
            activeParseRowID = snapshot.activeRowID
            queuedParseRowIDs = orderedDirtyRowIDsForCurrentInput().filter { $0 != snapshot.activeRowID }
            pendingFollowupRequested = false
            latestQueuedNoteText = nil
            synchronizeParseOwnership()
            return
        }
        let startedAt = Date()
        parseInFlightCount += 1
        defer {
            parseInFlightCount = max(0, parseInFlightCount - 1)
            parseTask = nil
            inFlightParseSnapshot = nil
            if !Task.isCancelled {
                if shouldAdvanceToNextRow {
                    processNextQueuedParseIfNeeded()
                } else {
                    synchronizeParseOwnership()
                }
            }
        }

        do {
            let response: ParseLogResponse
            let durationMs: Double
            if let cachedResponse = parseCoordinator.cachedResponse(
                rowID: snapshot.activeRowID,
                text: text,
                loggedAt: snapshot.loggedAt
            ) {
                response = cachedResponse
                durationMs = 0
            } else {
                let request = ParseLogRequest(text: text, loggedAt: snapshot.loggedAt)
                response = try await appStore.apiClient.parseLog(request)
                durationMs = elapsedMs(since: startedAt)
                parseCoordinator.storeCachedResponse(
                    response,
                    rowID: snapshot.activeRowID,
                    text: text,
                    loggedAt: snapshot.loggedAt
                )
            }

            // Guard: if the target row no longer exists (e.g. user swiped to a different
            // day while the parse was in flight), silently discard the response instead
            // of applying it to some other day's data.
            guard inputRows.contains(where: { $0.id == snapshot.activeRowID }) else {
                shouldAdvanceToNextRow = false
                return
            }

            // Staleness guard: the user may have edited the row's text while
            // this parse was in flight (e.g. typed "chicken tenders", then
            // edited to "3 pieces chicken tenders" before the response came
            // back). Applying the stale response would map 1-piece calories
            // onto the new text AND stamp normalizedTextAtParse with the new
            // text, making the row look fresh — so `rowNeedsFreshParse` would
            // return false and no follow-up parse would fire. Instead, discard
            // the response here and let the deferred
            // `processNextQueuedParseIfNeeded()` (via shouldAdvanceToNextRow)
            // dispatch a fresh parse against the edited text.
            if let currentRow = inputRows.first(where: { $0.id == snapshot.activeRowID }) {
                let normalizedSent = HomeLoggingTextMatch.normalizedRowText(snapshot.text)
                let normalizedCurrent = HomeLoggingTextMatch.normalizedRowText(currentRow.text)
                if !normalizedSent.isEmpty && normalizedSent != normalizedCurrent {
                    // Leave the row marked dirty (we deliberately don't touch
                    // calories/parsedItems/normalizedTextAtParse) and let the
                    // defer block re-dispatch against the new text.
                    emitParseTelemetrySuccess(response: response, durationMs: durationMs, uiApplied: false)
                    return
                }
            }
#if DEBUG
            if let cacheDebug = response.cacheDebug {
                let reasonSummary = (response.reasonCodes ?? []).joined(separator: ",")
                let retryAfterSummary = response.retryAfterSeconds.map(String.init) ?? "nil"
                print("[parse_cache_debug] route=\(response.route) cacheHit=\(response.cacheHit) reasonCodes=\(reasonSummary) retryAfterSeconds=\(retryAfterSummary) scope=\(cacheDebug.scope) hash=\(cacheDebug.textHash) normalized=\(cacheDebug.normalizedText)")
            } else {
                let reasonSummary = (response.reasonCodes ?? []).joined(separator: ",")
                let retryAfterSummary = response.retryAfterSeconds.map(String.init) ?? "nil"
                print("[parse_cache_debug] route=\(response.route) cacheHit=\(response.cacheHit) reasonCodes=\(reasonSummary) retryAfterSeconds=\(retryAfterSummary)")
            }
#endif
            if shouldHoldUnresolvedResponse(response) {
                // Mark only this row as unresolved — don't block the rest of the queue
                if let idx = inputRows.firstIndex(where: { $0.id == snapshot.activeRowID }) {
                    inputRows[idx].setParseUnresolved()
                }
                logUnresolvedParseDiagnostics(response)
                emitParseTelemetrySuccess(response: response, durationMs: durationMs, uiApplied: false)
                // shouldAdvanceToNextRow stays true → defer will call processNextQueuedParseIfNeeded()
                return
            }

            unresolvedRetryCount = 0
            unresolvedRetryTask?.cancel()
            latestParseInputKind = normalizedInputKind(response.inputKind, fallback: "text")
            applyRowParseResult(response, targetRowIDs: [snapshot.activeRowID])
            parseInfoMessage = nil
            parseError = nil
            saveError = nil
            escalationError = nil
            escalationInfoMessage = nil
            escalationBlockedCode = nil
            clearPendingSaveContext()
            appStore.setError(nil)
            emitParseTelemetrySuccess(response: response, durationMs: durationMs, uiApplied: true)

            // Store this row's result with the rawText that was actually sent to the backend.
            // This is the fix for the 422 rawText mismatch: buildSaveDraftRequest/autoSaveIfNeeded
            // will use the committed row snapshot rawText instead of trimmedNoteText.
            //
            // Also snapshot the row's per-row parsedItems (computed by
            // applyRowParseResult immediately above). When multiple rows are
            // parsed together, response.items contains ALL items but the row's
            // parsedItems is already filtered to just this row's item(s). The
            // save path uses this snapshot so one row's food_log doesn't end up
            // carrying another row's macros.
            let rowItemsSnapshot = inputRows.first(where: { $0.id == snapshot.activeRowID })?.parsedItems
                ?? response.items
            upsertParseSnapshot(
                rowID: snapshot.activeRowID,
                response: response,
                fallbackRawText: text,
                loggedAt: snapshot.loggedAt,
                rowItems: rowItemsSnapshot
            )

            let remainingDirtyRowIDs = orderedDirtyRowIDsForCurrentInput()
            activeParseRowID = remainingDirtyRowIDs.first
            queuedParseRowIDs = Array(remainingDirtyRowIDs.dropFirst())
            pendingFollowupRequested = !remainingDirtyRowIDs.isEmpty
            latestQueuedNoteText = remainingDirtyRowIDs.isEmpty ? nil : trimmedNoteText

            // Always show accumulated results so the UI never goes blank while the queue drains.
            parseResult = response
            // Use each entry's row-specific items (not the full response.items)
            // so items from a combined multi-row parse aren't duplicated in the
            // details drawer once the individual rows have their own entries.
            editableItems = activeParseSnapshots
                .flatMap { $0.rowItems }
                .map(EditableParsedItem.init(apiItem:))

            if remainingDirtyRowIDs.isEmpty {
                scheduleDetailsDrawer(for: response)
            }
            // Save completed rows even if other rows are still dirty/queued.
            // This prevents visible calorie rows from being left unsaved.
            scheduleAutoSave()
        } catch {
            let durationMs = elapsedMs(since: startedAt)
            if error is CancellationError || Task.isCancelled {
                return
            }
            shouldAdvanceToNextRow = false
            unresolvedRetryTask?.cancel()
            parseCoordinator.markFailed(rowID: snapshot.activeRowID)
            handleAuthFailureIfNeeded(error)
            activeParseRowID = snapshot.activeRowID
            queuedParseRowIDs = orderedDirtyRowIDsForCurrentInput().filter { $0 != snapshot.activeRowID }
            pendingFollowupRequested = false
            latestQueuedNoteText = nil
            let message = userFriendlyParseError(error)
            parseInfoMessage = nil
            parseError = message
            appStore.setError(message)
            emitParseTelemetryFailure(error: error, durationMs: durationMs, uiApplied: true)
            // Parse failure on one row should not block autosave for already
            // parsed rows that have visible calories.
            if hasSaveableRowsPending {
                scheduleAutoSave()
            }
        }
    }

    func shouldHoldUnresolvedResponse(_ response: ParseLogResponse) -> Bool {
        guard response.items.isEmpty else { return false }
        if isTrustedZeroNutritionResponse(response) {
            return false
        }
        return response.route == "unresolved" || response.route == "gemini"
    }

    func isTrustedZeroNutritionResponse(_ response: ParseLogResponse) -> Bool {
        guard response.items.isEmpty else { return false }
        guard !response.needsClarification else { return false }
        guard response.confidence >= 0.70 else { return false }
        return response.totals.calories <= 0.05 &&
            response.totals.protein <= 0.05 &&
            response.totals.carbs <= 0.05 &&
            response.totals.fat <= 0.05
    }

    func logUnresolvedParseDiagnostics(_ response: ParseLogResponse) {
#if DEBUG
        let reasonSummary = (response.reasonCodes ?? []).joined(separator: ",")
        let retryAfterSummary = response.retryAfterSeconds.map(String.init) ?? "nil"
        print(
            "[parse_unresolved_debug] route=\(response.route) fallbackUsed=\(response.fallbackUsed) " +
                "needsClarification=\(response.needsClarification) reasonCodes=\(reasonSummary) " +
                "retryAfterSeconds=\(retryAfterSummary) confidence=\(response.confidence)"
        )
#endif
    }

    func shouldDeferDebouncedParse(for rawText: String) -> Bool {
        guard rawText.contains("\n") else { return false }
        let lines = rawText.components(separatedBy: .newlines)
        guard let lastLine = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines), !lastLine.isEmpty else {
            return false
        }

        let sanitized = lastLine.replacingOccurrences(of: "[,;:]+$", with: "", options: .regularExpression)
        return sanitized.range(of: #"^\d+(?:[./]\d+)?$"#, options: .regularExpression) != nil
    }

    @MainActor
    func handleQueuedOrImmediateParseRequest(for text: String) {
        guard !text.isEmpty else { return }
        let dirtyRowIDs = orderedDirtyRowIDsForCurrentInput()
        guard let firstDirtyRowID = dirtyRowIDs.first else {
            clearParseSchedulerState()
            return
        }

        if hasActiveParseRequest {
            if activeParseRowID == nil {
                activeParseRowID = firstDirtyRowID
            }
            queuedParseRowIDs = dirtyRowIDs.filter { $0 != activeParseRowID }
            latestQueuedNoteText = text
            pendingFollowupRequested = true
            synchronizeParseOwnership()
            return
        }

        let rowText = inputRows.first(where: { $0.id == firstDirtyRowID })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? text
        startTextParse(
            text: rowText.isEmpty ? text : rowText,
            activeRowID: firstDirtyRowID,
            dirtyRowIDs: dirtyRowIDs
        )
    }

    @MainActor
    func startTextParse(
        text: String,
        activeRowID: UUID,
        dirtyRowIDs: [UUID]
    ) {
        parseRequestSequence += 1
        let loggedAt = currentDraftLoggedAtString()
        inFlightParseSnapshot = InFlightParseSnapshot(
            text: text,
            loggedAt: loggedAt,
            requestSequence: parseRequestSequence,
            activeRowID: activeRowID,
            dirtyRowIDsAtDispatch: dirtyRowIDs
        )
        activeParseRowID = activeRowID
        queuedParseRowIDs = Array(dirtyRowIDs.dropFirst())
        pendingFollowupRequested = false
        latestQueuedNoteText = nil
        parseInfoMessage = nil
        parseError = nil
        appStore.setError(nil)
        parseCoordinator.markInFlight(rowID: activeRowID)
        synchronizeParseOwnership()
        parseTask = Task { @MainActor in
            await parseCurrentText(text, requestSequence: parseRequestSequence)
        }
    }

    @MainActor
    func processNextQueuedParseIfNeeded() {
        let dirtyRowIDs = orderedDirtyRowIDsForCurrentInput()
        guard let nextActiveRowID = dirtyRowIDs.first else {
            clearParseSchedulerState()
            return
        }

        activeParseRowID = nextActiveRowID
        queuedParseRowIDs = Array(dirtyRowIDs.dropFirst())
        synchronizeParseOwnership()

        let nextText = inputRows.first(where: { $0.id == nextActiveRowID })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !nextText.isEmpty else { return }

        startTextParse(
            text: nextText,
            activeRowID: nextActiveRowID,
            dirtyRowIDs: dirtyRowIDs
        )
    }

    func clearParseSchedulerState() {
        if let activeParseRowID {
            parseCoordinator.cancelInFlight(rowID: activeParseRowID)
        }
        activeParseRowID = nil
        queuedParseRowIDs = []
        inFlightParseSnapshot = nil
        pendingFollowupRequested = false
        latestQueuedNoteText = nil
        synchronizeParseOwnership()
    }

    /// Clears ALL per-day transient parse state. Called when the user changes the
    /// selected date (swipe or calendar pick) so parse spinners / partial results
    /// from the previous day don't leak onto the new day's view.
    func resetActiveParseStateForDateChange() {
        // Cancel in-flight tasks first so their completion handlers bail out
        parseTask?.cancel()
        debounceTask?.cancel()
        cancelAutoSaveTask()
        unresolvedRetryTask?.cancel()

        // Drop active draft rows immediately on date changes so a draft from
        // one day cannot follow the user into another day while the network
        // reload is still in flight.
        let savedRows = inputRows.filter { $0.isSaved }
        inputRows = savedRows.isEmpty ? [HomeLogRow.empty()] : savedRows

        if parseResult != nil { parseResult = nil }
        if !editableItems.isEmpty { editableItems = [] }
        if activeParseRowID != nil { activeParseRowID = nil }
        if !queuedParseRowIDs.isEmpty { queuedParseRowIDs = [] }
        if inFlightParseSnapshot != nil { inFlightParseSnapshot = nil }
        if !autoSavedParseIDs.isEmpty { autoSavedParseIDs = [] }
        parseCoordinator.clearAll()
        if parseInFlightCount != 0 { parseInFlightCount = 0 }
        if unresolvedRetryCount != 0 { unresolvedRetryCount = 0 }

        // Clear transient error/info messages
        if parseError != nil { parseError = nil }
        if parseInfoMessage != nil { parseInfoMessage = nil }
        if saveError != nil { saveError = nil }
        if escalationError != nil { escalationError = nil }
        if escalationInfoMessage != nil { escalationInfoMessage = nil }
        if escalationBlockedCode != nil { escalationBlockedCode = nil }
        if saveSuccessMessage != nil { saveSuccessMessage = nil }

        // Reset flow tracking (new day = new flow)
        if flowStartedAt != nil { flowStartedAt = nil }
        if draftLoggedAt != nil { draftLoggedAt = nil }
        if lastTimeToLogMs != nil { lastTimeToLogMs = nil }
        if lastAutoSavedContentFingerprint != nil { lastAutoSavedContentFingerprint = nil }

        // Clear image-related @State vars (but NOT inputRows image data —
        // that gets replaced when syncInputRowsFromDayLogs runs)
        pendingImageData = nil
        pendingImagePreviewData = nil
        pendingImageMimeType = nil
        pendingImageStorageRef = nil
        latestParseInputKind = "text"
        selectedCameraSource = nil
    }

    func synchronizeParseOwnership() {
        let queuedSet = Set(queuedParseRowIDs)
        for index in inputRows.indices {
            let rowID = inputRows[index].id
            if hasActiveParseRequest, rowID == activeParseRowID {
                // Only mutate if not already in .active state to avoid re-rendering
                if !inputRows[index].isLoading {
                    let startedAt = inputRows[index].loadingStatusStartedAt ?? Date()
                    inputRows[index].setParseActive(
                        routeHint: HomeLogRow.predictedLoadingRouteHint(for: inputRows[index].text),
                        startedAt: startedAt
                    )
                }
            } else if !hasActiveParseRequest, rowID == activeParseRowID, parseError != nil {
                if !inputRows[index].isFailed {
                    inputRows[index].setParseFailed()
                }
            } else if queuedSet.contains(rowID) {
                if !inputRows[index].isQueued {
                    inputRows[index].setParseQueued()
                }
            } else if inputRows[index].isUnresolved {
                // Preserve "Edit & Retry" — user needs to act on this row
                continue
            } else {
                if inputRows[index].parsePhase != .idle {
                    inputRows[index].clearParsePhase()
                }
            }
        }
        updateParseQueueInfoMessage()
    }

    func updateParseQueueInfoMessage() {
        guard parseError == nil else { return }
        if hasActiveParseRequest && !queuedParseRowIDs.isEmpty {
            parseInfoMessage = L10n.parseQueuedLabel
        } else if parseInfoMessage == L10n.parseQueuedLabel {
            parseInfoMessage = nil
        }
    }

    func orderedDirtyRowIDsForCurrentInput() -> [UUID] {
        inputRows.compactMap { row in
            rowNeedsFreshParse(row) ? row.id : nil
        }
    }

    func rowNeedsFreshParse(_ row: HomeLogRow) -> Bool {
        let normalizedCurrentText = HomeLoggingTextMatch.normalizedRowText(row.text)
        guard !normalizedCurrentText.isEmpty else {
            return false
        }

        if let normalizedTextAtParse = row.normalizedTextAtParse {
            return normalizedTextAtParse != normalizedCurrentText
        }

        if row.calories != nil {
            return false
        }

        // Row has content but no parse snapshot yet.
        return row.parsedItem == nil && row.parsedItems.isEmpty
    }

    func applyRowParseResult(_ response: ParseLogResponse, targetRowIDs: Set<UUID>? = nil) {
        let targetRowIDSet = targetRowIDs ?? Set(inputRows.map(\.id))
        let geminiAuthoritative = isGeminiAuthoritativeResponse(response)
        let approximateDisplay = response.needsClarification || response.confidence < 0.70

        let nonEmptyIndices = inputRows.indices.filter {
            !inputRows[$0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !nonEmptyIndices.isEmpty else { return }

        let candidateRowIndices = nonEmptyIndices.filter { targetRowIDSet.contains(inputRows[$0].id) }
        guard !candidateRowIndices.isEmpty else { return }

        let rowsNeedingFreshMapping: Set<Int> = Set(candidateRowIndices.filter { rowIndex in
            let row = inputRows[rowIndex]
            let normalized = HomeLoggingTextMatch.normalizedRowText(row.text)
            guard !normalized.isEmpty else { return false }
            if row.normalizedTextAtParse == nil { return true }
            if row.normalizedTextAtParse != normalized { return true }
            return row.calories == nil || (row.parsedItem == nil && row.parsedItems.isEmpty)
        })

        let lockedRowIndices: Set<Int> = Set(candidateRowIndices.filter { rowIndex in
            guard let existingCalories = inputRows[rowIndex].calories, existingCalories > 0 else {
                return false
            }
            let normalized = HomeLoggingTextMatch.normalizedRowText(inputRows[rowIndex].text)
            guard !normalized.isEmpty else { return false }
            return inputRows[rowIndex].normalizedTextAtParse == normalized
        })

        for rowIndex in candidateRowIndices where rowsNeedingFreshMapping.contains(rowIndex) && !lockedRowIndices.contains(rowIndex) {
            inputRows[rowIndex].calories = nil
            inputRows[rowIndex].calorieRangeText = nil
            inputRows[rowIndex].isApproximate = false
            inputRows[rowIndex].parsedItem = nil
            inputRows[rowIndex].parsedItems = []
            inputRows[rowIndex].editableItemIndices = []
            inputRows[rowIndex].normalizedTextAtParse = nil
        }
        var mappedCaloriesByRow: [Int: Int] = [:]
        var mappedItemsByRow: [Int: ParsedFoodItem] = [:]
        var mappedItemOffsetsByRow: [Int: Int] = [:]
        var usedItemOffsets: Set<Int> = []

        // Whole-note text parsing remains backend-driven, but queued UI should only update the active target row.
        // Restrict direct in-order mapping to full-application cases; targeted passes rely on row/item matching.
        if targetRowIDs == nil, geminiAuthoritative {
            let assignCount = min(nonEmptyIndices.count, response.items.count)
            for offset in 0..<assignCount {
                let rowIndex = nonEmptyIndices[offset]
                let itemOffset = offset
                guard let normalizedCalories = normalizedRowCalories(
                    from: response.items[itemOffset].calories,
                    response: response
                ) else {
                    continue
                }
                mappedCaloriesByRow[rowIndex] = normalizedCalories
                mappedItemsByRow[rowIndex] = response.items[itemOffset]
                mappedItemOffsetsByRow[rowIndex] = itemOffset
                usedItemOffsets.insert(itemOffset)
            }
        } else if targetRowIDs == nil, nonEmptyIndices.count == response.items.count {
            // Non-Gemini mode: in-order assignment only when parser rows line up with UI rows.
            for (itemOffset, rowIndex) in nonEmptyIndices.enumerated() {
                guard let normalizedCalories = normalizedRowCalories(
                    from: response.items[itemOffset].calories,
                    response: response
                ) else {
                    continue
                }
                mappedCaloriesByRow[rowIndex] = normalizedCalories
                mappedItemsByRow[rowIndex] = response.items[itemOffset]
                mappedItemOffsetsByRow[rowIndex] = itemOffset
                usedItemOffsets.insert(itemOffset)
            }
        }

        // Second attempt: best-match remap for parser-expanded or parser-collapsed responses.
        for rowIndex in candidateRowIndices where mappedCaloriesByRow[rowIndex] == nil {
            let rowText = inputRows[rowIndex].text
            var bestOffset: Int?
            var bestScore = 0.0

            for (itemOffset, item) in response.items.enumerated() where !usedItemOffsets.contains(itemOffset) {
                let score = HomeLoggingTextMatch.rowItemMatchScore(rowText: rowText, itemName: item.name)
                if score > bestScore {
                    bestScore = score
                    bestOffset = itemOffset
                }
            }

            let bestMatchThreshold = geminiAuthoritative ? 0.20 : 0.35
            if let bestOffset, bestScore >= bestMatchThreshold {
                if let normalizedCalories = normalizedRowCalories(
                    from: response.items[bestOffset].calories,
                    response: response
                ) {
                    mappedCaloriesByRow[rowIndex] = normalizedCalories
                    mappedItemsByRow[rowIndex] = response.items[bestOffset]
                    mappedItemOffsetsByRow[rowIndex] = bestOffset
                    usedItemOffsets.insert(bestOffset)
                }
            }
        }

        // Final fallback: assign remaining parser items in order only for high-confidence non-Gemini routes.
        // For Gemini/clarification flows this can create misleading duplicated values across rows.
        let unmatchedRowIndices = candidateRowIndices.filter {
            rowsNeedingFreshMapping.contains($0) && mappedCaloriesByRow[$0] == nil
        }
        let remainingItemOffsets = response.items.indices.filter { !usedItemOffsets.contains($0) }
        let canUseSequentialFallback = !geminiAuthoritative && !response.needsClarification && response.confidence >= 0.75
        if canUseSequentialFallback, !unmatchedRowIndices.isEmpty, !remainingItemOffsets.isEmpty {
            let assignCount = min(unmatchedRowIndices.count, remainingItemOffsets.count)
            for offset in 0..<assignCount {
                let rowIndex = unmatchedRowIndices[offset]
                let itemOffset = remainingItemOffsets[offset]
                guard let normalizedCalories = normalizedRowCalories(
                    from: response.items[itemOffset].calories,
                    response: response
                ) else {
                    continue
                }
                mappedCaloriesByRow[rowIndex] = normalizedCalories
                mappedItemsByRow[rowIndex] = response.items[itemOffset]
                mappedItemOffsetsByRow[rowIndex] = itemOffset
                usedItemOffsets.insert(itemOffset)
            }
        }

        debugRowParseMapping(
            response: response,
            nonEmptyIndices: nonEmptyIndices,
            rowsNeedingFreshMapping: rowsNeedingFreshMapping,
            lockedRowIndices: lockedRowIndices,
            mappedCaloriesByRow: mappedCaloriesByRow
        )

        for rowIndex in candidateRowIndices where rowsNeedingFreshMapping.contains(rowIndex) {
            if let mapped = mappedCaloriesByRow[rowIndex] {
                if lockedRowIndices.contains(rowIndex) {
                    continue
                }
                // Trigger calorie reveal shimmer when calories appear for the first time
                if inputRows[rowIndex].calories == nil && mapped > 0 {
                    inputRows[rowIndex].showCalorieRevealShimmer = true
                }
                inputRows[rowIndex].calories = mapped
                inputRows[rowIndex].isApproximate = approximateDisplay
                inputRows[rowIndex].calorieRangeText = approximateDisplay ? estimatedCalorieRangeText(for: mapped) : nil
                inputRows[rowIndex].parsedItem = mappedItemsByRow[rowIndex]
                inputRows[rowIndex].parsedItems = mappedItemsByRow[rowIndex].map { [$0] } ?? []
                inputRows[rowIndex].editableItemIndices = mappedItemOffsetsByRow[rowIndex].map { [$0] } ?? []
                inputRows[rowIndex].normalizedTextAtParse = HomeLoggingTextMatch.normalizedRowText(inputRows[rowIndex].text)
            }
        }

        // Multi-item-to-single-row override: when only one row is being
        // parsed (whether because the caller scoped via `targetRowIDs` or
        // because we're parsing the full input and only one row has text),
        // ALL parser items belong to that row. Without this branch, the
        // per-row loop above would assign just one item and silently drop
        // the rest — the canonical bug where typing
        // "2 naan, butter paneer masala, rice bowl" yielded only Naan.
        // The original code restricted this to `targetRowIDs == nil`, but
        // typing into a specific row sets `targetRowIDs = [thatRowID]`,
        // which is exactly the case that needs the multi-item assignment.
        if candidateRowIndices.count == 1,
           let normalizedTotalsCalories = normalizedRowCalories(from: response.totals.calories, response: response) {
            let onlyRowIndex = candidateRowIndices[0]
            if rowsNeedingFreshMapping.contains(onlyRowIndex) {
                inputRows[onlyRowIndex].calories = normalizedTotalsCalories
                inputRows[onlyRowIndex].isApproximate = approximateDisplay
                inputRows[onlyRowIndex].calorieRangeText = approximateDisplay
                    ? estimatedCalorieRangeText(for: normalizedTotalsCalories)
                    : nil
                if let firstItem = response.items.first {
                    inputRows[onlyRowIndex].parsedItem = firstItem
                }
                inputRows[onlyRowIndex].parsedItems = response.items
                inputRows[onlyRowIndex].editableItemIndices = Array(response.items.indices)
                inputRows[onlyRowIndex].normalizedTextAtParse = HomeLoggingTextMatch.normalizedRowText(inputRows[onlyRowIndex].text)
            }
        }
    }

    func estimatedCalorieRangeText(for calories: Int) -> String {
        let lower = max(0, Int((Double(calories) * 0.8).rounded()))
        let upper = max(lower + 1, Int((Double(calories) * 1.2).rounded()))
        return "\(lower)-\(upper) cal"
    }

    func normalizedRowCalories(from rawCalories: Double, response: ParseLogResponse) -> Int? {
        let rounded = Int(rawCalories.rounded())
        guard rounded >= 0 else {
            return nil
        }

        // Keep non-Gemini clarification rows from showing empty zero values.
        if response.needsClarification && rounded == 0 && !isGeminiAuthoritativeResponse(response) {
            return nil
        }

        return rounded
    }

    func isGeminiAuthoritativeResponse(_ response: ParseLogResponse) -> Bool {
        response.route == "gemini" && !response.items.isEmpty
    }

    func debugRowParseMapping(
        response: ParseLogResponse,
        nonEmptyIndices: [Int],
        rowsNeedingFreshMapping: Set<Int>,
        lockedRowIndices: Set<Int>,
        mappedCaloriesByRow: [Int: Int]
    ) {
#if DEBUG
        let rowSummary = nonEmptyIndices.map { rowIndex in
            let action = rowsNeedingFreshMapping.contains(rowIndex) ? "update" : "keep"
            let lockState = lockedRowIndices.contains(rowIndex) ? "locked" : "free"
            let mapped = mappedCaloriesByRow[rowIndex].map(String.init) ?? "nil"
            let normalized = HomeLoggingTextMatch.normalizedRowText(inputRows[rowIndex].text)
            return "#\(rowIndex){action=\(action),lock=\(lockState),mapped=\(mapped),text=\(normalized)}"
        }.joined(separator: " | ")
        print("[parse_row_map] route=\(response.route) confidence=\(String(format: "%.3f", response.confidence)) rows=\(rowSummary)")
#endif
    }

    func scheduleDetailsDrawer(for response: ParseLogResponse) {
        detailsDrawerMode = .full
    }

}
