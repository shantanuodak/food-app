import Foundation
import UserNotifications

struct MealReminderTime: Codable, Equatable {
    var hour: Int
    var minute: Int
}

struct MealReminderSettings: Codable, Equatable {
    var remindersEnabled: Bool
    var breakfastEnabled: Bool
    var lunchEnabled: Bool
    var dinnerEnabled: Bool
    var breakfastStart: MealReminderTime
    var lunchStart: MealReminderTime
    var dinnerStart: MealReminderTime
    var breakfast: MealReminderTime
    var lunch: MealReminderTime
    var dinner: MealReminderTime
    var eatingWindowEnabled: Bool
    var eatingWindowStart: MealReminderTime
    var eatingWindowEnd: MealReminderTime

    static let `default` = MealReminderSettings(
        remindersEnabled: false,
        breakfastEnabled: true,
        lunchEnabled: true,
        dinnerEnabled: true,
        breakfastStart: MealReminderTime(hour: 7, minute: 0),
        lunchStart: MealReminderTime(hour: 11, minute: 30),
        dinnerStart: MealReminderTime(hour: 18, minute: 0),
        breakfast: MealReminderTime(hour: 9, minute: 30),
        lunch: MealReminderTime(hour: 14, minute: 0),
        dinner: MealReminderTime(hour: 21, minute: 0),
        eatingWindowEnabled: false,
        eatingWindowStart: MealReminderTime(hour: 8, minute: 0),
        eatingWindowEnd: MealReminderTime(hour: 20, minute: 0)
    )

    init(
        remindersEnabled: Bool,
        breakfastEnabled: Bool,
        lunchEnabled: Bool,
        dinnerEnabled: Bool,
        breakfastStart: MealReminderTime,
        lunchStart: MealReminderTime,
        dinnerStart: MealReminderTime,
        breakfast: MealReminderTime,
        lunch: MealReminderTime,
        dinner: MealReminderTime,
        eatingWindowEnabled: Bool,
        eatingWindowStart: MealReminderTime,
        eatingWindowEnd: MealReminderTime
    ) {
        self.remindersEnabled = remindersEnabled
        self.breakfastEnabled = breakfastEnabled
        self.lunchEnabled = lunchEnabled
        self.dinnerEnabled = dinnerEnabled
        self.breakfastStart = breakfastStart
        self.lunchStart = lunchStart
        self.dinnerStart = dinnerStart
        self.breakfast = breakfast
        self.lunch = lunch
        self.dinner = dinner
        self.eatingWindowEnabled = eatingWindowEnabled
        self.eatingWindowStart = eatingWindowStart
        self.eatingWindowEnd = eatingWindowEnd
    }

    enum CodingKeys: String, CodingKey {
        case remindersEnabled
        case breakfastEnabled
        case lunchEnabled
        case dinnerEnabled
        case breakfastStart
        case lunchStart
        case dinnerStart
        case breakfast
        case lunch
        case dinner
        case eatingWindowEnabled
        case eatingWindowStart
        case eatingWindowEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        remindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? fallback.remindersEnabled
        breakfastEnabled = try container.decodeIfPresent(Bool.self, forKey: .breakfastEnabled) ?? fallback.breakfastEnabled
        lunchEnabled = try container.decodeIfPresent(Bool.self, forKey: .lunchEnabled) ?? fallback.lunchEnabled
        dinnerEnabled = try container.decodeIfPresent(Bool.self, forKey: .dinnerEnabled) ?? fallback.dinnerEnabled
        breakfastStart = try container.decodeIfPresent(MealReminderTime.self, forKey: .breakfastStart) ?? fallback.breakfastStart
        lunchStart = try container.decodeIfPresent(MealReminderTime.self, forKey: .lunchStart) ?? fallback.lunchStart
        dinnerStart = try container.decodeIfPresent(MealReminderTime.self, forKey: .dinnerStart) ?? fallback.dinnerStart
        breakfast = try container.decodeIfPresent(MealReminderTime.self, forKey: .breakfast) ?? fallback.breakfast
        lunch = try container.decodeIfPresent(MealReminderTime.self, forKey: .lunch) ?? fallback.lunch
        dinner = try container.decodeIfPresent(MealReminderTime.self, forKey: .dinner) ?? fallback.dinner
        eatingWindowEnabled = try container.decodeIfPresent(Bool.self, forKey: .eatingWindowEnabled) ?? fallback.eatingWindowEnabled
        eatingWindowStart = try container.decodeIfPresent(MealReminderTime.self, forKey: .eatingWindowStart) ?? fallback.eatingWindowStart
        eatingWindowEnd = try container.decodeIfPresent(MealReminderTime.self, forKey: .eatingWindowEnd) ?? fallback.eatingWindowEnd
    }
}

/// Owns the lifecycle of all `UNNotificationRequest`s the app schedules.
///
/// The backend can also send richer APNs nudges, but meal reminders need a
/// reliable on-device fallback. Calling `reconcile(...)` is idempotent: it
/// removes stale app-owned requests, then schedules the current meal reminders
/// if the user has granted notification permission.
enum FoodAppNotificationIdentifier {
    static let mealBreakfast = "food-app.meal.breakfast"
    static let mealLunch = "food-app.meal.lunch"
    static let mealDinner = "food-app.meal.dinner"
    static let snackingNudge = "food-app.snacking.nudge"
    static let consistencyLunch = "food-app.consistency.lunch"
    static let consistencyDinner = "food-app.consistency.dinner"
    static let endOfDayRecovery = "food-app.engagement.end-of-day"
    static let reactivation24h = "food-app.engagement.reactivation.24h"
    static let reactivation48h = "food-app.engagement.reactivation.48h"
    static let featureDiscovery = "food-app.discovery.next"

    static let allFoodAppPrefix = "food-app."
}

@MainActor
final class NotificationScheduler {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Read the system's current authorization status. Cheap; safe to call on launch.
    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    /// Request `.alert + .badge + .sound` from the user. Returns the resolved
    /// status (granted maps to `.authorized`, denied to `.denied`).
    func requestAuthorization() async -> UNAuthorizationStatus {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }

    /// Cancel every pending notification this app has scheduled. Used
    /// before re-scheduling so we never end up with stale identifiers.
    func cancelAll() {
        center.removePendingNotificationRequests(
            withIdentifiers: [
                FoodAppNotificationIdentifier.snackingNudge,
                FoodAppNotificationIdentifier.consistencyLunch,
                FoodAppNotificationIdentifier.consistencyDinner,
                FoodAppNotificationIdentifier.mealBreakfast,
                FoodAppNotificationIdentifier.mealLunch,
                FoodAppNotificationIdentifier.mealDinner,
                FoodAppNotificationIdentifier.endOfDayRecovery,
                FoodAppNotificationIdentifier.reactivation24h,
                FoodAppNotificationIdentifier.reactivation48h,
                FoodAppNotificationIdentifier.featureDiscovery
            ]
        )
    }

    /// The single entry point — call after settings changes, after permission
    /// grant, and on app launch. Idempotent.
    func reconcile(
        challenge _: ChallengeChoice?,
        authState: UNAuthorizationStatus,
        mealReminders: MealReminderSettings,
        hasLoggedToday _: Bool
    ) async {
        cancelAll()
        guard canSchedule(authState), mealReminders.remindersEnabled else { return }

        await scheduleMealReminder(
            identifier: FoodAppNotificationIdentifier.mealBreakfast,
            mealKey: "breakfast",
            title: "Breakfast cameo 🍳",
            body: "Tiny breakfast check: say it, type it, or snap it before the coffee brain takes over ☕️",
            time: mealReminders.breakfast,
            isEnabled: mealReminders.breakfastEnabled
        )
        await scheduleMealReminder(
            identifier: FoodAppNotificationIdentifier.mealLunch,
            mealKey: "lunch",
            title: "Lunch roll call 🥗",
            body: "What did lunch look like? A quick voice note totally counts.",
            time: mealReminders.lunch,
            isEnabled: mealReminders.lunchEnabled
        )
        await scheduleMealReminder(
            identifier: FoodAppNotificationIdentifier.mealDinner,
            mealKey: "dinner",
            title: "Dinner plot twist 🍽️",
            body: "Future-you loves a complete log. Add dinner while it is still fresh ✨",
            time: mealReminders.dinner,
            isEnabled: mealReminders.dinnerEnabled
        )
    }

    private func canSchedule(_ authState: UNAuthorizationStatus) -> Bool {
        switch authState {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func scheduleMealReminder(
        identifier: String,
        mealKey: String,
        title: String,
        body: String,
        time: MealReminderTime,
        isEnabled: Bool
    ) async {
        guard isEnabled else { return }

        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar.current
        dateComponents.timeZone = TimeZone.current
        dateComponents.hour = time.hour
        dateComponents.minute = time.minute

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = FoodNotificationCategory.mealReminder
        content.userInfo = [
            "source": "local-meal-reminder",
            "meal": mealKey,
            "destination": FoodNotificationDestination.voice.rawValue
        ]

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            NSLog("[notifications] local meal reminder schedule failed %@ %@", identifier, error.localizedDescription)
        }
    }
}

enum AdminTestNotificationKind: String, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case endOfDay
    case discovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast:
            return "Breakfast cameo 🍳"
        case .lunch:
            return "Lunch roll call 🥗"
        case .dinner:
            return "Dinner plot twist 🍽️"
        case .endOfDay:
            return "Still time for a tiny save 🌙"
        case .discovery:
            return "Try the lazy log lane 📸"
        }
    }

    var body: String {
        switch self {
        case .breakfast:
            return "Tiny breakfast check: say it, type it, or snap it before the coffee brain takes over ☕️"
        case .lunch:
            return "What did lunch look like? A quick voice note totally counts."
        case .dinner:
            return "Future-you loves a complete log. Add dinner while it is still fresh ✨"
        case .endOfDay:
            return "One sentence beats a blank day. Drop in the meal you remember and call it a win."
        case .discovery:
            return "Voice, text, or camera — pick the least annoying one and let Amy do the math."
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast:
            return "sunrise.fill"
        case .lunch:
            return "sun.max.fill"
        case .dinner:
            return "moon.fill"
        case .endOfDay:
            return "clock.badge.exclamationmark.fill"
        case .discovery:
            return "camera.fill"
        }
    }

    var categoryIdentifier: String {
        switch self {
        case .breakfast, .lunch, .dinner:
            return FoodNotificationCategory.mealReminder
        case .endOfDay:
            return FoodNotificationCategory.engagement
        case .discovery:
            return FoodNotificationCategory.discovery
        }
    }

    var destination: FoodNotificationDestination {
        switch self {
        case .breakfast, .lunch, .dinner, .endOfDay:
            return .voice
        case .discovery:
            return .camera
        }
    }
}

enum AdminNotificationDebugService {
    enum Result: Equatable {
        case scheduled
        case denied
        case failed(String)
    }

    static func trigger(_ kind: AdminTestNotificationKind, delay: TimeInterval = 1) async -> Result {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                guard granted else { return .denied }
            } catch {
                return .failed(error.localizedDescription)
            }
        case .denied:
            return .denied
        @unknown default:
            return .failed("Unsupported notification authorization state.")
        }

        let content = UNMutableNotificationContent()
        content.title = "[Test] \(kind.title)"
        content.body = kind.body
        content.sound = .default
        content.categoryIdentifier = kind.categoryIdentifier
        content.userInfo = [
            "source": "admin-notification-debug",
            "kind": kind.rawValue,
            "destination": kind.destination.rawValue
        ]

        let request = UNNotificationRequest(
            identifier: "food-app.admin.test.\(kind.rawValue).\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )

        do {
            try await center.add(request)
            return .scheduled
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
