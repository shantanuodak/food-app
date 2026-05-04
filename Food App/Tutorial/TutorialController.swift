import Foundation
import SwiftUI
import Combine

/// Drives the first-launch tutorial. Owns the "completed" flag in
/// UserDefaults so the tutorial fires exactly once per install.
///
/// Combine import is explicit (not just relied on via SwiftUI's
/// re-exports) because `@MainActor` + `@Published` + `ObservableObject`
/// resolution can fail otherwise on Swift 6 build modes — the protocol
/// witness for `objectWillChange` needs `Combine.ObservableObject`
/// directly visible.
///
/// Usage:
///
///   @StateObject private var tutorialController = TutorialController()
///   ...
///   .sheet(isPresented: $tutorialController.isPresented) {
///       TutorialOverlay(controller: tutorialController)
///   }
///   .onAppear { tutorialController.startIfNeeded() }
///
/// The controller is intentionally simple — no internal step state.
/// The TabView in `TutorialOverlay` owns the visible-page index; the
/// controller just toggles `isPresented` and persists the completion
/// flag when the user finishes or skips.
@MainActor
final class TutorialController: ObservableObject {
    @Published var isPresented: Bool = false

    private let defaults: UserDefaults
    private let completedKey = "tutorial.firstLaunch.completed.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True once the tutorial has been finished or skipped at least once.
    var hasCompleted: Bool {
        defaults.bool(forKey: completedKey)
    }

    /// Auto-show on first home appearance per install. Idempotent — safe
    /// to call from multiple `.onAppear` hooks; only opens if not yet
    /// completed AND not already presenting.
    func startIfNeeded() {
        guard !hasCompleted, !isPresented else { return }
        // Defer one runloop tick so a sheet doesn't try to present before
        // the underlying view's transition settles.
        DispatchQueue.main.async { [weak self] in
            self?.isPresented = true
        }
    }

    /// Called from inside the sheet on the final "Done" tap or any skip.
    /// Persists completion + dismisses.
    func finish() {
        defaults.set(true, forKey: completedKey)
        isPresented = false
    }

    /// Test/debug helper — wipe the completion flag so the tutorial
    /// re-fires on next launch. Wired up via the Admin section in Profile
    /// for QA, not user-facing.
    func resetForTesting() {
        defaults.removeObject(forKey: completedKey)
    }
}
