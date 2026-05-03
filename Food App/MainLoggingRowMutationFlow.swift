import Foundation
import SwiftUI
import UIKit

// Row mutation / delete / focus / day-hydration flow extracted from
// MainLoggingShellView. Move-only refactor — function bodies and
// signatures unchanged.
// See docs/CLAUDE_PHASE_7A_REMAINING_HANDOFF.md Part 2.

extension MainLoggingShellView {
    func pendingSyncKey(for item: PendingSaveQueueItem) -> String {
        if let rowID = item.rowID {
            return "row:\(rowID.uuidString)"
        }
        return "key:\(item.idempotencyKey)"
    }

    func focusComposerInputFromBackgroundTap() {
        guard !isVoiceOverlayPresented,
              !isDetailsDrawerPresented,
              !isProfilePresented,
              !isCalendarPresented,
              !isNutritionSummaryPresented,
              !isStreakDrawerPresented,
              !isCustomCameraPresented,
              !isCameraAnalysisSheetPresented else {
            return
        }

        inputMode = .text
        NotificationCenter.default.post(name: .focusComposerInputFromBackgroundTap, object: nil)
    }

    func refreshNutritionStateForVisibleDay() {
        invalidateDayCache(for: summaryDateString)
        refreshDaySummary()
        refreshDayLogs()
    }

    func refreshNutritionStateAfterProgressChange(_ notification: Notification) {
        guard let savedDay = notification.userInfo?["savedDay"] as? String else {
            refreshNutritionStateForVisibleDay()
            return
        }

        invalidateDayCache(for: savedDay)
        guard savedDay == summaryDateString else { return }
        refreshDaySummary()
        refreshDayLogs()
    }

    func handleServerBackedRowCleared(_ row: HomeLogRow) {
        guard let deleteContext = serverBackedDeleteContext(for: row) else { return }
        let serverLogId = deleteContext.serverLogId

        isNoteEditorFocused = false
        activeEditingRowID = nil
        NotificationCenter.default.post(name: .dismissKeyboardFromTabBar, object: nil)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        clearTransientWorkForDeletedRow(rowID: row.id)
        _ = removePendingSaveQueueItems(forRowID: row.id)
        locallyDeletedPendingRowIDs.remove(row.id)
        pendingDeleteTasks[row.id]?.cancel()

        let originalIndex = inputRows.firstIndex(where: { $0.id == row.id }) ?? inputRows.count
        var restoredRow = row
        restoredRow.serverLogId = serverLogId
        restoredRow.serverLoggedAt = restoredRow.serverLoggedAt ?? deleteContext.savedDay
        restoredRow.isSaved = true
        restoredRow.parsePhase = .idle
        restoredRow.isDeleting = false

        if let index = inputRows.firstIndex(where: { $0.id == row.id }) {
            inputRows[index] = restoredRow
            inputRows[index].isDeleting = true
        }

        let savedDay = deleteContext.savedDay
        removeDeletedLogFromVisibleDayLogs(logId: serverLogId, dateString: savedDay)
        saveError = nil

        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                inputRows.removeAll { $0.id == row.id }
                if inputRows.allSatisfy({ $0.isSaved }) {
                    inputRows.append(.empty())
                }
            }
            await deleteServerBackedRow(
                row: restoredRow,
                serverLogId: serverLogId,
                savedDay: savedDay,
                originalIndex: originalIndex
            )
        }
        pendingDeleteTasks[row.id] = task
    }

    func serverBackedDeleteContext(for row: HomeLogRow) -> (serverLogId: String, savedDay: String)? {
        if let serverLogId = row.serverLogId {
            return (
                serverLogId,
                HomeLoggingDateUtils.summaryDayString(
                    fromLoggedAt: row.serverLoggedAt ?? summaryDateString,
                    fallback: summaryDateString
                )
            )
        }

        guard let queuedItem = pendingQueueItem(forRowID: row.id),
              let serverLogId = queuedItem.serverLogId else {
            return nil
        }

        return (serverLogId, queuedItem.dateString)
    }

    func clearTransientWorkForDeletedRow(rowID: UUID) {
        pendingPatchTasks[rowID]?.cancel()
        pendingPatchTasks[rowID] = nil

        if activeParseRowID == rowID {
            parseTask?.cancel()
            parseTask = nil
            activeParseRowID = nil
            parseCoordinator.cancelInFlight(rowID: rowID)
        }
        queuedParseRowIDs.removeAll { $0 == rowID }
        if inFlightParseSnapshot?.activeRowID == rowID {
            inFlightParseSnapshot = nil
        }

        let removedParseIDs = activeParseSnapshots
            .filter { $0.rowID == rowID }
            .map(\.parseRequestId)
        if !removedParseIDs.isEmpty {
            autoSavedParseIDs.subtract(removedParseIDs)
        }
        parseCoordinator.removeSnapshot(rowID: rowID)
        synchronizeParseOwnership()
    }

    func deleteServerBackedRow(
        row: HomeLogRow,
        serverLogId: String,
        savedDay: String,
        originalIndex: Int
    ) async {
        defer { pendingDeleteTasks[row.id] = nil }

        guard appStore.isNetworkReachable else {
            restoreDeletedRow(row, at: originalIndex)
            saveError = L10n.noNetworkSave
            return
        }

        do {
            let response = try await appStore.apiClient.deleteLog(id: serverLogId)
            await deleteSavedLogFromAppleHealthIfEnabled(row: row, healthSync: response.healthSync)
            await refreshDayAfterMutation(savedDay)
        } catch is CancellationError {
            return
        } catch {
            handleAuthFailureIfNeeded(error)
            restoreDeletedRow(row, at: originalIndex)
            saveError = userFriendlySaveError(error)
        }
    }

    func restoreDeletedRow(_ row: HomeLogRow, at originalIndex: Int) {
        guard !inputRows.contains(where: { $0.id == row.id }) else { return }
        var restored = row
        restored.isDeleting = false
        let insertIndex = min(max(originalIndex, 0), inputRows.count)
        inputRows.insert(restored, at: insertIndex)
    }

    func removeDeletedLogFromVisibleDayLogs(logId: String, dateString: String) {
        guard summaryDateString == dateString else { return }
        if let existing = dayLogs, existing.date == dateString {
            dayLogs = DayLogsResponse(
                date: existing.date,
                timezone: existing.timezone,
                logs: existing.logs.filter { $0.id != logId }
            )
        }
        if let cached = dayCacheLogs[dateString] {
            dayCacheLogs[dateString] = DayLogsResponse(
                date: cached.date,
                timezone: cached.timezone,
                logs: cached.logs.filter { $0.id != logId }
            )
        }
    }

    func refreshDayAfterMutation(
        _ dateString: String,
        postNutritionNotification: Bool = true,
        reconcilePendingQueueAfterLoad: Bool = false
    ) async {
        invalidateDayCache(for: dateString)
        await loadDaySummary(forcedDate: dateString, skipCache: true)
        await loadDayLogs(forcedDate: dateString, skipCache: true)

        if reconcilePendingQueueAfterLoad, let logs = dayLogs, logs.date == dateString {
            reconcilePendingSaveQueue(with: logs.logs, for: dateString)
        }

        if postNutritionNotification {
            NotificationCenter.default.post(
                name: .nutritionProgressDidChange,
                object: nil,
                userInfo: ["savedDay": dateString]
            )
        }
    }

    func hydrateVisibleDayLogsFromDiskIfNeeded() {
        let dateString = summaryDateString
        guard dayLogs == nil, let cached = loadDayLogsFromCache(date: dateString) else { return }
        dayLogs = cached
        dayCacheLogs[dateString] = cached
        syncInputRowsFromDayLogs(cached.logs, for: cached.date)
    }

    func bootstrapAuthenticatedHomeIfNeeded() {
        guard appStore.isSessionRestored, !hasBootstrappedAuthenticatedHome else { return }
        hasBootstrappedAuthenticatedHome = true

        submitRestoredPendingSaveIfPossible()
        refreshDaySummary()

        initialHomeBootstrapTask?.cancel()
        initialHomeBootstrapTask = Task { @MainActor in
            await loadDayLogs(skipCache: true)
            guard !Task.isCancelled else { return }
            refreshCurrentStreak()
            prefetchAdjacentDays(around: selectedSummaryDate)
        }
    }
}
