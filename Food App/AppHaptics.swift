import Foundation

#if canImport(UIKit)
import UIKit

@MainActor
enum AppHaptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    private static var lastTickAtByID: [String: TimeInterval] = [:]
    private static var lastTickValueByID: [String: String] = [:]

    static func selection() {
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }

    static func lightImpact(intensity: CGFloat? = nil) {
        lightGenerator.prepare()
        if let intensity {
            lightGenerator.impactOccurred(intensity: intensity)
        } else {
            lightGenerator.impactOccurred()
        }
    }

    static func mediumImpact(intensity: CGFloat? = nil) {
        mediumGenerator.prepare()
        if let intensity {
            mediumGenerator.impactOccurred(intensity: intensity)
        } else {
            mediumGenerator.impactOccurred()
        }
    }

    static func rigidImpact(intensity: CGFloat? = nil) {
        rigidGenerator.prepare()
        if let intensity {
            rigidGenerator.impactOccurred(intensity: intensity)
        } else {
            rigidGenerator.impactOccurred()
        }
    }

    static func softImpact(intensity: CGFloat? = nil) {
        softGenerator.prepare()
        if let intensity {
            softGenerator.impactOccurred(intensity: intensity)
        } else {
            softGenerator.impactOccurred()
        }
    }

    static func success() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.success)
    }

    static func warning() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.warning)
    }

    static func error() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.error)
    }

    static func throttledSelectionTick(
        id: String,
        value: String,
        minimumInterval: TimeInterval = 0.08
    ) {
        let now = CACurrentMediaTime()
        if lastTickValueByID[id] == value {
            return
        }

        defer {
            lastTickAtByID[id] = now
            lastTickValueByID[id] = value
        }

        let lastTickAt = lastTickAtByID[id] ?? .leastNormalMagnitude
        guard now - lastTickAt >= minimumInterval else { return }
        selection()
    }
}
#else
enum AppHaptics {
    static func selection() {}
    static func lightImpact(intensity: CGFloat? = nil) {}
    static func mediumImpact(intensity: CGFloat? = nil) {}
    static func rigidImpact(intensity: CGFloat? = nil) {}
    static func softImpact(intensity: CGFloat? = nil) {}
    static func success() {}
    static func warning() {}
    static func error() {}
    static func throttledSelectionTick(id: String, value: String, minimumInterval: TimeInterval = 0.08) {}
}
#endif
