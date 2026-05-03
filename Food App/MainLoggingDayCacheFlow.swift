import Foundation

extension MainLoggingShellView {
    func refreshDaySummary() {
        // Stale-while-revalidate: paint any cached summary instantly, THEN
        // always hit the network so stale cache (e.g. from a prior save whose
        // reload failed silently, or entries made in another session) gets
        // corrected. Previously this function never hit the network if the
        // cache was populated — leaving users with stale totals.
        Task {
            let dateToLoad = summaryDateString
            if let cached = dayCacheSummary[dateToLoad] {
                daySummary = cached
                daySummaryError = nil
            }
            await loadDaySummary(skipCache: true)
        }
    }

    func refreshDayLogs() {
        // Stale-while-revalidate: same rationale as refreshDaySummary. Paint
        // any cached logs instantly, then always hit the network so rows
        // saved on another device — or any save whose post-reload failed —
        // become visible.
        Task {
            let dateToLoad = summaryDateString
            if let cached = dayCacheLogs[dateToLoad], cached.date == dateToLoad {
                dayLogs = cached
                syncInputRowsFromDayLogs(cached.logs, for: cached.date)
            }
            await loadDayLogs(skipCache: true)
        }
    }

    func refreshCurrentStreak() {
        guard appStore.configuration.progressFeatureEnabled else {
            currentFoodLogStreak = nil
            return
        }

        Task { @MainActor in
            isLoadingFoodLogStreak = true
            defer { isLoadingFoodLogStreak = false }

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let formatter = HomeLoggingDateUtils.summaryRequestFormatter
            do {
                let response = try await appStore.apiClient.getStreaks(
                    range: 30,
                    to: formatter.string(from: today),
                    timezone: TimeZone.current.identifier
                )
                currentFoodLogStreak = response.currentDays
            } catch {
                handleAuthFailureIfNeeded(error)
            }
        }
    }

    func loadDayLogs(forcedDate: String? = nil, isRetry: Bool = false, skipCache: Bool = false) async {
        let dateToLoad = forcedDate ?? summaryDateString

        // Serve from cache only if the date still matches what the user is viewing.
        // This prevents stale cache from a prefetch or a race condition from showing
        // wrong data.
        if !skipCache, let cached = dayCacheLogs[dateToLoad], cached.date == dateToLoad {
            // Double-check the user hasn't swiped to a different day while we were loading
            guard summaryDateString == dateToLoad || forcedDate != nil else { return }
            dayLogs = cached
            syncInputRowsFromDayLogs(cached.logs, for: cached.date)
            return
        }

        isLoadingDayLogs = true
        defer { isLoadingDayLogs = false }

        guard appStore.isNetworkReachable else { return }

        do {
            let response = try await appStore.apiClient.getDayLogs(date: dateToLoad)

            // Validate the response is for the date we requested
            guard response.date == dateToLoad else {
#if DEBUG
                print("[loadDayLogs] date mismatch: requested=\(dateToLoad) got=\(response.date) — discarding")
#endif
                return
            }
            // Verify user is still viewing this date (they may have swiped during the network call)
            guard summaryDateString == dateToLoad || forcedDate != nil else {
                // Still cache it for when they come back
                dayCacheLogs[dateToLoad] = response
                persistDayLogsToCache(response, date: dateToLoad)
                return
            }

            dayLogs = response
            dayCacheLogs[dateToLoad] = response
            persistDayLogsToCache(response, date: dateToLoad)
            syncInputRowsFromDayLogs(response.logs, for: response.date)
        } catch is CancellationError {
            // ignore
        } catch {
            handleAuthFailureIfNeeded(error)
            if !isRetry && isTransientLoadError(error) {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await loadDayLogs(forcedDate: forcedDate, isRetry: true, skipCache: skipCache)
            }
        }
    }

    // MARK: - Day Logs Disk Cache

    func persistDayLogsToCache(_ response: DayLogsResponse, date: String) {
        HomeDayLogsDiskCache.persist(response, date: date, defaults: defaults)
    }

    func loadDayLogsFromCache(date: String) -> DayLogsResponse? {
        HomeDayLogsDiskCache.load(date: date, defaults: defaults)
    }

    func removeDayLogsCacheEntry(date: String) {
        HomeDayLogsDiskCache.remove(date: date, defaults: defaults)
    }

    func pendingRowsForDate(_ dateString: String, excluding serverEntries: [DayLogEntry]) -> [HomeLogRow] {
        let serverLogIds = Set(serverEntries.map(\.id))
        return pendingSaveQueue
            .filter { item in
                guard item.dateString == dateString else { return false }
                if item.serverLogId.map({ serverLogIds.contains($0) }) == true {
                    return false
                }
                return !serverEntries.contains { HomeLoggingRowFactory.pendingSaveItem(item, matchesServerLog: $0) }
            }
            .sorted { $0.createdAt < $1.createdAt }
            .map(HomeLoggingRowFactory.makePendingSaveRow)
    }

    func preservedDraftRowsForDate(
        _ dateString: String,
        pendingRows: [HomeLogRow],
        activeRows: [HomeLogRow]
    ) -> [HomeLogRow] {
        guard let preservedRows = preservedDraftRowsByDate[dateString], !preservedRows.isEmpty else {
            return []
        }

        let pendingRowIDs = Set(pendingRows.map(\.id))
        let activeRowIDs = Set(activeRows.map(\.id))

        return preservedRows.compactMap { preserved in
            var row = preserved.row
            let normalizedText = HomeLoggingTextMatch.normalizedRowText(row.text)
            guard !normalizedText.isEmpty else { return nil }
            guard !pendingRowIDs.contains(row.id) else { return nil }
            guard !activeRowIDs.contains(row.id) else { return nil }

            if preserved.isBackgroundManaged,
               row.calories == nil,
               row.parsedItem == nil,
               row.parsedItems.isEmpty {
                row.normalizedTextAtParse = normalizedText
            }

            row.clearParsePhase()
            return row
        }
    }

    func removePreservedDateDraft(rowID: UUID, for dateString: String) {
        guard var preservedRows = preservedDraftRowsByDate[dateString] else { return }
        preservedRows.removeAll { $0.row.id == rowID }
        if preservedRows.isEmpty {
            preservedDraftRowsByDate.removeValue(forKey: dateString)
        } else {
            preservedDraftRowsByDate[dateString] = preservedRows
        }
    }

    func markPreservedDateDraftNeedsParse(rowID: UUID, loggedAt: String) {
        let dateString = HomeLoggingDateUtils.summaryDayString(fromLoggedAt: loggedAt, fallback: summaryDateString)
        guard var preservedRows = preservedDraftRowsByDate[dateString],
              let preservedIndex = preservedRows.firstIndex(where: { $0.row.id == rowID }) else {
            return
        }

        preservedRows[preservedIndex].isBackgroundManaged = false
        preservedRows[preservedIndex].row.normalizedTextAtParse = nil
        preservedDraftRowsByDate[dateString] = preservedRows

        guard summaryDateString == dateString,
              let rowIndex = inputRows.firstIndex(where: { $0.id == rowID }) else {
            return
        }

        inputRows[rowIndex].normalizedTextAtParse = nil
        inputRows[rowIndex].clearParsePhase()
        scheduleDebouncedParse(for: noteText)
    }

    func syncInputRowsFromDayLogs(_ entries: [DayLogEntry], for dateString: String) {
        reconcilePendingSaveQueue(with: entries, for: dateString)
        let currentActiveRows = inputRows.filter { !$0.isSaved }
        let shouldKeepActiveRows = draftDayString() == dateString || (draftLoggedAt == nil && dateString == summaryDateString)
        let activeServerLogIds = shouldKeepActiveRows
            ? Set(currentActiveRows.compactMap(\.serverLogId))
            : []
        let currentSavedRowOrder: [String: Int] = Dictionary(
            uniqueKeysWithValues: inputRows.enumerated().compactMap { index, row in
                row.serverLogId.map { ($0, index) }
            }
        )
        let savedRows: [HomeLogRow] = entries
            .filter { !activeServerLogIds.contains($0.id) }
            .map(HomeLoggingRowFactory.makeSavedRow)
        let orderedSavedRows = savedRows.enumerated()
            .sorted { lhs, rhs in
                let lhsOrder = lhs.element.serverLogId.flatMap { currentSavedRowOrder[$0] }
                let rhsOrder = rhs.element.serverLogId.flatMap { currentSavedRowOrder[$0] }

                switch (lhsOrder, rhsOrder) {
                case let (lhs?, rhs?):
                    return lhs < rhs
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)

        // Merge server state into the existing visible order. This keeps rows from
        // jumping during optimistic save -> stale cache -> fresh server refresh cycles.
        let pendingRows = pendingRowsForDate(dateString, excluding: entries)
        let pendingRowIDs = Set(pendingRows.map(\.id))
        let activeRows: [HomeLogRow]
        if shouldKeepActiveRows {
            activeRows = currentActiveRows.filter { !pendingRowIDs.contains($0.id) }
        } else {
            activeRows = []
        }
        let preservedRows = preservedDraftRowsForDate(
            dateString,
            pendingRows: pendingRows,
            activeRows: activeRows
        )
        let nextRows = mergeRowsPreservingVisibleOrder(
            currentRows: inputRows,
            candidateRows: orderedSavedRows + pendingRows + preservedRows + activeRows
        )
        if inputRowsSyncSignature(inputRows) != inputRowsSyncSignature(nextRows) {
            inputRows = nextRows
        }

        // Ensure there's always at least one empty active row for input
        if inputRows.allSatisfy({ $0.isSaved }) {
            inputRows.append(.empty())
        }
    }

    func inputRowsSyncSignature(_ rows: [HomeLogRow]) -> String {
        rows.map { row in
            [
                row.id.uuidString,
                row.serverLogId ?? "",
                HomeLoggingTextMatch.normalizedRowText(row.text),
                row.calories.map(String.init) ?? "",
                row.isSaved ? "saved" : "draft"
            ].joined(separator: "|")
        }
        .joined(separator: "\n")
    }

    func mergeRowsPreservingVisibleOrder(
        currentRows: [HomeLogRow],
        candidateRows: [HomeLogRow]
    ) -> [HomeLogRow] {
        var remainingByServerLogId: [String: HomeLogRow] = [:]
        var remainingByRowId: [UUID: HomeLogRow] = [:]
        var candidateOrder: [String] = []

        for row in candidateRows {
            if let serverLogId = row.serverLogId {
                let key = "server:\(serverLogId)"
                if remainingByServerLogId[serverLogId] == nil {
                    candidateOrder.append(key)
                }
                remainingByServerLogId[serverLogId] = row
            } else {
                let key = "row:\(row.id.uuidString)"
                if remainingByRowId[row.id] == nil {
                    candidateOrder.append(key)
                }
                remainingByRowId[row.id] = row
            }
        }

        var output: [HomeLogRow] = []
        var usedKeys = Set<String>()

        func appendIfUnused(_ row: HomeLogRow) {
            let key = row.serverLogId.map { "server:\($0)" } ?? "row:\(row.id.uuidString)"
            guard !usedKeys.contains(key) else { return }
            output.append(row)
            usedKeys.insert(key)
        }

        for current in currentRows {
            if let serverLogId = current.serverLogId,
               let replacement = remainingByServerLogId.removeValue(forKey: serverLogId) {
                appendIfUnused(replacement)
                continue
            }

            if let replacement = remainingByRowId.removeValue(forKey: current.id) {
                appendIfUnused(replacement)
            }
        }

        for key in candidateOrder where !usedKeys.contains(key) {
            if key.hasPrefix("server:") {
                let serverLogId = String(key.dropFirst("server:".count))
                if let row = remainingByServerLogId.removeValue(forKey: serverLogId) {
                    appendIfUnused(row)
                }
            } else if key.hasPrefix("row:") {
                let rowIDText = String(key.dropFirst("row:".count))
                if let rowID = UUID(uuidString: rowIDText),
                   let row = remainingByRowId.removeValue(forKey: rowID) {
                    appendIfUnused(row)
                }
            }
        }

        return output
    }

    func loadDaySummary(forcedDate: String? = nil, isRetry: Bool = false, skipCache: Bool = false) async {
        let dateToLoad = forcedDate ?? summaryDateString

        // Serve from cache if available — instant, no loading spinner
        if !skipCache, let cached = dayCacheSummary[dateToLoad] {
            daySummary = cached
            daySummaryError = nil
            return
        }

        isLoadingDaySummary = true
        daySummaryError = nil
        defer { isLoadingDaySummary = false }

        guard appStore.isNetworkReachable else {
            daySummaryError = L10n.noNetworkSummary
            return
        }

        do {
            let response = try await appStore.apiClient.getDaySummary(date: dateToLoad)
            daySummary = response
            daySummaryError = nil
            dayCacheSummary[dateToLoad] = response
        } catch {
            handleAuthFailureIfNeeded(error)

            if !isRetry && isTransientLoadError(error) {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await loadDaySummary(forcedDate: forcedDate, isRetry: true, skipCache: skipCache)
                return
            }

            daySummaryError = userFriendlyDaySummaryError(error)
            if daySummary?.date != dateToLoad {
                daySummary = nil
            }
        }
    }

    /// Silently prefetch the previous 10 days in the background so swiping is instant.
    /// Runs with low priority and doesn't show loading indicators or errors.
    func prefetchAdjacentDays(around date: Date, count: Int = 15) {
        prefetchTask?.cancel()
        prefetchTask = Task(priority: .utility) {
            let calendar = Calendar.current
            let formatter = HomeLoggingDateUtils.summaryRequestFormatter

            // Check if any days in the range need fetching
            var needsFetch = false
            for offset in 1...count {
                let pastDate = calendar.date(byAdding: .day, value: -offset, to: date) ?? date
                let dateStr = formatter.string(from: pastDate)
                if dayCacheSummary[dateStr] == nil || dayCacheLogs[dateStr] == nil {
                    needsFetch = true
                    break
                }
            }
            guard needsFetch, !Task.isCancelled else { return }

            // Batch fetch: single request for the entire range
            let toDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            let fromDate = calendar.date(byAdding: .day, value: -count, to: date) ?? date
            let toStr = formatter.string(from: toDate)
            let fromStr = formatter.string(from: fromDate)

            guard !Task.isCancelled else { return }

            do {
                let range = try await appStore.apiClient.getDayRange(from: fromStr, to: toStr)
                guard !Task.isCancelled else { return }
                for summary in range.summaries {
                    dayCacheSummary[summary.date] = summary
                }
                for logs in range.logs {
                    dayCacheLogs[logs.date] = logs
                    persistDayLogsToCache(logs, date: logs.date)
                }
            } catch {
                // Fallback: fetch individually if batch fails
                for offset in 1...count {
                    guard !Task.isCancelled else { return }
                    let pastDate = calendar.date(byAdding: .day, value: -offset, to: date) ?? date
                    let dateStr = formatter.string(from: pastDate)
                    guard dayCacheSummary[dateStr] == nil || dayCacheLogs[dateStr] == nil else { continue }

                    async let summaryResult = try? appStore.apiClient.getDaySummary(date: dateStr)
                    async let logsResult = try? appStore.apiClient.getDayLogs(date: dateStr)
                    if let summary = await summaryResult { dayCacheSummary[dateStr] = summary }
                    if let logs = await logsResult {
                        dayCacheLogs[dateStr] = logs
                        persistDayLogsToCache(logs, date: dateStr)
                    }
                }
            }
        }
    }

    /// Invalidate cache for a specific date (e.g. after saving a new log entry).
    func invalidateDayCache(for dateString: String) {
        dayCacheSummary.removeValue(forKey: dateString)
        dayCacheLogs.removeValue(forKey: dateString)
        removeDayLogsCacheEntry(date: dateString)
    }

    /// Returns true for errors that are transient and worth retrying automatically.
    func isTransientLoadError(_ error: Error) -> Bool {
        if let apiErr = error as? APIClientError, case .networkFailure = apiErr {
            return true
        }
        let nsErr = error as NSError
        let transientCodes: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorCannotConnectToHost
        ]
        return nsErr.domain == NSURLErrorDomain && transientCodes.contains(nsErr.code)
    }

    var summaryDateString: String {
        HomeLoggingDateUtils.summaryRequestFormatter.string(from: selectedSummaryDate)
    }

    func userFriendlyDaySummaryError(_ error: Error) -> String {
        HomeLoggingErrorText.daySummaryError(error)
    }
}
