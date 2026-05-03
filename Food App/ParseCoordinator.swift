import Foundation
import Combine

@MainActor
final class ParseCoordinator: ObservableObject {
    @Published private(set) var snapshots: [UUID: ParseSnapshot] = [:]
    @Published private(set) var inFlight: Set<UUID> = []

    private struct CachedParseResponse {
        let response: ParseLogResponse
        let cachedAt: Date
    }

    private let responseCacheTTL: TimeInterval = 30 * 60
    private let responseCacheLimit = 50
    private var responseCache: [String: CachedParseResponse] = [:]
    private var responseCacheOrder: [String] = []

    private var apiClient: APIClient?
    private weak var saveCoordinator: SaveCoordinator?

    func configure(
        apiClient: APIClient,
        saveCoordinator: SaveCoordinator? = nil
    ) {
        self.apiClient = apiClient
        self.saveCoordinator = saveCoordinator
    }

    func markInFlight(rowID: UUID) {
        inFlight.insert(rowID)
    }

    func commit(snapshot: ParseSnapshot) {
        snapshots[snapshot.rowID] = snapshot
        inFlight.remove(snapshot.rowID)
    }

    func cachedResponse(rowID: UUID, text: String, loggedAt: String) -> ParseLogResponse? {
        pruneExpiredResponseCache()
        let key = responseCacheKey(rowID: rowID, text: text, loggedAt: loggedAt)
        guard let cached = responseCache[key] else { return nil }
        touchResponseCacheKey(key)
        return cached.response
    }

    func storeCachedResponse(_ response: ParseLogResponse, rowID: UUID, text: String, loggedAt: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pruneExpiredResponseCache()
        let key = responseCacheKey(rowID: rowID, text: text, loggedAt: loggedAt)
        responseCache[key] = CachedParseResponse(response: response, cachedAt: Date())
        touchResponseCacheKey(key)

        while responseCacheOrder.count > responseCacheLimit, let oldest = responseCacheOrder.first {
            responseCacheOrder.removeFirst()
            responseCache.removeValue(forKey: oldest)
        }
    }

    func markFailed(rowID: UUID) {
        inFlight.remove(rowID)
    }

    func cancelInFlight(rowID: UUID) {
        inFlight.remove(rowID)
    }

    func removeSnapshot(rowID: UUID) {
        snapshots.removeValue(forKey: rowID)
        inFlight.remove(rowID)
        removeCachedResponses(rowID: rowID)
    }

    func clearAll() {
        snapshots.removeAll()
        inFlight.removeAll()
        responseCache.removeAll()
        responseCacheOrder.removeAll()
    }

    func snapshotFor(rowID: UUID) -> ParseSnapshot? {
        snapshots[rowID]
    }

    private func responseCacheKey(rowID: UUID, text: String, loggedAt: String) -> String {
        let normalizedText = HomeLoggingTextMatch.normalizedRowText(text)
        return "\(rowID.uuidString.lowercased())|\(loggedAt)|\(normalizedText)"
    }

    private func touchResponseCacheKey(_ key: String) {
        responseCacheOrder.removeAll { $0 == key }
        responseCacheOrder.append(key)
    }

    private func pruneExpiredResponseCache() {
        let cutoff = Date().addingTimeInterval(-responseCacheTTL)
        let expiredKeys = responseCache
            .filter { $0.value.cachedAt < cutoff }
            .map(\.key)
        guard !expiredKeys.isEmpty else { return }
        let expired = Set(expiredKeys)
        responseCacheOrder.removeAll { expired.contains($0) }
        for key in expired {
            responseCache.removeValue(forKey: key)
        }
    }

    private func removeCachedResponses(rowID: UUID) {
        let prefix = "\(rowID.uuidString.lowercased())|"
        responseCacheOrder.removeAll { key in
            if key.hasPrefix(prefix) {
                responseCache.removeValue(forKey: key)
                return true
            }
            return false
        }
    }
}
