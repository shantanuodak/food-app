import Foundation
import UserNotifications

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
///   `MindfulPauseSheet` on home appear)
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
    static let snackingNudge = "food-app.snacking.nudge"
    static let consistencyLunch = "food-app.consistency.lunch"
    static let consistencyDinner = "food-app.consistency.dinner"

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
                FoodAppNotificationIdentifier.consistencyDinner
            ]
        )
    }

    /// The single entry point — call after challenge changes, after permission
    /// grant, and on app launch. Idempotent.
    func reconcile(challenge: ChallengeChoice?, authState: UNAuthorizationStatus) async {
        cancelAll()

        guard authState == .authorized || authState == .provisional else { return }
        guard let challenge else { return }

        switch challenge {
        case .snacking:
            await schedule(
                identifier: FoodAppNotificationIdentifier.snackingNudge,
                title: "Mindful moment",
                body: "What does your body actually want right now?",
                hour: 21,
                minute: 0
            )

        case .inconsistentMeals:
            await schedule(
                identifier: FoodAppNotificationIdentifier.consistencyLunch,
                title: "Lunch check-in",
                body: "Anything to log so far today?",
                hour: 12,
                minute: 30
            )
            await schedule(
                identifier: FoodAppNotificationIdentifier.consistencyDinner,
                title: "Day's almost done",
                body: "Log what you ate when you have a sec.",
                hour: 19,
                minute: 30
            )

        case .emotionalEating, .portionControl, .eatingOut:
            // Handled in-app or by the parse flow itself.
            break
        }
    }

    private func schedule(
        identifier: String,
        title: String,
        body: String,
        hour: Int,
        minute: Int
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            // Schedule failures are non-fatal — user can still log normally.
        }
    }
}
