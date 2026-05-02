import Foundation
import Combine

struct PendingRetryContext {
    let request: SaveLogRequest
    let fingerprint: String
    let idempotencyKey: UUID
}

struct PendingSubmissionCandidate {
    let item: PendingSaveQueueItem
    let idempotencyKey: UUID
}

enum SaveFlushReason: String {
    case startup
    case authRestored
    case networkRestored
    case manualRetry
}

struct SaveFlushReport {
    let reason: SaveFlushReason
    let attempted: Int
    let succeeded: Int
    let failed: Int
}

enum SaveCoordinatorError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "SaveCoordinator is not configured."
        }
    }
}

struct SaveExecutionSuccess {
    let preparedRequest: SaveLogRequest
    let response: SaveLogResponse
}

struct SaveExecutionFailure {
    let effectiveRequest: SaveLogRequest
    let error: Error
}

enum SaveExecutionResult {
    case success(SaveExecutionSuccess)
    case failure(SaveExecutionFailure)
}

protocol PendingSavePersistence {
    func loadQueue() -> [PendingSaveQueueItem]
    func saveQueue(_ items: [PendingSaveQueueItem])
    func clear()
}

struct HomePendingSavePersistence: PendingSavePersistence {
    let defaults: UserDefaults

    func loadQueue() -> [PendingSaveQueueItem] {
        HomePendingSaveStore.loadQueue(defaults: defaults)
    }

    func saveQueue(_ items: [PendingSaveQueueItem]) {
        HomePendingSaveStore.saveQueue(items, defaults: defaults)
    }

    func clear() {
        HomePendingSaveStore.clear(defaults: defaults)
    }
}

@MainActor
final class SaveCoordinator: ObservableObject {
    @Published private(set) var pendingItems: [PendingSaveQueueItem] = []
    @Published private(set) var lastError: String?

    private var apiClient: APIClient?
    private var imageStorageService: ImageStorageService?
    private var deferredImageUploadStore: DeferredImageUploadStore?
    private var telemetry: SaveAttemptTelemetry = .shared
    private var persistence: PendingSavePersistence?
    private var isConfigured = false

    func configure(
        apiClient: APIClient,
        imageStorageService: ImageStorageService,
        deferredImageUploadStore: DeferredImageUploadStore?,
        persistence: PendingSavePersistence,
        telemetry: SaveAttemptTelemetry? = nil
    ) {
        self.apiClient = apiClient
        self.imageStorageService = imageStorageService
        self.deferredImageUploadStore = deferredImageUploadStore
        self.persistence = persistence
        self.telemetry = telemetry ?? .shared
        isConfigured = true
    }

    func loadQueue() -> [PendingSaveQueueItem] {
        guard let persistence else { return pendingItems }
        let loaded = persistence.loadQueue()
        pendingItems = loaded
        return loaded
    }

    func loadRecoverableQueue(
        isRecoverable: (PendingSaveQueueItem) -> Bool
    ) -> (queue: [PendingSaveQueueItem], droppedCount: Int) {
        let loaded = loadQueue()
        let filtered = loaded.filter(isRecoverable)
        let droppedCount = loaded.count - filtered.count
        if droppedCount > 0 {
            pendingItems = filtered
            persistence?.saveQueue(filtered)
        } else {
            pendingItems = loaded
        }
        return (pendingItems, droppedCount)
    }

    func persistQueue(_ items: [PendingSaveQueueItem]) {
        pendingItems = items
        persistence?.saveQueue(items)
    }

    func setPendingItems(_ items: [PendingSaveQueueItem], persist: Bool) {
        pendingItems = items
        if persist {
            persistence?.saveQueue(items)
        }
    }

    func upsertPendingItem(
        request: SaveLogRequest,
        fingerprint: String,
        idempotencyKey: UUID,
        rowID: UUID?,
        imageUploadData: Data?,
        imagePreviewData: Data?,
        imageMimeType: String?,
        serverLogId: String?
    ) {
        let key = idempotencyKey.uuidString.lowercased()
        let dateString = String(request.parsedLog.loggedAt.prefix(10))
        let existingIndex = pendingItems.firstIndex { item in
            item.idempotencyKey == key || (rowID != nil && item.rowID == rowID && item.serverLogId == nil)
        }
        let existing = existingIndex.map { pendingItems[$0] }
        let item = PendingSaveQueueItem(
            id: existing?.id ?? UUID(),
            rowID: rowID ?? existing?.rowID,
            request: request,
            fingerprint: fingerprint,
            idempotencyKey: key,
            dateString: dateString,
            createdAt: existing?.createdAt ?? Date(),
            imageUploadData: imageUploadData ?? existing?.imageUploadData,
            imagePreviewData: imagePreviewData ?? existing?.imagePreviewData,
            imageMimeType: imageMimeType ?? existing?.imageMimeType,
            serverLogId: serverLogId ?? existing?.serverLogId
        )

        if let existingIndex {
            pendingItems[existingIndex] = item
        } else {
            pendingItems.append(item)
        }
        persistence?.saveQueue(pendingItems)
    }

    func removePendingSave(idempotencyKey: String) {
        pendingItems.removeAll { $0.idempotencyKey == idempotencyKey }
        persistence?.saveQueue(pendingItems)
    }

    func retryContext() -> PendingRetryContext? {
        guard let item = pendingItems.first(where: { $0.serverLogId == nil }),
              let key = UUID(uuidString: item.idempotencyKey) else {
            return nil
        }
        return PendingRetryContext(
            request: item.request,
            fingerprint: item.fingerprint,
            idempotencyKey: key
        )
    }

    func pendingSubmissionCandidates() -> (valid: [PendingSubmissionCandidate], invalidIdempotencyKeys: [String]) {
        var valid: [PendingSubmissionCandidate] = []
        var invalidKeys: [String] = []

        for item in pendingItems where item.serverLogId == nil {
            guard let key = UUID(uuidString: item.idempotencyKey) else {
                invalidKeys.append(item.idempotencyKey)
                continue
            }
            valid.append(PendingSubmissionCandidate(item: item, idempotencyKey: key))
        }

        return (valid, invalidKeys)
    }

    func consumeSubmissionCandidates() -> [PendingSubmissionCandidate] {
        let candidates = pendingSubmissionCandidates()
        if !candidates.invalidIdempotencyKeys.isEmpty {
            let badKeys = Set(candidates.invalidIdempotencyKeys)
            pendingItems.removeAll { badKeys.contains($0.idempotencyKey) }
            persistence?.saveQueue(pendingItems)
        }
        return candidates.valid
    }

    func flushAll(
        reason: SaveFlushReason,
        submit: @MainActor (PendingSubmissionCandidate) async -> Bool
    ) async -> SaveFlushReport {
        let candidates = consumeSubmissionCandidates()
        var succeeded = 0
        var failed = 0

        for candidate in candidates {
            let didSucceed = await submit(candidate)
            if didSucceed {
                succeeded += 1
            } else {
                failed += 1
            }
        }

        return SaveFlushReport(
            reason: reason,
            attempted: candidates.count,
            succeeded: succeeded,
            failed: failed
        )
    }

    func handleAuthRestored(
        submit: @MainActor (PendingSubmissionCandidate) async -> Bool
    ) async -> SaveFlushReport {
        await flushAll(reason: .authRestored, submit: submit)
    }

    func handleFailure(idempotencyKey: UUID, message: String, nonRetryable: Bool) {
        if nonRetryable {
            removePendingSave(idempotencyKey: idempotencyKey.uuidString.lowercased())
            return
        }
        markFailed(idempotencyKey: idempotencyKey, message: message)
    }

    @discardableResult
    func handleFailure(idempotencyKey: UUID, message: String, error: Error) -> Bool {
        let nonRetryable = SaveErrorPolicy.isNonRetryable(error)
        handleFailure(
            idempotencyKey: idempotencyKey,
            message: message,
            nonRetryable: nonRetryable
        )
        return nonRetryable
    }

    func markAttemptStarted(idempotencyKey: UUID) {
        let key = idempotencyKey.uuidString.lowercased()
        guard let index = pendingItems.firstIndex(where: { $0.idempotencyKey == key }) else {
            return
        }

        pendingItems[index].attemptCount = (pendingItems[index].attemptCount ?? 0) + 1
        pendingItems[index].lastAttemptAt = Date()
        pendingItems[index].lastErrorMessage = nil
        persistence?.saveQueue(pendingItems)
    }

    func markFailed(idempotencyKey: UUID, message: String) {
        let key = idempotencyKey.uuidString.lowercased()
        guard let index = pendingItems.firstIndex(where: { $0.idempotencyKey == key }) else {
            return
        }

        pendingItems[index].lastAttemptAt = Date()
        pendingItems[index].lastErrorMessage = message
        persistence?.saveQueue(pendingItems)
    }

    func markSucceeded(idempotencyKey: UUID, logId: String, preparedRequest: SaveLogRequest, fingerprint: String) {
        let key = idempotencyKey.uuidString.lowercased()
        guard let index = pendingItems.firstIndex(where: { $0.idempotencyKey == key }) else {
            return
        }

        pendingItems[index].request = preparedRequest
        pendingItems[index].fingerprint = fingerprint
        pendingItems[index].serverLogId = logId
        pendingItems[index].lastErrorMessage = nil
        persistence?.saveQueue(pendingItems)
    }

    @discardableResult
    func removePendingItems(forRowID rowID: UUID) -> Set<String> {
        let removedKeys = Set(
            pendingItems
                .filter { $0.rowID == rowID }
                .map(\.idempotencyKey)
        )
        guard !removedKeys.isEmpty else { return [] }
        pendingItems.removeAll { $0.rowID == rowID }
        persistence?.saveQueue(pendingItems)
        return removedKeys
    }

    func reconcilePendingQueue(with logs: [DayLogEntry], for dateString: String) {
        let serverLogIds = Set(logs.map(\.id))
        let beforeCount = pendingItems.count
        pendingItems.removeAll { item in
            guard item.dateString == dateString else { return false }
            if item.serverLogId.map({ serverLogIds.contains($0) }) == true {
                return true
            }
            return logs.contains { log in
                Self.pendingItem(item, matchesServerLog: log)
            }
        }
        if pendingItems.count != beforeCount {
            persistence?.saveQueue(pendingItems)
        }
    }

    private static func pendingItem(_ item: PendingSaveQueueItem, matchesServerLog log: DayLogEntry) -> Bool {
        let pending = item.request.parsedLog
        guard normalize(pending.rawText) == normalize(log.rawText) else { return false }
        guard normalizedInputKind(pending.inputKind) == normalizedInputKind(log.inputKind) else { return false }
        guard pending.loggedAt == log.loggedAt else { return false }
        return abs(pending.totals.calories - log.totals.calories) <= 0.5
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func normalizedInputKind(_ value: String?) -> String {
        let kind = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return kind.isEmpty ? "text" : kind
    }

    func executeSave(
        request: SaveLogRequest,
        idempotencyKey: UUID,
        prepareForNetwork: @MainActor (SaveLogRequest, UUID) async throws -> SaveLogRequest
    ) async throws -> SaveExecutionSuccess {
        guard let apiClient else { throw SaveCoordinatorError.notConfigured }
        let preparedRequest = try await prepareForNetwork(request, idempotencyKey)
        let response = try await apiClient.saveLog(preparedRequest, idempotencyKey: idempotencyKey)
        return SaveExecutionSuccess(preparedRequest: preparedRequest, response: response)
    }

    func executeSaveResult(
        request: SaveLogRequest,
        idempotencyKey: UUID,
        prepareForNetwork: @MainActor (SaveLogRequest, UUID) async throws -> SaveLogRequest
    ) async -> SaveExecutionResult {
        guard let apiClient else {
            return .failure(
                SaveExecutionFailure(
                    effectiveRequest: request,
                    error: SaveCoordinatorError.notConfigured
                )
            )
        }

        var effectiveRequest = request
        do {
            effectiveRequest = try await prepareForNetwork(request, idempotencyKey)
            let response = try await apiClient.saveLog(effectiveRequest, idempotencyKey: idempotencyKey)
            return .success(
                SaveExecutionSuccess(
                    preparedRequest: effectiveRequest,
                    response: response
                )
            )
        } catch {
            return .failure(
                SaveExecutionFailure(
                    effectiveRequest: effectiveRequest,
                    error: error
                )
            )
        }
    }

    func deleteLog(id: String) async throws {
        guard let apiClient else { throw SaveCoordinatorError.notConfigured }
        _ = try await apiClient.deleteLog(id: id)
    }

    func scheduleDeferredImageUploadRetry(
        logId: String,
        imageData: Data,
        normalizedInputKind: String,
        userIDHint: String?
    ) {
        guard normalizedInputKind == "image" else { return }
        guard let imageStorageService, let apiClient else { return }
        let store = deferredImageUploadStore

        Task.detached(priority: .background) {
            await store?.enqueue(logId: logId, imageData: imageData)
            do {
                let imageRef = try await imageStorageService.uploadJPEG(imageData, userIdentifierHint: userIDHint)
                _ = try await apiClient.updateLogImageRef(id: logId, imageRef: imageRef)
                await store?.remove(logId: logId)
                NSLog("[SaveCoordinator] Deferred image upload succeeded for log \(logId)")
            } catch {
                NSLog("[SaveCoordinator] Deferred image upload failed for log \(logId); persisted for next launch: \(error)")
            }
        }
    }

}
