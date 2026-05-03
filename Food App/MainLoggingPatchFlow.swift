import Foundation

// Patch / quantity-fast-path flow extracted from MainLoggingSaveFlow.
// Move-only refactor — function bodies and signatures unchanged.
// See docs/CLAUDE_PHASE_7A_REMAINING_HANDOFF.md Part 1.

extension MainLoggingShellView {
    func handleQuantityFastPathUpdate(rowID: UUID) {
        guard let row = inputRows.first(where: { $0.id == rowID }) else { return }

        if let serverLogId = row.serverLogId {
            schedulePatchUpdate(rowID: rowID, serverLogId: serverLogId)
        } else {
            // New row, not yet saved server-side. The existing auto-save
            // loop reads inputRows[rowID].parsedItems when building the save
            // request, so the scaled items will be persisted on the next
            // auto-save tick. Nudge the timer so the edit doesn't sit idle.
            if activeParseSnapshots.contains(where: { $0.rowID == rowID }) {
                scheduleAutoSave()
            }
        }
    }

    /// Debounced PATCH scheduler for edits to server-backed rows. If the
    /// user keeps adjusting the number, each keystroke cancels the previous
    /// task and restarts the timer — so one sustained edit session becomes
    /// one network call.

    func schedulePatchUpdate(rowID: UUID, serverLogId: String) {
        pendingPatchTasks[rowID]?.cancel()
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: patchDebounceNs)
            guard !Task.isCancelled else { return }
            await performPatchUpdate(rowID: rowID, serverLogId: serverLogId)
        }
        pendingPatchTasks[rowID] = task
    }

    /// Build and dispatch the PATCH. Reads the row's CURRENT state at call
    /// time so we always persist the latest scaled values even if multiple
    /// edits were debounced together.

    func performPatchUpdate(rowID: UUID, serverLogId: String) async {
        guard appStore.isNetworkReachable else {
            pendingPatchTasks[rowID] = nil
            saveError = L10n.noNetworkSave
            return
        }
        guard let row = inputRows.first(where: { $0.id == rowID }),
              !row.parsedItems.isEmpty else {
            pendingPatchTasks[rowID] = nil
            return
        }

        let items: [SaveParsedFoodItem] = row.parsedItems.map { item in
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

        // Recompute totals from items so server validation passes.
        let totals = NutritionTotals(
            calories: row.parsedItems.reduce(0) { $0 + $1.calories },
            protein: row.parsedItems.reduce(0) { $0 + $1.protein },
            carbs: row.parsedItems.reduce(0) { $0 + $1.carbs },
            fat: row.parsedItems.reduce(0) { $0 + $1.fat }
        )

        // Intentionally pass loggedAt: nil so the backend preserves the
        // original food_logs.logged_at — a quantity fast-path edit shouldn't
        // "move" the entry to today just because the user adjusted a number.
        let body = PatchLogBody(
            rawText: row.text.trimmingCharacters(in: .whitespacesAndNewlines),
            loggedAt: nil,
            inputKind: "text",
            imageRef: row.imageRef,
            confidence: row.parsedItem.map { $0.matchConfidence } ?? 0.85,
            totals: totals,
            sourcesUsed: nil,
            assumptions: nil,
            items: items
        )
        let request = PatchLogRequest(
            parseRequestId: nil,
            parseVersion: nil,
            parsedLog: body
        )

        do {
            _ = try await appStore.apiClient.patchLog(id: serverLogId, request: request)
            // Re-mark the row as saved and invalidate the day cache so the
            // next refresh reads the updated totals. Use serverLoggedAt —
            // the original day — so we don't accidentally invalidate today's
            // cache for an edit to yesterday's entry.
            if let idx = inputRows.firstIndex(where: { $0.id == rowID }) {
                inputRows[idx].isSaved = true
            }
            let savedDay = HomeLoggingDateUtils.summaryDayString(
                fromLoggedAt: row.serverLoggedAt ?? summaryDateString,
                fallback: summaryDateString
            )
            await refreshDayAfterMutation(
                savedDay,
                postNutritionNotification: true,
                reconcilePendingQueueAfterLoad: true
            )
        } catch is CancellationError {
            return
        } catch {
            handleAuthFailureIfNeeded(error)
            // Keep the row editable so the user can try again; surface a
            // lightweight error without blocking the flow.
            saveError = userFriendlySaveError(error)
        }
        pendingPatchTasks[rowID] = nil
    }

    /// Convert a SaveLogRequest (POST-flavored) into a PatchLogRequest and
    /// send it to the backend. Preserves the parseRequestId/parseVersion
    /// from the save request since the edit did go through a fresh parse
    /// (the client-side fast path uses `performPatchUpdate` instead, which
    /// omits parse references).

    func submitRowPatch(
        serverLogId: String,
        saveRequest: SaveLogRequest,
        rowID: UUID
    ) async {
        guard appStore.isNetworkReachable else { return }
        let startedAt = Date()
        saveAttemptTelemetry.emit(
            parseRequestId: saveRequest.parseRequestId,
            rowID: rowID,
            outcome: .attempted,
            errorCode: nil,
            latencyMs: nil,
            source: .patch
        )

        // Copy the SaveLogBody into a PatchLogBody, dropping loggedAt so the
        // backend keeps the original. A text-change edit with re-parse
        // shouldn't bump the entry forward in time.
        let src = saveRequest.parsedLog
        let patchBody = PatchLogBody(
            rawText: src.rawText,
            loggedAt: nil,
            inputKind: src.inputKind,
            imageRef: src.imageRef,
            confidence: src.confidence,
            totals: src.totals,
            sourcesUsed: src.sourcesUsed,
            assumptions: src.assumptions,
            items: src.items
        )
        let patchRequest = PatchLogRequest(
            parseRequestId: saveRequest.parseRequestId,
            parseVersion: saveRequest.parseVersion,
            parsedLog: patchBody
        )

        do {
            _ = try await appStore.apiClient.patchLog(id: serverLogId, request: patchRequest)
            saveAttemptTelemetry.emit(
                parseRequestId: saveRequest.parseRequestId,
                rowID: rowID,
                outcome: .succeeded,
                errorCode: nil,
                latencyMs: Int(elapsedMs(since: startedAt)),
                source: .patch
            )
            // Prefer the row's original loggedAt (the day the entry actually
            // belongs to) over the save request's loggedAt (which reflects
            // when the re-parse fired).
            let originalDay = inputRows.first(where: { $0.id == rowID })?.serverLoggedAt
            let savedDay = HomeLoggingDateUtils.summaryDayString(
                fromLoggedAt: originalDay ?? saveRequest.parsedLog.loggedAt,
                fallback: summaryDateString
            )
            if let idx = inputRows.firstIndex(where: { $0.id == rowID }) {
                inputRows[idx].isSaved = true
            }
            await refreshDayAfterMutation(savedDay)
        } catch is CancellationError {
            return
        } catch {
            handleAuthFailureIfNeeded(error)
            saveError = userFriendlySaveError(error)
            saveAttemptTelemetry.emit(
                parseRequestId: saveRequest.parseRequestId,
                rowID: rowID,
                outcome: .failed,
                errorCode: saveAttemptErrorCode(error),
                latencyMs: Int(elapsedMs(since: startedAt)),
                source: .patch
            )
        }
    }

    // MARK: - Delete Saved Row
}
