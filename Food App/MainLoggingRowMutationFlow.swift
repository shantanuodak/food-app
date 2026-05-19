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

    func handleSavedMealDidLog(_ notification: Notification) {
        guard let meal = notification.userInfo?["meal"] as? SavedMeal,
              let logId = notification.userInfo?["logId"] as? String,
              let loggedAt = notification.userInfo?["loggedAt"] as? String else {
            refreshNutritionStateForVisibleDay()
            return
        }

        let savedDay = (notification.userInfo?["savedDay"] as? String) ??
            HomeLoggingDateUtils.summaryDayString(fromLoggedAt: loggedAt)
        let optimisticEntry = HomeLoggingRowFactory.makeDayLogEntry(from: meal, logId: logId, loggedAt: loggedAt)
        invalidateDayCache(for: savedDay)

        if savedDay == summaryDateString {
            let existingLogs = dayLogs?.logs ?? []
            let mergedLogs = [optimisticEntry] + existingLogs.filter { $0.id != logId }
            let response = DayLogsResponse(
                date: savedDay,
                timezone: TimeZone.current.identifier,
                logs: mergedLogs
            )
            applyVisibleDayLogs(response)
        } else if let parsedDate = HomeLoggingDateUtils.summaryRequestFormatter.date(from: savedDay) {
            selectedSummaryDate = parsedDate
        }

        isSavedMealsPresented = false
        isProfilePresented = false
        saveSuccessMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            presentCelebration(title: "Logged", subtitle: meal.name, style: .logged)
        }

        Task { @MainActor in
            await refreshDayAfterMutation(savedDay, postNutritionNotification: false)
            appStore.recordTodayLogState(hasLogs: true)
            refreshCurrentStreak(shouldDetectBadgeUnlock: true)
            appStore.preloadProfileDashboard(force: true)
            appStore.preloadProgressCharts(force: true, includeHealthSamples: false)
        }
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
        if daySummary == nil, let cachedSummary = loadDaySummaryFromCache(date: dateString) {
            daySummary = cachedSummary
            daySummaryError = nil
            dayCacheSummary[dateString] = cachedSummary
        }
        guard dayLogs == nil,
              let cached = loadDayLogsFromCache(date: dateString),
              cached.date == dateString else { return }
        applyVisibleDayLogs(cached)
    }

    func applyVisibleDayLogs(_ response: DayLogsResponse) {
        dayLogs = response
        dayCacheLogs[response.date] = response
        syncInputRowsFromDayLogs(response.logs, for: response.date)
    }

    func showLoadingStateForUncachedDay(_ dateString: String) {
        dayLogs = DayLogsResponse(date: dateString, timezone: TimeZone.current.identifier, logs: [])
        daySummary = nil
        daySummaryError = nil
        inputRows = [.empty()]
    }

    func bootstrapAuthenticatedHomeIfNeeded() {
        guard appStore.isSessionRestored, !hasBootstrappedAuthenticatedHome else { return }
        hasBootstrappedAuthenticatedHome = true

        submitRestoredPendingSaveIfPossible()
        hydrateCurrentStreakFromCacheIfNeeded()
        refreshDaySummary()

        initialHomeBootstrapTask?.cancel()
        initialHomeBootstrapTask = Task { @MainActor in
            await loadDayLogs(skipCache: true)
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            refreshCurrentStreak()
            prefetchAdjacentDays(around: selectedSummaryDate)
        }
    }

    func scheduleSecondaryHomePreloads(force: Bool = false) {
        secondaryHomePreloadTask?.cancel()
        secondaryHomePreloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled, appStore.isSessionRestored else { return }
            appStore.preloadProfileDashboard(force: force)
            appStore.preloadProgressCharts(force: force, includeHealthSamples: false)
        }
    }

    func refreshVisibleDayOnForeground() {
        guard appStore.isSessionRestored else { return }
        refreshDaySummary()
        refreshDayLogs()
        scheduleSecondaryHomePreloads(force: true)
    }
}
