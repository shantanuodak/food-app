import Foundation
import UserNotifications

enum QuickCameraNotificationIdentifier {
    static let parsedCategory = "food-app.quick-camera.parsed"
    static let reviewCategory = "food-app.quick-camera.review"

    static let logAction = "food-app.quick-camera.action.log"
    static let reviewAction = "food-app.quick-camera.action.review"
    static let retakeAction = "food-app.quick-camera.action.retake"
    static let discardAction = "food-app.quick-camera.action.discard"

    static func parsedRequest(id: String) -> String {
        "food-app.quick-camera.parsed.\(id)"
    }

    static func statusRequest(id: String) -> String {
        "food-app.quick-camera.status.\(id)"
    }
}

enum QuickCameraNotificationService {
    static func configure(center: UNUserNotificationCenter = .current()) {
        let log = UNNotificationAction(
            identifier: QuickCameraNotificationIdentifier.logAction,
            title: "Log",
            options: []
        )
        let review = UNNotificationAction(
            identifier: QuickCameraNotificationIdentifier.reviewAction,
            title: "Review",
            options: [.foreground]
        )
        let retake = UNNotificationAction(
            identifier: QuickCameraNotificationIdentifier.retakeAction,
            title: "Retake",
            options: [.foreground]
        )
        let discard = UNNotificationAction(
            identifier: QuickCameraNotificationIdentifier.discardAction,
            title: "Discard",
            options: [.destructive]
        )

        let parsedCategory = UNNotificationCategory(
            identifier: QuickCameraNotificationIdentifier.parsedCategory,
            actions: [log, retake, discard],
            intentIdentifiers: [],
            options: []
        )
        let reviewCategory = UNNotificationCategory(
            identifier: QuickCameraNotificationIdentifier.reviewCategory,
            actions: [review, retake, discard],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([parsedCategory, reviewCategory])
    }

    static func notifyParsed(_ pendingLog: QuickCameraPendingLog) async {
        let content = UNMutableNotificationContent()
        content.title = "Food detected"
        if pendingLog.canSaveDirectly {
            content.body = "\(pendingLog.displayName), about \(pendingLog.calories) cal. Log this?"
        } else {
            content.body = "\(pendingLog.displayName), about \(pendingLog.calories) cal. Review or retake?"
        }
        content.sound = .default
        content.categoryIdentifier = pendingLog.canSaveDirectly
            ? QuickCameraNotificationIdentifier.parsedCategory
            : QuickCameraNotificationIdentifier.reviewCategory
        content.userInfo = ["pendingLogId": pendingLog.id]

        await addNotification(
            identifier: QuickCameraNotificationIdentifier.parsedRequest(id: pendingLog.id),
            content: content
        )
    }

    static func notifyAnalyzing(id: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Analyzing food photo"
        content.body = "I’ll let you know what I find."
        content.sound = .default

        await addNotification(
            identifier: QuickCameraNotificationIdentifier.statusRequest(id: "\(id).analyzing"),
            content: content,
            delay: 0.2
        )
    }

    static func notifyStatus(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        await addNotification(
            identifier: QuickCameraNotificationIdentifier.statusRequest(id: id),
            content: content
        )
    }

    private static func addNotification(
        identifier: String,
        content: UNMutableNotificationContent,
        delay: TimeInterval = 1
    ) async {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Notification failures should not interrupt capture or saving.
        }
    }
}
