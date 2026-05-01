import Foundation

enum SaveAttemptOutcome: String {
    case attempted
    case succeeded
    case failed
    case skippedNoEligibleState
    case skippedDuplicate
}

enum SaveAttemptSource: String {
    case auto
    case manual
    case retry
    case patch
}

struct SaveAttemptEvent {
    let parseRequestId: String
    let rowID: UUID
    let outcome: SaveAttemptOutcome
    let errorCode: String?
    let latencyMs: Int?
    let source: SaveAttemptSource
    let clientBuild: String
    let backendCommit: String?
    let timestamp: Date
}

final class SaveAttemptTelemetry {
    static let shared = SaveAttemptTelemetry()

    private init() {}

    private lazy var isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func emit(
        parseRequestId: String,
        rowID: UUID,
        outcome: SaveAttemptOutcome,
        errorCode: String?,
        latencyMs: Int?,
        source: SaveAttemptSource,
        backendCommit: String? = nil,
        timestamp: Date = Date()
    ) {
        let clientBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let event = SaveAttemptEvent(
            parseRequestId: parseRequestId,
            rowID: rowID,
            outcome: outcome,
            errorCode: errorCode,
            latencyMs: latencyMs,
            source: source,
            clientBuild: clientBuild,
            backendCommit: backendCommit,
            timestamp: timestamp
        )

        var payload: [String: Any] = [
            "parseRequestId": event.parseRequestId,
            "rowID": event.rowID.uuidString.lowercased(),
            "outcome": event.outcome.rawValue,
            "source": event.source.rawValue,
            "clientBuild": event.clientBuild,
            "timestamp": isoFormatter.string(from: event.timestamp)
        ]

        if let errorCode = event.errorCode, !errorCode.isEmpty {
            payload["errorCode"] = errorCode
        }
        if let latencyMs {
            payload["latencyMs"] = latencyMs
        }
        if let backendCommit, !backendCommit.isEmpty {
            payload["backendCommit"] = backendCommit
        }

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            NSLog("[save_attempt] \(json)")
            return
        }

        NSLog(
            "[save_attempt] parseRequestId=%@ rowID=%@ outcome=%@ source=%@",
            event.parseRequestId,
            event.rowID.uuidString.lowercased(),
            event.outcome.rawValue,
            event.source.rawValue
        )
    }
}

