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
/// Notifications are challenge-driven: depending on which "biggest challenge"
/// the user picked in onboarding (`ChallengeChoice`), the scheduler installs
/// a different fixed-time daily nudge.
///
/// MVP behavior:
/// - `.snacking` → daily 21:00 mindful-snack reminder
/// - `.inconsistentMeals` → daily 12:30 + 19:30 logging check-ins
/// - `.emotionalEating` → no scheduled notification (handled by an in-app
///   `MindfulPauseSheet` when logging starts outside meal windows)
/// - `.portionControl` / `.eatingOut` → no notifications (the in-flow parse
///   feedback already addresses these challenges)
///
/// The scheduler is **idempotent**: calling `reconcile(...)` always cancels
/// every previously-scheduled request first, then re-installs only the ones
/// the current challenge requires. Safe to call from anywhere — onboarding
/// finish, permission grant, app launch, or settings change.
///
/// All identifiers are namespaced under `food-app.*` so future code (or
/// future me) can list / clean / migrate them without ambiguity.
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

    /// The single entry point — call after challenge changes, after permission
    /// grant, and on app launch. Idempotent.
    ///
    /// Production reminders and engagement nudges are server-managed through
    /// APNs so the backend can honor meal windows, no-log checks, template CMS
    /// changes, and delivery de-dupe. The app keeps this reconciler only to
    /// remove stale local requests from older builds and to keep permission
    /// handling in one place.
    func reconcile(
        challenge _: ChallengeChoice?,
        authState _: UNAuthorizationStatus,
        mealReminders _: MealReminderSettings,
        hasLoggedToday _: Bool
    ) async {
        cancelAll()
    }
}
