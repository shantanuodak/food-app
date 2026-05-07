import SwiftUI
import Foundation
import PhotosUI
import UIKit

struct MainLoggingShellView: View {
    @EnvironmentObject var appStore: AppStore
    @Environment(\.colorScheme) var colorScheme

    @StateObject var speechService = SpeechRecognitionService()
    @StateObject var saveCoordinator = SaveCoordinator()
    @StateObject var parseCoordinator = ParseCoordinator()
    @StateObject var tutorialController = TutorialController()
    @State var isVoiceOverlayPresented = false
    @State var voiceOverlayPhase: VoiceRecordingOverlay.Phase = .listening
    @State var voiceHandoffTask: Task<Void, Never>?
    @State var voiceRevealTask: Task<Void, Never>?
    @State var voiceCaptureCancelRequested = false
    @State var inputRows: [HomeLogRow] = [.empty()]
    @State var parseInFlightCount = 0
    @State var parseRequestSequence = 0
    @State var parseResult: ParseLogResponse?
    @State var parseError: String?
    @State var parseInfoMessage: String?
    @State var debounceTask: Task<Void, Never>?
    @State var parseTask: Task<Void, Never>?
    @State var activeParseRowID: UUID?
    @State var queuedParseRowIDs: [UUID] = []
    @State var inFlightParseSnapshot: InFlightParseSnapshot?
    @State var pendingFollowupRequested = false
    @State var latestQueuedNoteText: String?
    @State var autoSaveTask: Task<Void, Never>?
    @State var unresolvedRetryTask: Task<Void, Never>?
    @State var unresolvedRetryCount = 0
    @State var isDetailsDrawerPresented = false
    @State var editableItems: [EditableParsedItem] = []
    @State var isSaving = false
    @State var isSubmittingRestoredPendingSaves = false
    @State var saveError: String?
    @State var saveSuccessMessage: String?
    @State var pendingSaveRequest: SaveLogRequest?
    @State var pendingSaveFingerprint: String?
    @State var pendingSaveIdempotencyKey: UUID?
    @State var pendingSaveQueue: [PendingSaveQueueItem] = []
    @State var isEscalating = false
    @State var escalationError: String?
    @State var escalationInfoMessage: String?
    @State var escalationBlockedCode: String?
    @State var selectedSummaryDate = Date()
    @State var daySummary: DaySummaryResponse?
    @State var isLoadingDaySummary = false
    @State var daySummaryError: String?
    @State var dayLogs: DayLogsResponse?
    @State var isLoadingDayLogs = false
    /// Per-saved-log-id dismissal state for `HomeMealInsightCard`.
    /// Persisted in UserDefaults so dismissals survive app launches and day swipes.
    @State var dismissedInsightLogIds: Set<String> = RecentFlaggedMealCard.loadDismissedLogIds()
    /// Once-per-day in-app pause for users whose biggest challenge is emotional eating.
    @State var isMindfulPausePresented = false
    /// In-memory cache for adjacent days — keyed by "yyyy-MM-dd" date string.
    @State var dayCacheSummary: [String: DaySummaryResponse] = [:]
    @State var dayCacheLogs: [String: DayLogsResponse] = [:]
    @State var prefetchTask: Task<Void, Never>?
    @State var initialHomeBootstrapTask: Task<Void, Never>?
    @State var hasBootstrappedAuthenticatedHome = false
    /// Per-row debounced PATCH task. A key is added when the client-side
    /// quantity fast path scales a row that already has a `serverLogId`; the
    /// task fires after `patchDebounceNs` and issues a `PATCH /v1/logs/:id`
    /// with the row's current items. Cancelled & replaced on each keystroke
    /// so a user adjusting 3 → 4 → 5 → 6 only results in one network call.
    @State var pendingPatchTasks: [UUID: Task<Void, Never>] = [:]
    @State var pendingDeleteTasks: [UUID: Task<Void, Never>] = [:]
    @State var dateChangeDraftTasks: [UUID: Task<Void, Never>] = [:]
    @State var preservedDraftRowsByDate: [String: [PreservedDateDraftRow]] = [:]
    @State var dateTransitionResetHandled = false
    @State var locallyDeletedPendingRowIDs: Set<UUID> = []
    @State var locallyDeletedPendingSaveKeys: Set<String> = []
    let patchDebounceNs: UInt64 = 1_500_000_000
    @FocusState var isNoteEditorFocused: Bool
    @State var flowStartedAt: Date?
    @State var draftLoggedAt: Date?
    @State var lastTimeToLogMs: Double?
    @State var lastAutoSavedContentFingerprint: String?
    @State var inputMode: HomeInputMode = .text
    @State var detailsDrawerMode: DetailsDrawerMode = .full
    @State var selectedRowDetails: RowCalorieDetails?
    @State var rowDetailsPendingDeleteID: UUID?
    @State var isRowDetailsDeleteConfirmationPresented = false
    /// Per-(row, itemIndex) retry tracking for unresolved placeholders.
    /// Key format: "<rowUUID>-<itemIndex>". Drives the in-flight spinner
    /// on Retry buttons in the drawer + dedupes concurrent taps.
    @State var retryingPlaceholderKeys: Set<String> = []
    @State var activeEditingRowID: UUID?
    @State var selectedCameraSource: CameraInputSource?
    @State var isImagePickerPresented = false
    @State var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State var pendingImageData: Data?
    @State var pendingImagePreviewData: Data?
    @State var pendingImageMimeType: String?
    @State var pendingImageStorageRef: String?
    /// Image data captured for post-save retry when the inline upload during
    /// `prepareSaveRequestForNetwork` fails. The food_log lands without an
    /// image_ref; once it's saved we kick off a background upload + PATCH.
    /// Keyed by idempotency key so concurrent saves don't clobber each other.
    @State var deferredImageUploads: [String: Data] = [:]
    @State var latestParseInputKind: String = "text"
    @State var suppressDebouncedParseOnce = false
    @State var isCalendarPresented = false
    @State var isProfilePresented = false
    @State var isNutritionSummaryPresented = false
    @State var currentFoodLogStreak: Int?
    @State var isLoadingFoodLogStreak = false
    @State var isStreakDrawerPresented = false
    @State var isKeyboardVisible = false
    @State var isSyncInfoPresented = false
    /// Slide direction for day transitions: negative = slide left (going forward), positive = slide right (going back)
    @State var dayTransitionOffset: CGFloat = 0
    /// Locks the swipe direction once determined — prevents fighting with ScrollView vertical scroll
    @State var swipeAxis: SwipeAxis = .undecided
    @State var isCustomCameraPresented = false
    @State var cameraDrawerState: CameraDrawerState = .idle
    @State var cameraDrawerImage: UIImage?
    @State var isCameraAnalysisSheetPresented = false

    @State var autoSavedParseIDs: Set<String> = []
    let defaults = UserDefaults.standard
    let autoSaveDelayNs: UInt64 = 1_500_000_000
    let saveAttemptTelemetry = SaveAttemptTelemetry.shared

    var activeParseSnapshots: [ParseSnapshot] {
        parseCoordinator.snapshots.values.sorted { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt {
                return lhs.capturedAt < rhs.capturedAt
            }
            return lhs.rowID.uuidString < rhs.rowID.uuidString
        }
    }

    var summaryDateSelectionBinding: Binding<Date> {
        Binding(
            get: { selectedSummaryDate },
            set: { newValue in
                Task { @MainActor in
                    await transitionToSummaryDate(newValue)
                }
            }
        )
    }

    static let voiceHapticGenerator = UIImpactFeedbackGenerator(style: .soft)
    @State var lastHapticTime: Date = .distantPast


    /// Retries a deferred image upload after its food log has been saved.
    func scheduleDeferredImageUploadRetry(
        idempotencyKey: UUID,
        logId: String,
        inputKind: String?
    ) {
        let queueKey = idempotencyKey.uuidString.lowercased()
        guard let imageData = deferredImageUploads[queueKey] else { return }
        deferredImageUploads.removeValue(forKey: queueKey)
        let kind = normalizedInputKind(inputKind, fallback: latestParseInputKind)
        let userIDHint = appStore.authSessionStore.session?.userID
        saveCoordinator.scheduleDeferredImageUploadRetry(
            logId: logId,
            imageData: imageData,
            normalizedInputKind: kind,
            userIDHint: userIDHint
        )
    }

}

#Preview {
    MainLoggingShellView()
        .environmentObject(AppStore())
}
