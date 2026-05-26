import Foundation
import UIKit

enum TelemetryOutcome: String, Codable {
    case success
    case failure
}

enum TelemetryValue: Encodable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        }
    }
}

struct TelemetryEvent: Encodable {
    let eventName: String
    let feature: String
    let outcome: TelemetryOutcome
    let durationMs: Double
    let timestamp: String
    let environment: String
    let backendRequestId: String?
    let backendErrorCode: String?
    let httpStatusCode: Int?
    let parseRequestId: String?
    let parseVersion: String?
    let details: [String: TelemetryValue]
}

final class TelemetryClient {
    static let shared = TelemetryClient()

    private let encoder: JSONEncoder
    private let isoFormatter: ISO8601DateFormatter

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func emit(_ event: TelemetryEvent) {
        guard let data = try? encoder.encode(event),
              let json = String(data: data, encoding: .utf8) else {
#if DEBUG
            print("[telemetry] failed_to_encode_event eventName=\(event.eventName)")
#endif
            return
        }
#if DEBUG
        print("[telemetry] \(json)")
#endif
    }

    func nowISO8601() -> String {
        isoFormatter.string(from: Date())
    }
}

private struct QueuedAuthDiagnosticEvent: Codable {
    let clientEventId: String
    let eventName: String
    let occurredAt: String
    let appLaunchId: String
    let clientBuild: String?
    let appVersion: String?
    let osVersion: String?
    let deviceModel: String?
    let provider: String?
    let userIdHint: String?
    let metadata: [String: String]

    func requestPayload() -> AuthDiagnosticEventRequest {
        AuthDiagnosticEventRequest(
            clientEventId: clientEventId,
            eventName: eventName,
            occurredAt: occurredAt,
            appLaunchId: appLaunchId,
            clientBuild: clientBuild,
            appVersion: appVersion,
            osVersion: osVersion,
            deviceModel: deviceModel,
            provider: provider,
            userIdHint: userIdHint,
            metadata: metadata
        )
    }
}

final class AuthDiagnosticTelemetry {
    static let shared = AuthDiagnosticTelemetry()

    let appLaunchId = UUID().uuidString.lowercased()

    private let queueKey = "app.auth.diagnostic.events.v1"
    private let maxQueuedEvents = 80
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let isoFormatter: ISO8601DateFormatter
    private let lock = NSLock()
    private var isFlushing = false

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func emit(
        eventName: String,
        session: AuthSession?,
        details: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        emit(
            eventName: eventName,
            userIdHint: session?.userID,
            provider: session?.provider,
            details: details,
            timestamp: timestamp
        )
    }

    func emit(
        eventName: String,
        userIdHint: String?,
        provider: AccountProvider?,
        details: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        let event = QueuedAuthDiagnosticEvent(
            clientEventId: UUID().uuidString.lowercased(),
            eventName: eventName,
            occurredAt: isoFormatter.string(from: timestamp),
            appLaunchId: appLaunchId,
            clientBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            osVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model,
            provider: provider?.rawValue,
            userIdHint: userIdHint,
            metadata: sanitized(details)
        )

        locked {
            var events = loadQueuedEventsLocked()
            events.append(event)
            if events.count > maxQueuedEvents {
                events.removeFirst(events.count - maxQueuedEvents)
            }
            saveQueuedEventsLocked(events)
        }

        NSLog("[auth_diagnostic] %@ %@", event.eventName, event.metadata.description)
    }

    func flush(apiClient: APIClient) async {
        let events: [QueuedAuthDiagnosticEvent] = locked {
            guard !isFlushing else { return [] }
            isFlushing = true
            return loadQueuedEventsLocked()
        }

        guard !events.isEmpty else {
            locked { isFlushing = false }
            return
        }

        do {
            _ = try await apiClient.recordAuthDiagnosticEvents(
                AuthDiagnosticBatchRequest(events: events.map { $0.requestPayload() })
            )
            let sentIds = Set(events.map(\.clientEventId))
            locked {
                let remaining = loadQueuedEventsLocked().filter { !sentIds.contains($0.clientEventId) }
                saveQueuedEventsLocked(remaining)
                isFlushing = false
            }
        } catch {
            locked { isFlushing = false }
            NSLog("[auth_diagnostic_flush_failed] %@", error.localizedDescription)
        }
    }

    private func sanitized(_ details: [String: String]) -> [String: String] {
        var output: [String: String] = [:]
        for (key, value) in details {
            let cleanKey = String(key.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
            guard !cleanKey.isEmpty else { continue }
            output[cleanKey] = String(value.prefix(500))
        }
        return output
    }

    private func loadQueuedEventsLocked() -> [QueuedAuthDiagnosticEvent] {
        guard let data = defaults.data(forKey: queueKey),
              let events = try? decoder.decode([QueuedAuthDiagnosticEvent].self, from: data) else {
            return []
        }
        return events
    }

    private func saveQueuedEventsLocked(_ events: [QueuedAuthDiagnosticEvent]) {
        guard !events.isEmpty else {
            defaults.removeObject(forKey: queueKey)
            return
        }
        guard let data = try? encoder.encode(events) else { return }
        defaults.set(data, forKey: queueKey)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
