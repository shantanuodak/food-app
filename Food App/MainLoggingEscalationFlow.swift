import Foundation

// Escalation / advanced AI flow extracted from MainLoggingShellView.
// Move-only refactor — function bodies and signatures unchanged.
// See docs/CLAUDE_PHASE_7A_REMAINING_HANDOFF.md Part 3.

extension MainLoggingShellView {
    func canEscalate(_ result: ParseLogResponse) -> Bool {
        guard appStore.isNetworkReachable else { return false }
        guard result.needsClarification else { return false }
        guard !isEscalating else { return false }
        if result.budget.escalationAllowed == false {
            return false
        }
        if escalationBlockedCode == "ESCALATION_DISABLED" || escalationBlockedCode == "BUDGET_EXCEEDED" {
            return false
        }
        return true
    }

    func escalationDisabledReason(_ result: ParseLogResponse) -> String? {
        if result.budget.escalationAllowed == false || escalationBlockedCode == "BUDGET_EXCEEDED" {
            return L10n.escalationBudgetReason
        }
        if escalationBlockedCode == "ESCALATION_DISABLED" {
            return L10n.escalationConfigReason
        }
        return nil
    }

    func startEscalationFlow() {
        guard appStore.isNetworkReachable else {
            escalationError = L10n.noNetworkEscalate
            return
        }
        guard let parseResult else {
            escalationError = L10n.parseBeforeEscalation
            return
        }

        guard parseResult.needsClarification else {
            escalationError = L10n.escalationNotRequired
            return
        }

        if parseResult.budget.escalationAllowed == false {
            escalationBlockedCode = "BUDGET_EXCEEDED"
            escalationError = L10n.escalationBudgetBlocked
            return
        }

        Task {
            await escalateCurrentParse(parseResult)
        }
    }

    func escalateCurrentParse(_ current: ParseLogResponse) async {
        isEscalating = true
        escalationError = nil
        escalationInfoMessage = nil
        defer { isEscalating = false }

        let request = EscalateParseRequest(
            parseRequestId: current.parseRequestId,
            loggedAt: current.loggedAt
        )

        do {
            let response = try await appStore.apiClient.escalateParse(request)
            parseResult = ParseLogResponse(
                requestId: response.requestId,
                parseRequestId: response.parseRequestId,
                parseVersion: response.parseVersion,
                route: response.route,
                cacheHit: false,
                sourcesUsed: response.sourcesUsed,
                fallbackUsed: false,
                fallbackModel: response.model,
                budget: response.budget,
                needsClarification: false,
                clarificationQuestions: [],
                reasonCodes: nil,
                retryAfterSeconds: nil,
                parseDurationMs: response.parseDurationMs,
                loggedAt: response.loggedAt,
                confidence: response.confidence,
                totals: response.totals,
                items: response.items,
                assumptions: [],
                cacheDebug: nil,
                inputKind: "text",
                extractedText: nil,
                imageMeta: nil,
                visionModel: nil,
                visionFallbackUsed: nil,
                dietaryFlags: nil
            )
            editableItems = response.items.map(EditableParsedItem.init(apiItem:))
            clearParseSchedulerState()
            if let parseResult {
                applyRowParseResult(parseResult)
            }
            parseInfoMessage = nil
            parseError = nil
            escalationBlockedCode = nil
            escalationError = nil
            escalationInfoMessage = L10n.escalationCompleted
            clearPendingSaveContext()
            appStore.setError(nil)
        } catch {
            handleAuthFailureIfNeeded(error)
            let mapped = userFriendlyEscalationError(error)
            escalationBlockedCode = mapped.blockCode
            escalationError = mapped.message
            escalationInfoMessage = nil
            appStore.setError(mapped.message)
        }
    }

    func buildSaveDraftRequest() -> SaveLogRequest? {
        guard let parseResult else { return nil }
        guard !hasDirtyRowsPendingParse else { return nil }
        guard activeParseRowID == nil else { return nil }
        guard queuedParseRowIDs.isEmpty else { return nil }
        guard !hasActiveParseRequest else { return nil }
        guard !pendingFollowupRequested else { return nil }

        // Use the rawText that was actually sent to the backend for this parse.
        // For text parses, use the last completed row's rawText (fixes the 422
        // mismatch where trimmedNoteText included all rows but the parseRequest
        // stored only the individual row text).
        // For image parses without a committed row snapshot, fall back to trimmedNoteText.
        let rawText: String
        if let lastRow = activeParseSnapshots.last {
            rawText = lastRow.rawText
        } else {
            rawText = trimmedNoteText
        }
        guard !rawText.isEmpty else { return nil }
        let effectiveLoggedAt = HomeLoggingDateUtils.loggedAtFormatter.string(from: draftLoggedAt ?? draftTimestampForSelectedDate())
        let inputKind = normalizedInputKind(parseResult.inputKind, fallback: latestParseInputKind)
        let currentImageRef = pendingImageStorageRef ??
            inputRows.compactMap(\.imageRef).first
        var saveItems = editableItems.map { $0.asSaveParsedFoodItem() }
        if saveItems.isEmpty && hasVisibleUnsavedCalorieRows {
            saveItems = [
                fallbackSaveItem(
                    rawText: rawText,
                    totals: displayedTotals,
                    confidence: parseResult.confidence,
                    nutritionSourceId: parseResult.items.first?.nutritionSourceId
                )
            ]
        }
        guard !saveItems.isEmpty else { return nil }

        return SaveLogRequest(
            parseRequestId: parseResult.parseRequestId,
            parseVersion: parseResult.parseVersion,
            parsedLog: SaveLogBody(
                rawText: rawText,
                loggedAt: effectiveLoggedAt,
                inputKind: inputKind,
                imageRef: currentImageRef,
                confidence: parseResult.confidence,
                totals: displayedTotals,
                sourcesUsed: parseResult.sourcesUsed,
                assumptions: parseResult.assumptions,
                items: saveItems
            )
        )
    }
}
