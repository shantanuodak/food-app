import Foundation

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
            print("[telemetry] failed_to_encode_event eventName=\(event.eventName)")
            return
        }
        print("[telemetry] \(json)")
    }

    func nowISO8601() -> String {
        isoFormatter.string(from: Date())
    }
}
