import Foundation

extension MainLoggingShellView {

    func emitParseTelemetrySuccess(response: ParseLogResponse, durationMs: Double, uiApplied: Bool) {
        let reasonSummary = (response.reasonCodes ?? []).joined(separator: ",")
        TelemetryClient.shared.emit(
            TelemetryEvent(
                eventName: "parse_request",
                feature: "parse",
                outcome: .success,
                durationMs: durationMs,
                timestamp: TelemetryClient.shared.nowISO8601(),
                environment: appStore.configuration.environment.rawValue,
                backendRequestId: response.requestId,
                backendErrorCode: nil,
                httpStatusCode: nil,
                parseRequestId: response.parseRequestId,
                parseVersion: response.parseVersion,
                details: [
                    "route": .string(response.route),
                    "cacheHit": .bool(response.cacheHit),
                    "fallbackUsed": .bool(response.fallbackUsed),
                    "needsClarification": .bool(response.needsClarification),
                    "reasonCodes": .string(reasonSummary),
                    "retryAfterSeconds": .int(response.retryAfterSeconds ?? 0),
                    "uiApplied": .bool(uiApplied)
                ]
            )
        )
    }

    func emitParseTelemetryFailure(error: Error, durationMs: Double, uiApplied: Bool) {
        let metadata = telemetryErrorMetadata(error)
        TelemetryClient.shared.emit(
            TelemetryEvent(
                eventName: "parse_request",
                feature: "parse",
                outcome: .failure,
                durationMs: durationMs,
                timestamp: TelemetryClient.shared.nowISO8601(),
                environment: appStore.configuration.environment.rawValue,
                backendRequestId: metadata.backendRequestId,
                backendErrorCode: metadata.backendErrorCode,
                httpStatusCode: metadata.httpStatusCode,
                parseRequestId: parseResult?.parseRequestId,
                parseVersion: parseResult?.parseVersion,
                details: [
                    "uiApplied": .bool(uiApplied),
                    "errorMessage": .string((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                ]
            )
        )
    }

    func emitSaveTelemetrySuccess(request: SaveLogRequest, durationMs: Double, isRetry: Bool, logId: String) {
        emitSaveTelemetrySuccess(request: request, durationMs: durationMs, isRetry: isRetry, logId: logId, timeToLogMs: nil)
    }

    func emitSaveTelemetrySuccess(
        request: SaveLogRequest,
        durationMs: Double,
        isRetry: Bool,
        logId: String,
        timeToLogMs: Double?
    ) {
        var details: [String: TelemetryValue] = [
            "isRetry": .bool(isRetry),
            "itemsCount": .int(request.parsedLog.items.count),
            "rawTextLength": .int(request.parsedLog.rawText.count),
            "logId": .string(logId)
        ]
        if let timeToLogMs {
            details["timeToLogMs"] = .int(Int(timeToLogMs.rounded()))
        }

        TelemetryClient.shared.emit(
            TelemetryEvent(
                eventName: "save_log",
                feature: "save",
                outcome: .success,
                durationMs: durationMs,
                timestamp: TelemetryClient.shared.nowISO8601(),
                environment: appStore.configuration.environment.rawValue,
                backendRequestId: nil,
                backendErrorCode: nil,
                httpStatusCode: nil,
                parseRequestId: request.parseRequestId,
                parseVersion: request.parseVersion,
                details: details
            )
        )
    }

    func emitSaveTelemetryFailure(request: SaveLogRequest, error: Error, durationMs: Double, isRetry: Bool) {
        let metadata = telemetryErrorMetadata(error)
        TelemetryClient.shared.emit(
            TelemetryEvent(
                eventName: "save_log",
                feature: "save",
                outcome: .failure,
                durationMs: durationMs,
                timestamp: TelemetryClient.shared.nowISO8601(),
                environment: appStore.configuration.environment.rawValue,
                backendRequestId: metadata.backendRequestId,
                backendErrorCode: metadata.backendErrorCode,
                httpStatusCode: metadata.httpStatusCode,
                parseRequestId: request.parseRequestId,
                parseVersion: request.parseVersion,
                details: [
                    "isRetry": .bool(isRetry),
                    "itemsCount": .int(request.parsedLog.items.count),
                    "rawTextLength": .int(request.parsedLog.rawText.count),
                    "errorMessage": .string((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                ]
            )
        )
    }

    func telemetryErrorMetadata(_ error: Error) -> (backendRequestId: String?, backendErrorCode: String?, httpStatusCode: Int?) {
        guard let apiError = error as? APIClientError else {
            return (nil, nil, nil)
        }

        switch apiError {
        case let .server(statusCode, payload):
            return (payload.requestId, payload.code, statusCode)
        case let .unexpectedStatus(code):
            return (nil, "UNEXPECTED_STATUS", code)
        default:
            return (nil, nil, nil)
        }
    }

    func saveAttemptErrorCode(_ error: Error) -> String? {
        let metadata = telemetryErrorMetadata(error)
        if let backendCode = metadata.backendErrorCode, !backendCode.isEmpty {
            return backendCode
        }
        if let statusCode = metadata.httpStatusCode {
            return "HTTP_\(statusCode)"
        }
        return nil
    }

    func telemetrySource(for intent: SaveIntent) -> SaveAttemptSource {
        switch intent {
        case .manual:
            return .manual
        case .retry:
            return .retry
        case .auto, .dateChangeBackground:
            return .auto
        }
    }

    func elapsedMs(since startedAt: Date) -> Double {
        (Date().timeIntervalSince(startedAt) * 1000).rounded()
    }
}
