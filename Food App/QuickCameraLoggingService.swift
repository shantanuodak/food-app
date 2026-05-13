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

        let prepared: PreparedImagePayload? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: MainLoggingShellView.prepareImagePayload(from: image))
            }
        }
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
            let response = try await apiClient.parseImageLog(
                imageData: prepared.uploadData,
                mimeType: prepared.mimeType,
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
                inputKind: "image"
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
