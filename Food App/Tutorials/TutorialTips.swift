import Foundation
import SwiftUI
import TipKit

/// First-launch tutorial tips for the home screen, using TipKit (iOS 17+).
///
/// Three tips fire in sequence the first time a user lands on the home
/// screen after onboarding:
///
///   1. `LogWithPhotoTip` — anchored to the camera button.
///   2. `LogWithVoiceTip` — anchored to the mic button. Shows after the
///      photo tip is dismissed (or its display threshold is met).
///   3. `SwipeBetweenDaysTip` — anchored to the title at the top.
///      Shows after the user has actually used the app at least once
///      (i.e. has a saved log) so they have a reason to navigate days.
///
/// Each tip dismisses permanently once the user either taps it, taps the
/// anchored button, or — for the day-swipe tip — successfully swipes.
/// TipKit handles persistence automatically; we just call `invalidate(...)`
/// on the relevant interactions.
///
/// Why TipKit instead of custom overlays:
/// - Built-in dismissal persistence (no custom `UserDefaults` key).
/// - Native iOS visual language, accessibility, and reduced-motion support.
/// - Declarative display rules via `Rule` / event-based gating.
/// - Free, on-device, no backend involvement.
///
/// Configuration is done once at app launch via `Tips.configure()` —
/// see `Food_AppApp.swift`.

// MARK: - Events

/// User has tapped the photo button at least once. Used to retire the
/// photo tip even if the user dismisses without tapping the popover.
@MainActor
enum TutorialEvents {
    static let photoButtonTapped = Tips.Event(id: "tutorial.photoButtonTapped")
    static let micButtonTapped = Tips.Event(id: "tutorial.micButtonTapped")
    /// Fired when the user has at least one saved log — implies they've
    /// successfully completed a meal flow at some point. Used to gate the
    /// day-swipe tip so we don't show it before the user has any data
    /// worth navigating between.
    static let firstSaveCompleted = Tips.Event(id: "tutorial.firstSaveCompleted")
    /// Fired when the user actually swipes between days for the first
    /// time. Used to dismiss the day-swipe tip permanently.
    static let firstDaySwipeCompleted = Tips.Event(id: "tutorial.firstDaySwipeCompleted")
}

// MARK: - Tips

/// Tip 1: anchored to the photo button on the bottom dock.
struct LogWithPhotoTip: Tip {
    var id: String { "tutorial.logWithPhoto" }

    var title: Text {
        Text("Log a meal with a photo")
    }

    var message: Text? {
        Text("Snap your plate. We'll estimate calories and macros.")
    }

    var image: Image? {
        Image(systemName: "camera.fill")
    }

    /// Show until the user has tapped the photo button at least once.
    var rules: [Rule] {
        [
            #Rule(TutorialEvents.photoButtonTapped) { event in
                event.donations.donatedWithin(.week).count == 0
            }
        ]
    }
}

/// Tip 2: anchored to the mic button on the bottom dock.
struct LogWithVoiceTip: Tip {
    var id: String { "tutorial.logWithVoice" }

    var title: Text {
        Text("Or just say it")
    }

    var message: Text? {
        Text("Tap the mic and speak — we'll parse the rest.")
    }

    var image: Image? {
        Image(systemName: "mic.fill")
    }

    /// Show after the photo tip has been retired (so the two don't fire
    /// simultaneously and crowd the dock), and until the user has tapped
    /// the mic button.
    var rules: [Rule] {
        [
            #Rule(TutorialEvents.photoButtonTapped) { event in
                event.donations.donatedWithin(.week).count > 0
            },
            #Rule(TutorialEvents.micButtonTapped) { event in
                event.donations.donatedWithin(.week).count == 0
            }
        ]
    }
}

/// Tip 3: anchored to the home-screen title.
///
/// Gated on the user having logged at least one meal — there's no point
/// teaching navigation across days when the user has no past days to
/// navigate to.
struct SwipeBetweenDaysTip: Tip {
    var id: String { "tutorial.swipeBetweenDays" }

    var title: Text {
        Text("Swipe to change days")
    }

    var message: Text? {
        Text("Swipe left or right anywhere on this screen to jump between days.")
    }

    var image: Image? {
        Image(systemName: "calendar")
    }

    /// Show when the user has at least one saved log AND has not yet
    /// swiped between days. Once they swipe, retire the tip permanently.
    var rules: [Rule] {
        [
            #Rule(TutorialEvents.firstSaveCompleted) { event in
                event.donations.donatedWithin(.week).count > 0
            },
            #Rule(TutorialEvents.firstDaySwipeCompleted) { event in
                event.donations.donatedWithin(.week).count == 0
            }
        ]
    }
}
