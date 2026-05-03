import Foundation

extension MainLoggingShellView {

    func clearPendingSaveContext() {
        pendingSaveRequest = nil
        pendingSaveFingerprint = nil
        pendingSaveIdempotencyKey = nil
    }

    func pendingQueueItem(for idempotencyKey: UUID) -> PendingSaveQueueItem? {
        let queueKey = idempotencyKey.uuidString.lowercased()
        return pendingSaveQueue.first { $0.idempotencyKey == queueKey }
    }

    func pendingQueueItem(forRowID rowID: UUID) -> PendingSaveQueueItem? {
        pendingSaveQueue.first { $0.rowID == rowID }
    }

    func containsPendingQueueItem(for idempotencyKey: UUID) -> Bool {
        pendingQueueItem(for: idempotencyKey) != nil
    }

    func resolveIdempotencyKey(forRowID rowID: UUID?) -> UUID {
        IdempotencyKeyResolver.resolve(
            rowID: rowID,
            queue: pendingSaveQueue
        )
    }

    var unresolvedPendingQueueItems: [PendingSaveQueueItem] {
        pendingSaveQueue.filter { $0.serverLogId == nil }
    }

    func firstUnresolvedPendingQueueItem() -> PendingSaveQueueItem? {
        unresolvedPendingQueueItems.first
    }

    func syncPendingQueueFromCoordinator(refreshRetryState: Bool = false) {
        pendingSaveQueue = saveCoordinator.pendingItems
        if refreshRetryState {
            refreshRetryStateFromPendingQueue()
        }
    }

    func upsertPendingSaveQueueItem(
        request: SaveLogRequest,
        fingerprint: String,
        idempotencyKey: UUID,
        rowID: UUID?,
        imageUploadData: Data? = nil,
        imagePreviewData: Data? = nil,
        imageMimeType: String? = nil,
        serverLogId: String? = nil
    ) {
        saveCoordinator.upsertPendingItem(
            request: request,
            fingerprint: fingerprint,
            idempotencyKey: idempotencyKey,
            rowID: rowID,
            imageUploadData: imageUploadData,
            imagePreviewData: imagePreviewData,
            imageMimeType: imageMimeType,
            serverLogId: serverLogId
        )
        syncPendingQueueFromCoordinator(refreshRetryState: true)
    }

    func refreshRetryStateFromPendingQueue() {
        if let context = saveCoordinator.retryContext() {
            pendingSaveRequest = context.request
            pendingSaveFingerprint = context.fingerprint
            pendingSaveIdempotencyKey = context.idempotencyKey
            return
        }

        guard let item = firstUnresolvedPendingQueueItem(),
              let key = UUID(uuidString: item.idempotencyKey) else {
            pendingSaveRequest = nil
            pendingSaveFingerprint = nil
            pendingSaveIdempotencyKey = nil
            return
        }

        pendingSaveRequest = item.request
        pendingSaveFingerprint = item.fingerprint
        pendingSaveIdempotencyKey = key
    }

    func markPendingSaveAttemptStarted(idempotencyKey: UUID) {
        saveCoordinator.markAttemptStarted(idempotencyKey: idempotencyKey)
        syncPendingQueueFromCoordinator()
    }

    func handlePendingSaveFailure(
        idempotencyKey: UUID,
        request: SaveLogRequest,
        error: Error,
        message: String
    ) async {
        let nonRetryable = saveCoordinator.handleFailure(
            idempotencyKey: idempotencyKey,
            message: message,
            error: error
        )
        syncPendingQueueFromCoordinator(refreshRetryState: true)

        if nonRetryable {
            let failedDay = HomeLoggingDateUtils.summaryDayString(
                fromLoggedAt: request.parsedLog.loggedAt,
                fallback: summaryDateString
            )
            await refreshDayAfterMutation(failedDay, postNutritionNotification: false)
        }
    }

    func markPendingSaveSucceeded(idempotencyKey: UUID, logId: String, preparedRequest: SaveLogRequest) {
        saveCoordinator.markSucceeded(
            idempotencyKey: idempotencyKey,
            logId: logId,
            preparedRequest: preparedRequest,
            fingerprint: saveRequestFingerprint(preparedRequest)
        )
        syncPendingQueueFromCoordinator(refreshRetryState: true)
    }

    func removePendingSave(idempotencyKey: String) {
        saveCoordinator.removePendingSave(idempotencyKey: idempotencyKey)
        syncPendingQueueFromCoordinator(refreshRetryState: true)
    }

    @discardableResult
    func removePendingSaveQueueItems(forRowID rowID: UUID) -> Set<String> {
        let removed = saveCoordinator.removePendingItems(forRowID: rowID)
        syncPendingQueueFromCoordinator(refreshRetryState: true)
        return removed
    }

    func reconcilePendingSaveQueue(with logs: [DayLogEntry], for dateString: String) {
        saveCoordinator.reconcilePendingQueue(with: logs, for: dateString)
        syncPendingQueueFromCoordinator(refreshRetryState: true)
    }

    func saveRequestFingerprint(_ request: SaveLogRequest) -> String {
        HomeLoggingSaveRequestUtils.fingerprint(request)
    }

    func userFriendlySaveError(_ error: Error) -> String {
        HomeLoggingErrorText.saveError(error)
    }

    func userFriendlyParseError(_ error: Error) -> String {
        HomeLoggingErrorText.parseError(error)
    }

    func userFriendlyEscalationError(_ error: Error) -> (message: String, blockCode: String?) {
        HomeLoggingErrorText.escalationError(error)
    }

    func handleAuthFailureIfNeeded(_ error: Error) {
        _ = appStore.handleAuthFailureIfNeeded(error)
    }

    func persistPendingSaveContext(
        rowID: UUID? = nil,
        imageUploadData: Data? = nil,
        imagePreviewData: Data? = nil,
        imageMimeType: String? = nil
    ) {
        guard let pendingSaveRequest, let pendingSaveFingerprint, let pendingSaveIdempotencyKey else {
            return
        }
        upsertPendingSaveQueueItem(
            request: pendingSaveRequest,
            fingerprint: pendingSaveFingerprint,
            idempotencyKey: pendingSaveIdempotencyKey,
            rowID: rowID,
            imageUploadData: imageUploadData,
            imagePreviewData: imagePreviewData,
            imageMimeType: imageMimeType
        )
    }

    func restorePendingSaveContextIfNeeded() {
        guard pendingSaveQueue.isEmpty else {
            return
        }
        let restored = saveCoordinator.loadRecoverableQueue(
            isRecoverable: isRecoverablePendingSaveItem
        )
        pendingSaveQueue = restored.queue
        refreshRetryStateFromPendingQueue()
    }

    func submitRestoredPendingSaveIfPossible() {
        guard appStore.isNetworkReachable, !isSaving, !isSubmittingRestoredPendingSaves else { return }

        Task { @MainActor in
            isSubmittingRestoredPendingSaves = true
            defer { isSubmittingRestoredPendingSaves = false }

            let report = await saveCoordinator.flushAll(reason: .startup) { candidate in
                await submitSave(
                    request: candidate.item.request,
                    idempotencyKey: candidate.idempotencyKey,
                    isRetry: true,
                    intent: .auto
                ).didSucceed
            }
            syncPendingQueueFromCoordinator()
            guard report.attempted > 0 else { return }
        }
    }

    func isRecoverablePendingSaveItem(_ item: PendingSaveQueueItem) -> Bool {
        HomeLoggingSaveRequestUtils.isRecoverablePendingSaveItem(item)
    }

    func saveDraftPreviewJSON() -> String {
        guard let request = buildSaveDraftRequest() else {
            return "{}"
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(request), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
