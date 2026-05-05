import Combine
import Foundation
import SwiftUI

/// Save state shared by all profile editor screens (Body / Diet / Targets).
enum ProfileSaveStatus: Equatable {
    case idle
    case saving
    case saved
    case failed(String)
}

/// Shared editing state for the profile editor screens reachable from the
/// bento dashboard (Body, Diet, Targets). Mirrors the load-once + 500ms
/// debounced auto-save flow the legacy `HomeProfileScreen` Form uses, so
/// drafts edited in either context follow the same persistence path.
///
/// Created at the bento level (`HomeProfileBentoScreen` holds it as a
/// `@StateObject` and injects via environment), so all editor screens
/// reachable from the bento share the same draft. HomeProfileScreen
/// continues to use its own `@State draft` for now — eventual
/// consolidation is a follow-up refactor.
///
/// Note: this class is intentionally non-isolated. Marking it (or any of
/// its methods) `@MainActor` breaks the `ObservableObject` conformance —
/// the synthesized `objectWillChange` requirement is non-isolated by
/// protocol definition and conflicts with main-actor isolation. Mutations
/// of `@Published` properties happen via SwiftUI bindings (already on
/// main) and via `Task { @MainActor in ... }` closures inside the save
/// pipeline, so the actual writes hit main without isolating the class.
final class ProfileDraftStore: ObservableObject {
    @Published var draft = OnboardingDraft()
    @Published var saveStatus: ProfileSaveStatus = .idle

    private var hasLoadedDraft = false
    private var saveTask: Task<Void, Never>?
    private var savedResetTask: Task<Void, Never>?

    /// Loads the latest profile from disk + the API, merging into the
    /// in-memory draft. Idempotent — subsequent calls are no-ops.
    func loadIfNeeded(appStore: AppStore) async {
        guard !hasLoadedDraft else { return }
        hasLoadedDraft = true
        appStore.refreshHealthAuthorizationState()
        if let persisted = OnboardingPersistence.load() {
            draft = persisted.draft
        }
        if let profile = try? await appStore.apiClient.getOnboardingProfile() {
            draft = OnboardingDraft(
                profile: profile,
                accountProvider: appStore.authSessionStore.session?.provider
            )
        }
        draft.migrateLegacyBaselineTouchStateIfNeeded()
        draft.connectHealth = appStore.isHealthSyncEnabled
    }

    /// Schedules an auto-save 500 ms after the most recent draft mutation.
    /// Posts `.profileDraftSaved` on success so other surfaces (the bento
    /// tile data fetch, for instance) can refresh.
    func triggerDebouncedSave(immediate: Bool = false, appStore: AppStore) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
            }
            OnboardingPersistence.save(draft: draft, route: .ready)
            guard
                draft.hasBaselineValues,
                let goal = draft.goal,
                let activity = draft.activity
            else { return }
            if draft.preferences.isEmpty {
                draft.preferences = [.noPreference]
            }

            let request = OnboardingRequest(
                goal: goal,
                dietPreference: dietPreferencePayload,
                allergies: draft.allergies.map(\.rawValue).sorted(),
                units: draft.units ?? .imperial,
                activityLevel: activity.apiValue,
                timezone: TimeZone.current.identifier,
                age: Int(draft.ageValue.rounded()),
                sex: (draft.sex ?? .other).rawValue,
                heightCm: draft.heightInCm,
                weightKg: draft.weightInKg,
                pace: (draft.pace ?? .balanced).rawValue,
                activityDetail: draft.activity?.rawValue
            )
            saveStatus = .saving
            do {
                let response = try await appStore.apiClient.submitOnboarding(request)
                draft.savedCalorieTarget = response.calorieTarget
                draft.savedMacroTargets = response.macroTargets
                OnboardingPersistence.save(draft: draft, route: .ready)
                appStore.setError(nil)
                saveStatus = .saved
                NotificationCenter.default.post(name: .profileDraftSaved, object: nil)
                savedResetTask?.cancel()
                savedResetTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    saveStatus = .idle
                }
            } catch is CancellationError {
                // ignore
            } catch {
                if appStore.handleAuthFailureIfNeeded(error) {
                    saveStatus = .failed(L10n.authSessionExpired)
                } else {
                    let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    saveStatus = .failed(msg)
                }
            }
        }
    }

    func togglePreference(_ preference: PreferenceChoice) {
        if draft.preferences.contains(preference) {
            draft.preferences.remove(preference)
            if draft.preferences.filter({ $0 != .noPreference }).isEmpty {
                draft.preferences = [.noPreference]
            }
        } else {
            if preference == .noPreference {
                draft.preferences = [.noPreference]
            } else {
                draft.preferences.remove(.noPreference)
                draft.preferences.insert(preference)
            }
        }
    }

    func toggleAllergy(_ allergy: AllergyChoice) {
        if draft.allergies.contains(allergy) {
            draft.allergies.remove(allergy)
        } else {
            draft.allergies.insert(allergy)
        }
    }

    // MARK: - Bindings

    var goalBinding: Binding<GoalOption?> {
        Binding(get: { self.draft.goal }, set: { self.draft.goal = $0 })
    }

    var activityBinding: Binding<ActivityChoice?> {
        Binding(get: { self.draft.activity }, set: { self.draft.activity = $0 })
    }

    var paceBinding: Binding<PaceChoice?> {
        Binding(get: { self.draft.pace }, set: { self.draft.pace = $0 })
    }

    var sexBinding: Binding<SexOption?> {
        Binding(
            get: { self.draft.sex },
            set: { newValue in
                self.draft.sex = newValue
                self.draft.baselineTouchedSex = true
            }
        )
    }

    var unitsBinding: Binding<UnitsOption> {
        Binding(
            get: { self.draft.units ?? .imperial },
            set: { self.draft.setUnitsPreservingBaseline($0) }
        )
    }

    var ageIntBinding: Binding<Int> {
        Binding(
            get: { Int(self.draft.ageValue) },
            set: { newValue in
                self.draft.ageValue = Double(newValue)
                self.draft.baselineTouchedAge = true
            }
        )
    }

    func preferenceToggleBinding(_ preference: PreferenceChoice) -> Binding<Bool> {
        Binding(
            get: { self.draft.preferences.contains(preference) },
            set: { _ in self.togglePreference(preference) }
        )
    }

    func allergyToggleBinding(_ allergy: AllergyChoice) -> Binding<Bool> {
        Binding(
            get: { self.draft.allergies.contains(allergy) },
            set: { _ in self.toggleAllergy(allergy) }
        )
    }

    // MARK: - Display helpers

    var heightLabel: String {
        if (draft.units ?? .imperial) == .metric {
            return "\(Int(draft.heightMetricValue)) cm"
        }
        let h = draft.imperialHeightFeetInches
        return "\(h.feet)' \(h.inches)\""
    }

    var weightLabel: String {
        let unitLabel = (draft.units ?? .imperial) == .metric ? "kg" : "lbs"
        return "\(Int(draft.weightValue)) \(unitLabel)"
    }

    private var dietPreferencePayload: String {
        if draft.preferences.isEmpty || draft.preferences.contains(.noPreference) {
            return "no_preference"
        }
        return draft.preferences.map(\.rawValue).sorted().joined(separator: ",")
    }

    private func preferenceSymbol(for preference: PreferenceChoice) -> String {
        switch preference {
        case .highProtein:   return "bolt.fill"
        case .vegetarian:    return "leaf"
        case .vegan:         return "leaf.fill"
        case .pescatarian:   return "fish"
        case .lowCarb:       return "minus.circle.fill"
        case .keto:          return "bolt.circle.fill"
        case .glutenFree:    return "checkmark.circle.fill"
        case .dairyFree:     return "drop.fill"
        case .halal:         return "moon.fill"
        case .lowSodium:     return "heart.text.square.fill"
        case .mediterranean: return "sun.max.fill"
        case .noPreference:  return "fork.knife"
        }
    }
}

extension Notification.Name {
    /// Posted by `ProfileDraftStore` after a successful auto-save. Bento
    /// tile data sources can listen and re-fetch their projections.
    static let profileDraftSaved = Notification.Name("profileDraftSaved")
}
