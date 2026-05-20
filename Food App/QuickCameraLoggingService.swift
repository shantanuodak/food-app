import Foundation
import UIKit

enum QuickCameraLoggingService {
    @MainActor
    static func processCapturedImage(_ image: UIImage, apiClient: APIClient) async {
        let flowStartedAt = Date()
        let clientAttemptId = UUID().uuidString.lowercased()
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "QuickCameraParse") {}
        defer {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
        }

        let pendingId = UUID().uuidString.lowercased()
        let loggedAt = HomeLoggingDateUtils.loggedAtFormatter.string(from: Date())
        await QuickCameraNotificationService.notifyAnalyzing(id: pendingId)

        async let visionTask = Task.detached(priority: .userInitiated) {
            await ImageVisionPipeline.analyze(image, timeoutMs: 800)
        }.value
        async let preparedTask = Task.detached(priority: .userInitiated) {
            MainLoggingShellView.prepareImagePayload(from: image)
        }.value
        let (visionResult, prepared) = await (visionTask, preparedTask)
        let prepMs = Int(Date().timeIntervalSince(flowStartedAt) * 1000)

        guard let prepared else {
            ImageParseAttemptTelemetry.emit(
                apiClient: apiClient,
                clientAttemptId: clientAttemptId,
                parseRequestId: nil,
                outcome: "failed",
                errorCode: "image_prep_failed",
                prepMs: prepMs,
                requestMs: nil,
                totalMs: Int(Date().timeIntervalSince(flowStartedAt) * 1000),
                backendMs: nil,
                imageBytes: nil,
                mimeType: nil,
                visionModel: nil,
                fallbackUsed: nil,
                source: .quickCamera
            )
            await QuickCameraNotificationService.notifyStatus(
                id: pendingId,
                title: "Couldn’t read photo",
                body: "Retake the picture from Food Camera."
            )
            return
        }

        do {
            let requestStartedAt = Date()
            let response = try await performLaneParse(
                prepared: prepared,
                visionResult: visionResult,
                apiClient: apiClient,
                clientAttemptId: clientAttemptId,
                loggedAt: loggedAt
            )
            let requestMs = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
            let totalMs = Int(Date().timeIntervalSince(flowStartedAt) * 1000)
            ImageParseAttemptTelemetry.emit(
                apiClient: apiClient,
                clientAttemptId: clientAttemptId,
                parseRequestId: response.parseRequestId,
                outcome: "succeeded",
                errorCode: nil,
                prepMs: prepMs,
                requestMs: requestMs,
                totalMs: totalMs,
                backendMs: Int(response.parseDurationMs),
                imageBytes: prepared.uploadData.count,
                mimeType: prepared.mimeType,
                visionModel: response.visionModel,
                fallbackUsed: response.visionFallbackUsed,
                source: .quickCamera
            )
            let displayName = displayName(for: response)
            let calories = Int(response.totals.calories.rounded())
            let saveRequest = try? FoodLogSaveRequestBuilder.makeSaveRequest(
                rawText: imageRawText(for: response, fallback: displayName),
                loggedAt: loggedAt,
                parseResponse: response,
                inputKind: response.inputKind ?? "image"
            )
            let pendingLog = QuickCameraPendingLog(
                id: pendingId,
                createdAt: Date(),
                displayName: displayName,
                calories: calories,
                saveRequest: saveRequest,
                idempotencyKey: saveRequest == nil ? nil : UUID()
            )
            QuickCameraPendingLogStore.save(pendingLog)
            await QuickCameraNotificationService.notifyParsed(pendingLog)
        } catch let apiError as APIClientError {
            ImageParseAttemptTelemetry.emit(
                apiClient: apiClient,
                clientAttemptId: clientAttemptId,
                parseRequestId: nil,
                outcome: "failed",
                errorCode: ImageParseAttemptTelemetry.errorCode(from: apiError),
                prepMs: prepMs,
                requestMs: nil,
                totalMs: Int(Date().timeIntervalSince(flowStartedAt) * 1000),
                backendMs: nil,
                imageBytes: prepared.uploadData.count,
                mimeType: prepared.mimeType,
                visionModel: nil,
                fallbackUsed: nil,
                source: .quickCamera
            )
            if apiError.isAuthTokenError(treatForbiddenAsAuthFailure: true) {
                await QuickCameraNotificationService.notifyStatus(
                    id: pendingId,
                    title: "Sign in needed",
                    body: "Open Food App and sign in before using Food Camera."
                )
            } else {
                await QuickCameraNotificationService.notifyStatus(
                    id: pendingId,
                    title: "Couldn’t detect food",
                    body: apiError.errorDescription ?? "Retake the picture from Food Camera."
                )
            }
        } catch {
            ImageParseAttemptTelemetry.emit(
                apiClient: apiClient,
                clientAttemptId: clientAttemptId,
                parseRequestId: nil,
                outcome: "failed",
                errorCode: ImageParseAttemptTelemetry.errorCode(from: error),
                prepMs: prepMs,
                requestMs: nil,
                totalMs: Int(Date().timeIntervalSince(flowStartedAt) * 1000),
                backendMs: nil,
                imageBytes: prepared.uploadData.count,
                mimeType: prepared.mimeType,
                visionModel: nil,
                fallbackUsed: nil,
                source: .quickCamera
            )
            await QuickCameraNotificationService.notifyStatus(
                id: pendingId,
                title: "Couldn’t detect food",
                body: "Retake the picture from Food Camera."
            )
        }
    }

    private enum QuickCameraParseLane {
        case barcode(String, String?)
        case label(String)
        case vision
    }

    private static func decideLane(visionResult: ImageVisionResult) -> QuickCameraParseLane {
        if let barcode = visionResult.barcode, barcode.confidence >= 0.95 {
            return .barcode(barcode.payload, barcode.symbology)
        }
        if let label = visionResult.labelPanel, label.confidence >= 0.7 {
            return .label(visionResult.ocrText)
        }
        if let barcode = visionResult.barcode,
           barcode.confidence >= 0.80,
           visionResult.labelPanel == nil {
            return .barcode(barcode.payload, barcode.symbology)
        }
        return .vision
    }

    private static func performLaneParse(
        prepared: PreparedImagePayload,
        visionResult: ImageVisionResult,
        apiClient: APIClient,
        clientAttemptId: String,
        loggedAt: String
    ) async throws -> ParseLogResponse {
        switch decideLane(visionResult: visionResult) {
        case let .barcode(code, symbology):
            do {
                let response = try await apiClient.parseBarcode(
                    code: code,
                    symbology: symbology,
                    clientAttemptId: clientAttemptId,
                    loggedAt: loggedAt
                )
                if response.fallback == "image" {
                    if visionResult.labelPanel != nil, !visionResult.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return try await parseLabel(
                            prepared: prepared,
                            ocrText: visionResult.ocrText,
                            apiClient: apiClient,
                            clientAttemptId: clientAttemptId,
                            loggedAt: loggedAt
                        )
                    }
                    return try await parseVision(
                        prepared: prepared,
                        apiClient: apiClient,
                        clientAttemptId: clientAttemptId,
                        loggedAt: loggedAt
                    )
                }
                return response
            } catch {
                return try await parseVision(
                    prepared: prepared,
                    apiClient: apiClient,
                    clientAttemptId: clientAttemptId,
                    loggedAt: loggedAt
                )
            }
        case let .label(ocrText):
            do {
                return try await parseLabel(
                    prepared: prepared,
                    ocrText: ocrText,
                    apiClient: apiClient,
                    clientAttemptId: clientAttemptId,
                    loggedAt: loggedAt
                )
            } catch {
                return try await parseVision(
                    prepared: prepared,
                    apiClient: apiClient,
                    clientAttemptId: clientAttemptId,
                    loggedAt: loggedAt
                )
            }
        case .vision:
            return try await parseVision(
                prepared: prepared,
                apiClient: apiClient,
                clientAttemptId: clientAttemptId,
                loggedAt: loggedAt
            )
        }
    }

    private static func parseLabel(
        prepared: PreparedImagePayload,
        ocrText: String,
        apiClient: APIClient,
        clientAttemptId: String,
        loggedAt: String
    ) async throws -> ParseLogResponse {
        try await apiClient.parseLabel(
            ocrText: ocrText,
            imageData: prepared.uploadData,
            mimeType: prepared.mimeType,
            clientAttemptId: clientAttemptId,
            loggedAt: loggedAt
        )
    }

    private static func parseVision(
        prepared: PreparedImagePayload,
        apiClient: APIClient,
        clientAttemptId: String,
        loggedAt: String
    ) async throws -> ParseLogResponse {
        try await apiClient.parseImageLog(
            imageData: prepared.uploadData,
            mimeType: prepared.mimeType,
            loggedAt: loggedAt,
            clientAttemptId: clientAttemptId
        )
    }

    private static func displayName(for response: ParseLogResponse) -> String {
        let extracted = response.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let extracted, !extracted.isEmpty {
            return extracted
        }

        let names = response.items.map(\.name).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !names.isEmpty {
            return names.prefix(3).joined(separator: ", ")
        }

        return "Camera food log"
    }

    private static func imageRawText(for response: ParseLogResponse, fallback: String) -> String {
        let extracted = response.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let extracted, !extracted.isEmpty {
            return extracted
        }
        return fallback
    }
}
