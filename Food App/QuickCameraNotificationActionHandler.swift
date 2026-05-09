import Foundation
import UserNotifications

enum QuickCameraNotificationActionHandler {
    static func handle(_ response: UNNotificationResponse) async {
        guard let pendingLogId = response.notification.request.content.userInfo["pendingLogId"] as? String else {
            return
        }

        switch response.actionIdentifier {
        case QuickCameraNotificationIdentifier.logAction:
            await logPendingEntry(id: pendingLogId)

        case QuickCameraNotificationIdentifier.discardAction:
            QuickCameraPendingLogStore.remove(id: pendingLogId)

        case QuickCameraNotificationIdentifier.retakeAction:
            QuickCameraPendingLogStore.remove(id: pendingLogId)
            await MainActor.run {
                QuickCameraLaunchStore.requestLaunch()
            }

        case QuickCameraNotificationIdentifier.reviewAction, UNNotificationDefaultActionIdentifier:
            // The foreground action opens the app. A fuller review surface can
            // be added later without changing the notification contract.
            break

        default:
            break
        }
    }

    private static func logPendingEntry(id: String) async {
        guard let pendingLog = QuickCameraPendingLogStore.load(id: id),
              let saveRequest = pendingLog.saveRequest,
              let idempotencyKey = pendingLog.idempotencyKey else {
            await QuickCameraNotificationService.notifyStatus(
                id: id,
                title: "Review needed",
                body: "Open Food App to finish this camera log."
            )
            return
        }

        do {
            let apiClient = LiveAPIClientFactory.make()
            _ = try await apiClient.saveLog(saveRequest, idempotencyKey: idempotencyKey)
            QuickCameraPendingLogStore.remove(id: id)
            await QuickCameraNotificationService.notifyStatus(
                id: id,
                title: "Food logged",
                body: "\(pendingLog.displayName) was added to today."
            )
            NotificationCenter.default.post(
                name: .nutritionProgressDidChange,
                object: nil,
                userInfo: savedDayUserInfo(from: saveRequest)
            )
        } catch {
            await QuickCameraNotificationService.notifyStatus(
                id: id,
                title: "Couldn’t log food",
                body: "Open Food App to finish this camera log."
            )
        }
    }

    private static func savedDayUserInfo(from saveRequest: SaveLogRequest) -> [String: String]? {
        return [
            "savedDay": HomeLoggingDateUtils.summaryDayString(fromLoggedAt: saveRequest.parsedLog.loggedAt)
        ]
    }
}
