import Foundation

enum ImageParseAttemptSource: String {
    case drawer
    case quickCamera = "quick_camera"
}

enum ImageParseAttemptTelemetry {
    static func clientBuild() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    static func errorCode(from error: Error) -> String {
        if let apiError = error as? APIClientError {
            switch apiError {
            case .invalidURL:
                return "invalid_url"
            case .missingAuthToken:
                return "missing_auth_token"
            case .networkFailure:
                return "network_failure"
            case .server(_, let payload):
                return payload.code
            case .decodingFailure:
                return "decoding_failure"
            case .unexpectedStatus(let status):
                return "unexpected_status_\(status)"
            }
        }
        if error is CancellationError {
            return "cancelled"
        }
        return "unknown_error"
    }

    static func emit(
        apiClient: APIClient,
        clientAttemptId: String,
        parseRequestId: String?,
        outcome: String,
        errorCode: String?,
        prepMs: Int?,
        requestMs: Int?,
        totalMs: Int?,
        backendMs: Int?,
        imageBytes: Int?,
        mimeType: String?,
        visionModel: String?,
        fallbackUsed: Bool?,
        source: ImageParseAttemptSource,
        metadata: [String: String]? = nil
    ) {
        let body = ImageParseAttemptTelemetryRequest(
            clientAttemptId: clientAttemptId,
            parseRequestId: parseRequestId,
            outcome: outcome,
            errorCode: errorCode,
            prepMs: prepMs,
            requestMs: requestMs,
            totalMs: totalMs,
            backendMs: backendMs,
            imageBytes: imageBytes,
            mimeType: mimeType,
            visionModel: visionModel,
            fallbackUsed: fallbackUsed,
            clientBuild: clientBuild(),
            source: source.rawValue,
            metadata: metadata
        )

        Task {
            do {
                _ = try await apiClient.recordImageParseAttempt(body)
            } catch {
                NSLog("[image_parse_attempt_telemetry_failed] \(error.localizedDescription)")
            }
        }
    }
}
