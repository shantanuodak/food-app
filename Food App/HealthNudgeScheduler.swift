import Foundation
import UserNotifications

/// User preferences for the real-time "smart" health nudges (hydration,
/// protein, movement). iOS-local only — persisted in `UserDefaults`, never
/// synced to the backend. Defaults ON, but nudges only ever schedule once the
/// user has granted notification permission, so we never force a prompt.
struct HealthNudgeSettings: Codable, Equatable {
    /// Master switch. When false, no smart nudges are scheduled regardless of
    /// the per-type toggles below.
    var enabled: Bool
    var hydrationEnabled: Bool
    var proteinEnabled: Bool
    var movementEnabled: Bool
    /// Daily step goal used to decide whether the movement nudge fires. There
    /// is no server-side step goal today, so this lives here with a sensible
    /// default the user can tune.
    var stepGoal: Int
    /// Fallback daily water goal (ml) used only when the backend hasn't set a
    /// hydration goal for the day. ~2 litres.
    var waterGoalFallbackMl: Int

    static let `default` = HealthNudgeSettings(
        enabled: true,
        hydrationEnabled: true,
        proteinEnabled: true,
        movementEnabled: true,
        stepGoal: 8000,
        waterGoalFallbackMl: 2000
    )

    enum CodingKeys: String, CodingKey {
        case enabled
        case hydrationEnabled
        case proteinEnabled
        case movementEnabled
        case stepGoal
        case waterGoalFallbackMl
    }

    init(
        enabled: Bool,
        hydrationEnabled: Bool,
        proteinEnabled: Bool,
        movementEnabled: Bool,
        stepGoal: Int,
        waterGoalFallbackMl: Int
    ) {
        self.enabled = enabled
        self.hydrationEnabled = hydrationEnabled
        self.proteinEnabled = proteinEnabled
        self.movementEnabled = movementEnabled
        self.stepGoal = stepGoal
        self.waterGoalFallbackMl = waterGoalFallbackMl
    }

    // Tolerant decode so adding fields later never wipes a user's saved prefs.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? fallback.enabled
        hydrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .hydrationEnabled) ?? fallback.hydrationEnabled
        proteinEnabled = try container.decodeIfPresent(Bool.self, forKey: .proteinEnabled) ?? fallback.proteinEnabled
        movementEnabled = try container.decodeIfPresent(Bool.self, forKey: .movementEnabled) ?? fallback.movementEnabled
        stepGoal = try container.decodeIfPresent(Int.self, forKey: .stepGoal) ?? fallback.stepGoal
        waterGoalFallbackMl = try container.decodeIfPresent(Int.self, forKey: .waterGoalFallbackMl) ?? fallback.waterGoalFallbackMl
    }

    /// True when at least one nudge type would actually be scheduled.
    var hasAnyActiveNudge: Bool {
        enabled && (hydrationEnabled || proteinEnabled || movementEnabled)
    }
}

/// A point-in-time view of the user's progress toward their daily goals.
/// Built by `AppStore` from live data (day summary, HealthKit steps,
/// hydration summary) and handed to the scheduler. All fields are optional:
/// a `nil` goal/value means "we don't know" and the corresponding nudge is
/// skipped rather than guessed.
struct HealthNudgeSnapshot {
    var proteinConsumed: Double?
    var proteinTargetGrams: Double?

    var waterConsumedMl: Double?
    var waterGoalMl: Double?

    var steps: Double?
    var stepGoal: Double?
    /// Whether step data is actually available (HealthKit authorized + sync on).
    /// Without it we never fire a movement nudge — a flat 0 would be a lie.
    var stepsAvailable: Bool

    static let empty = HealthNudgeSnapshot(
        proteinConsumed: nil,
        proteinTargetGrams: nil,
        waterConsumedMl: nil,
        waterGoalMl: nil,
        steps: nil,
        stepGoal: nil,
        stepsAvailable: false
    )
}

/// One conditional nudge: a time of day, the fraction of the goal the user
/// should have reached by then, and the copy to show if they're behind.
private struct HealthNudgePlan {
    let identifier: String
    let hour: Int
    let minute: Int
    let title: String
    let body: String
    let category: String
    let destination: FoodNotificationDestination
    let kind: String
}

/// Owns the lifecycle of the real-time health nudge `UNNotificationRequest`s.
///
/// iOS local notifications can't run code at fire time, so we *predictively*
/// schedule: at every reconcile (app foreground, after a save, after a health
/// sync, on background refresh) we look at the user's current pace and schedule
/// a one-shot notification for later today **only if** they're currently behind.
/// As the day goes on and the user catches up, the next reconcile cancels the
/// no-longer-warranted nudge. This keeps the nudges honest without a backend.
@MainActor
final class HealthNudgeScheduler {
    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    init(center: UNUserNotificationCenter = .current(), calendar: Calendar = .current) {
        self.center = center
        self.calendar = calendar
    }

    func cancelAll() {
        center.removePendingNotificationRequests(
            withIdentifiers: [
                FoodAppNotificationIdentifier.hydrationMidday,
                FoodAppNotificationIdentifier.hydrationEvening,
                FoodAppNotificationIdentifier.proteinNudge,
                FoodAppNotificationIdentifier.movementNudge
            ]
        )
    }

    /// Cancel stale nudges, then re-schedule today's based on the current
    /// snapshot. Idempotent. `now` is injectable for testing.
    func reconcile(
        authState: UNAuthorizationStatus,
        settings: HealthNudgeSettings,
        snapshot: HealthNudgeSnapshot,
        now: Date = Date()
    ) async {
        cancelAll()
        guard canSchedule(authState), settings.hasAnyActiveNudge else { return }

        for plan in plans(settings: settings, snapshot: snapshot) {
            await schedule(plan, now: now)
        }
    }

    private func plans(settings: HealthNudgeSettings, snapshot: HealthNudgeSnapshot) -> [HealthNudgePlan] {
        var result: [HealthNudgePlan] = []

        // Hydration — two gentle checkpoints. Goal falls back to the user's
        // configured fallback when the backend hasn't set one.
        if settings.hydrationEnabled {
            let goal = positiveOrNil(snapshot.waterGoalMl)
                ?? Double(settings.waterGoalFallbackMl)
            if goal > 0, let consumed = snapshot.waterConsumedMl {
                if consumed < goal * 0.5 {
                    result.append(HealthNudgePlan(
                        identifier: FoodAppNotificationIdentifier.hydrationMidday,
                        hour: 14, minute: 30,
                        title: "Hydration check 💧",
                        body: "You're a little behind on water today. A glass now keeps you on pace — tap to log it.",
                        category: FoodNotificationCategory.healthNudge,
                        destination: .text,
                        kind: "hydration"
                    ))
                }
                if consumed < goal * 0.75 {
                    result.append(HealthNudgePlan(
                        identifier: FoodAppNotificationIdentifier.hydrationEvening,
                        hour: 17, minute: 30,
                        title: "Still time to top up 💧",
                        body: "A bit more water before the evening winds down. Future-you will feel it tomorrow.",
                        category: FoodNotificationCategory.healthNudge,
                        destination: .text,
                        kind: "hydration"
                    ))
                }
            }
        }

        // Protein — one afternoon checkpoint so there's time to course-correct
        // at dinner.
        if settings.proteinEnabled,
           let target = positiveOrNil(snapshot.proteinTargetGrams),
           let consumed = snapshot.proteinConsumed,
           consumed < target * 0.55 {
            let remaining = max(0, Int((target - consumed).rounded()))
            result.append(HealthNudgePlan(
                identifier: FoodAppNotificationIdentifier.proteinNudge,
                hour: 16, minute: 30,
                title: "Protein is lagging 🍗",
                body: "About \(remaining)g of protein left to hit today's goal. Plan a protein-forward dinner — tap to log.",
                category: FoodNotificationCategory.healthNudge,
                destination: .text,
                kind: "protein"
            ))
        }

        // Movement — evening checkpoint, only when we actually have step data.
        if settings.movementEnabled,
           snapshot.stepsAvailable,
           let goal = positiveOrNil(snapshot.stepGoal),
           let steps = snapshot.steps,
           steps < goal * 0.7 {
            let remaining = max(0, Int((goal - steps).rounded()))
            result.append(HealthNudgePlan(
                identifier: FoodAppNotificationIdentifier.movementNudge,
                hour: 18, minute: 30,
                title: "Let's get moving 🚶",
                body: "About \(remaining.formatted()) steps to go. A short walk now closes the gap — every bit counts.",
                category: FoodNotificationCategory.healthNudge,
                destination: .home,
                kind: "movement"
            ))
        }

        return result
    }

    private func schedule(_ plan: HealthNudgePlan, now: Date) async {
        // Build today's fire date with full y/m/d so a non-repeating trigger
        // can only land today (never roll to tomorrow). Skip if already past —
        // we never want a nudge to fire the instant it's scheduled.
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = plan.hour
        components.minute = plan.minute
        components.second = 0
        guard let fireDate = calendar.date(from: components), fireDate > now else { return }

        let triggerComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )

        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.categoryIdentifier = plan.category
        content.userInfo = [
            "source": "local-health-nudge",
            "kind": plan.kind,
            "destination": plan.destination.rawValue
        ]

        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            NSLog("[notifications] health nudge schedule failed %@ %@", plan.identifier, error.localizedDescription)
        }
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

    /// Returns the value only when it's a usable positive number, else nil.
    /// Keeps the plan builder from ever dividing against a zero/absent goal.
    private func positiveOrNil(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
