import Foundation
import Combine

@MainActor
final class ParseCoordinator: ObservableObject {
    @Published private(set) var snapshots: [UUID: ParseSnapshot] = [:]
    @Published private(set) var inFlight: Set<UUID> = []

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

    func markFailed(rowID: UUID) {
        inFlight.remove(rowID)
    }

    func cancelInFlight(rowID: UUID) {
        inFlight.remove(rowID)
    }

    func removeSnapshot(rowID: UUID) {
        snapshots.removeValue(forKey: rowID)
        inFlight.remove(rowID)
    }

    func clearAll() {
        snapshots.removeAll()
        inFlight.removeAll()
    }

    func snapshotFor(rowID: UUID) -> ParseSnapshot? {
        snapshots[rowID]
    }
}
