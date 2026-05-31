import Foundation
import UserNotifications

enum FoodNotificationDestination: String {
    case voice
    case text
    case camera
    case streaks
    case reminders
    case home
}

enum FoodNotificationAction {
    static let logByVoice = "food-app.action.log.voice"
    static let logByText = "food-app.action.log.text"
    static let openCamera = "food-app.action.open.camera"
    static let snooze = "food-app.action.snooze"
}

enum FoodNotificationCategory {
    static let mealReminder = "food-app.category.meal-reminder"
    static let engagement = "food-app.category.engagement"
    static let discovery = "food-app.category.discovery"
    static let healthNudge = "food-app.category.health-nudge"

    static func categories() -> Set<UNNotificationCategory> {
        let voice = UNNotificationAction(
            identifier: FoodNotificationAction.logByVoice,
            title: "Log by voice",
            options: [.foreground]
        )
        let text = UNNotificationAction(
            identifier: FoodNotificationAction.logByText,
            title: "Type it",
            options: [.foreground]
        )
        let camera = UNNotificationAction(
            identifier: FoodNotificationAction.openCamera,
            title: "Camera",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: FoodNotificationAction.snooze,
            title: "Later",
            options: []
        )

        let mealReminder = UNNotificationCategory(
            identifier: Self.mealReminder,
            actions: [voice, text, camera, snooze],
            intentIdentifiers: [],
            options: []
        )
        let engagement = UNNotificationCategory(
            identifier: Self.engagement,
            actions: [voice, text, snooze],
            intentIdentifiers: [],
            options: []
        )
        let discovery = UNNotificationCategory(
            identifier: Self.discovery,
            actions: [text, camera],
            intentIdentifiers: [],
            options: []
        )
        // Health nudges: a quick log path plus a snooze. Movement nudges
        // carry the same actions — logging a post-walk snack is fair game.
        let healthNudge = UNNotificationCategory(
            identifier: Self.healthNudge,
            actions: [text, voice, snooze],
            intentIdentifiers: [],
            options: []
        )

        return [mealReminder, engagement, discovery, healthNudge]
    }

    static func configure(center: UNUserNotificationCenter = .current()) {
        center.setNotificationCategories(categories())
    }
}

enum FoodNotificationActionHandler {
    static func handle(_ response: UNNotificationResponse) async -> Bool {
        let userInfo = response.notification.request.content.userInfo
        recordInteractionIfPossible(userInfo: userInfo, actionIdentifier: response.actionIdentifier)
        let fallbackDestination = (userInfo["destination"] as? String)
            .flatMap(FoodNotificationDestination.init(rawValue:))
        let destination: FoodNotificationDestination?

        switch response.actionIdentifier {
        case FoodNotificationAction.logByVoice:
            destination = .voice
        case FoodNotificationAction.logByText:
            destination = .text
        case FoodNotificationAction.openCamera:
            destination = .camera
        case FoodNotificationAction.snooze:
            await snooze(response)
            return true
        case UNNotificationDefaultActionIdentifier:
            destination = fallbackDestination ?? .home
        default:
            destination = fallbackDestination
        }

        guard let destination else { return false }
        await MainActor.run {
            route(to: destination)
        }
        return true
    }

    private static func recordInteractionIfPossible(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        guard let deliveryKey = userInfo["deliveryKey"] as? String,
              let templateKey = userInfo["templateKey"] as? String,
              let destinationRaw = userInfo["destination"] as? String,
              let destination = FoodNotificationDestination(rawValue: destinationRaw) else {
            return
        }

        let eventType: String
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            eventType = "opened"
        case FoodNotificationAction.snooze:
            eventType = "snoozed"
        default:
            eventType = "action_tapped"
        }

        let recordedActionIdentifier: String?
        if actionIdentifier == UNNotificationDefaultActionIdentifier {
            recordedActionIdentifier = nil
        } else {
            recordedActionIdentifier = actionIdentifier
        }

        let request = NotificationEventRequest(
            deliveryKey: deliveryKey,
            templateKey: templateKey,
            destination: destination.rawValue,
            eventType: eventType,
            actionIdentifier: recordedActionIdentifier
        )

        Task(priority: .utility) {
            let apiClient = LiveAPIClientFactory.make()
            _ = try? await apiClient.recordNotificationEvent(request)
        }
    }

    @MainActor
    private static func route(to destination: FoodNotificationDestination) {
        switch destination {
        case .voice:
            NotificationCenter.default.post(name: .openVoiceFromTabBar, object: nil)
        case .text, .home:
            NotificationCenter.default.post(name: .openTextLoggerFromNotification, object: nil)
        case .camera:
            NotificationCenter.default.post(name: .openCameraFromTabBar, object: nil)
        case .streaks:
            NotificationCenter.default.post(name: .openStreaksFromNotification, object: nil)
        case .reminders:
            NotificationCenter.default.post(name: .openRemindersFromNotification, object: nil)
        }
    }

    private static func snooze(_ response: UNNotificationResponse) async {
        let content = response.notification.request.content.mutableCopy() as? UNMutableNotificationContent
        guard let content else { return }
        let request = UNNotificationRequest(
            identifier: "\(response.notification.request.identifier).snooze",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
