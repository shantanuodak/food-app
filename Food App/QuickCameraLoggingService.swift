import Foundation
import UIKit

enum QuickCameraLoggingService {
    @MainActor
    static func processCapturedImage(_ image: UIImage, apiClient: APIClient) async {
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

        guard let prepared else {
            await QuickCameraNotificationService.notifyStatus(
                id: pendingId,
                title: "Couldn’t read photo",
                body: "Retake the picture from Food Camera."
            )
            return
        }

        do {
            let response = try await apiClient.parseImageLog(
                imageData: prepared.uploadData,
                mimeType: prepared.mimeType,
                loggedAt: loggedAt
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
