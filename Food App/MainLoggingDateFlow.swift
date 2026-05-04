import SwiftUI
import UIKit

extension MainLoggingShellView {
    func handleSwipeTransition(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        // Use both distance and velocity — a fast flick with short distance should also work
        let velocity = value.predictedEndTranslation.width - value.translation.width

        guard abs(horizontal) >= 30 || abs(velocity) > 200 else {
            // Too small — snap back
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                dayTransitionOffset = 0
            }
            return
        }

        let days = horizontal > 0 ? -1 : 1
        shiftSelectedSummaryDate(byDays: days)
    }

    func shiftSelectedSummaryDate(byDays days: Int) {
        guard let moved = Calendar.current.date(byAdding: .day, value: days, to: selectedSummaryDate) else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dayTransitionOffset = 0
            }
            return
        }

        let normalized = clampedSummaryDate(moved)
        guard !Calendar.current.isDate(normalized, inSameDayAs: selectedSummaryDate) else {
            // Can't move (e.g. already on today, tried to go forward) — bounce back with a light tap
            let rigidFeedback = UIImpactFeedbackGenerator(style: .rigid)
            rigidFeedback.impactOccurred(intensity: 0.5)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dayTransitionOffset = 0
            }
            return
        }

        // Haptic tick for successful day change
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        // Flush any pending save for the current day BEFORE leaving it, so typed
        // entries don't get lost when the user swipes away mid-debounce.
        Task { @MainActor in
            await flushPendingAutoSaveIfEligible()
            protectDraftRowsForDateChange()

            // Reset transient parse/flow state so it doesn't leak across days.
            resetActiveParseStateForDateChange()

            // Slide content out in swipe direction, then slide new content in from opposite side
            let slideOut: CGFloat = days > 0 ? -120 : 120
            withAnimation(.easeIn(duration: 0.12)) {
                dayTransitionOffset = slideOut
            }

            // After a brief pause, update the date and slide content back from the opposite side
            try? await Task.sleep(nanoseconds: 120_000_000)

            // Pre-apply cached data to prevent flicker during transition
            let dateStr = HomeLoggingDateUtils.summaryRequestFormatter.string(from: normalized)
            if let cachedLogs = dayCacheLogs[dateStr] {
                dayLogs = cachedLogs
                syncInputRowsFromDayLogs(cachedLogs.logs, for: cachedLogs.date)
            }
            if let cachedSummary = dayCacheSummary[dateStr] {
                daySummary = cachedSummary
                daySummaryError = nil
            }

            dateTransitionResetHandled = true
            selectedSummaryDate = normalized
            dayTransitionOffset = -slideOut * 0.6
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                dayTransitionOffset = 0
            }
        }
    }

    @MainActor
    func transitionToSummaryDate(_ rawDate: Date) async {
        let normalized = clampedSummaryDate(rawDate)
        guard !Calendar.current.isDate(normalized, inSameDayAs: selectedSummaryDate) else { return }

        await flushPendingAutoSaveIfEligible()
        protectDraftRowsForDateChange()
        resetActiveParseStateForDateChange()

        dateTransitionResetHandled = true
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSummaryDate = normalized
        }
    }

    func draftTimestampForSelectedDate(reference: Date = Date()) -> Date {
        HomeLoggingDateUtils.draftTimestamp(for: selectedSummaryDate, reference: reference)
    }

    func ensureDraftTimingStarted() {
        let now = Date()
        if flowStartedAt == nil {
            flowStartedAt = now
        }
        if draftLoggedAt == nil {
            draftLoggedAt = draftTimestampForSelectedDate(reference: now)
        }
    }

    func draftDayString() -> String? {
        draftLoggedAt.map { HomeLoggingDateUtils.summaryRequestFormatter.string(from: $0) }
    }

    func currentDraftLoggedAtString(reference: Date = Date()) -> String {
        HomeLoggingDateUtils.loggedAtFormatter.string(
            from: draftLoggedAt ?? draftTimestampForSelectedDate(reference: reference)
        )
    }

    func captureDateChangeDraftRows() -> [DateChangeDraftRow] {
        let snapshotRowIDs = Set(activeParseSnapshots.map(\.rowID))
        let loggedAt = currentDraftLoggedAtString()

        return inputRows.compactMap { row in
            guard !row.isSaved else { return nil }
            // A saved row that the user tapped to "edit" gets `isSaved = false`
            // (HomeComposerView line ~95) but retains its `serverLogId` — so the
            // row already has a backend representation. Re-POSTing it as a
            // background draft on day-change creates a duplicate food_log.
            // Guard with serverLogId in addition to isSaved.
            guard row.serverLogId == nil else { return nil }
            guard !snapshotRowIDs.contains(row.id) else { return nil }

            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            return DateChangeDraftRow(
                rowID: row.id,
                text: text,
                loggedAt: loggedAt,
                inputKind: normalizedInputKind(latestParseInputKind, fallback: "text")
            )
        }
    }

    func protectDraftRowsForDateChange() {
        let drafts = captureDateChangeDraftRows()
        preserveCurrentDraftRowsForDateChange(backgroundDraftRowIDs: Set(drafts.map(\.rowID)))
        startDateChangeDraftPersistence(drafts)
    }

    func preserveCurrentDraftRowsForDateChange(backgroundDraftRowIDs: Set<UUID>) {
        let dateString = draftDayString() ?? summaryDateString
        let rowsToPreserve = inputRows.compactMap { row -> PreservedDateDraftRow? in
            guard !row.isSaved else { return nil }
            // Mirror the guard in `captureDateChangeDraftRows` — if the row was
            // a saved row demoted by tap-to-edit, it still has a serverLogId,
            // and we don't want to re-render it as a "preserved draft" on
            // return either (the server will already restore it).
            guard row.serverLogId == nil else { return nil }
            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            var preservedRow = row
            preservedRow.clearParsePhase()
            preservedRow.showInsertShimmer = false
            preservedRow.showCalorieRevealShimmer = false
            preservedRow.showCalorieUpdateShimmer = false
            preservedRow.isDeleting = false

            let backgroundManaged = backgroundDraftRowIDs.contains(row.id)
            if backgroundManaged,
               preservedRow.calories == nil,
               preservedRow.parsedItem == nil,
               preservedRow.parsedItems.isEmpty {
                preservedRow.normalizedTextAtParse = HomeLoggingTextMatch.normalizedRowText(text)
            }

            return PreservedDateDraftRow(
                row: preservedRow,
                isBackgroundManaged: backgroundManaged
            )
        }

        guard !rowsToPreserve.isEmpty else { return }

        var existingRows = preservedDraftRowsByDate[dateString] ?? []
        var indexByRowID: [UUID: Int] = [:]
        for (index, existingRow) in existingRows.enumerated() {
            indexByRowID[existingRow.row.id] = index
        }

        for preservedRow in rowsToPreserve {
            if let index = indexByRowID[preservedRow.row.id] {
                existingRows[index] = preservedRow
            } else {
                indexByRowID[preservedRow.row.id] = existingRows.count
                existingRows.append(preservedRow)
            }
        }

        preservedDraftRowsByDate[dateString] = existingRows
    }

    func startDateChangeDraftPersistence(_ drafts: [DateChangeDraftRow]) {
        for draft in drafts {
            dateChangeDraftTasks[draft.rowID]?.cancel()
            dateChangeDraftTasks[draft.rowID] = Task { @MainActor in
                await persistDateChangeDraft(draft)
                dateChangeDraftTasks[draft.rowID] = nil
            }
        }
    }

    @MainActor
    func persistDateChangeDraft(_ draft: DateChangeDraftRow) async {
        guard appStore.isNetworkReachable else {
            markPreservedDateDraftNeedsParse(rowID: draft.rowID, loggedAt: draft.loggedAt)
            return
        }

        do {
            let response = try await appStore.apiClient.parseLog(
                ParseLogRequest(text: draft.text, loggedAt: draft.loggedAt)
            )
            guard let request = buildDateChangeDraftSaveRequest(
                draft: draft,
                response: response
            ) else {
                markPreservedDateDraftNeedsParse(rowID: draft.rowID, loggedAt: draft.loggedAt)
                return
            }

            let idempotencyKey = resolveIdempotencyKey(forRowID: draft.rowID)
            upsertPendingSaveQueueItem(
                request: request,
                fingerprint: saveRequestFingerprint(request),
                idempotencyKey: idempotencyKey,
                rowID: draft.rowID
            )

            _ = await submitSave(
                request: request,
                idempotencyKey: idempotencyKey,
                isRetry: false,
                intent: .dateChangeBackground
            )
        } catch {
            handleAuthFailureIfNeeded(error)
            markPreservedDateDraftNeedsParse(rowID: draft.rowID, loggedAt: draft.loggedAt)
        }
    }

    func clampedSummaryDate(_ date: Date) -> Date {
        HomeLoggingDateUtils.clampedSummaryDate(date)
    }

}
