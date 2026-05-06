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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Title stays fixed — doesn't move during day swipe
                    Text("What did you eat today?")
                        .font(.custom("InstrumentSerif-Regular", size: 28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.00, green: 0.62, blue: 0.20),
                                    Color(red: 0.90, green: 0.36, blue: 0.10)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)

                    // Food rows + status slide with the swipe animation
                    composeEntryContent
                        .modifier(DaySwipeOffsetModifier(offset: dayTransitionOffset))
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .safeAreaInset(edge: .bottom) {
                // Floating glass card surfacing the most recent flagged meal.
                // Bottom padding clears the mic/camera dock that lives in the
                // outer `HomeTabShellView` ZStack (60pt buttons + 16pt dock
                // padding ≈ 92pt of room).
                RecentFlaggedMealCard(
                    logs: dayLogs?.logs ?? [],
                    dismissedLogIds: $dismissedInsightLogIds
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 92)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 15, coordinateSpace: .local)
                    .onChanged { value in
                        let dx = abs(value.translation.width)
                        let dy = abs(value.translation.height)

                        // Lock axis on first meaningful movement
                        if swipeAxis == .undecided && (dx > 8 || dy > 8) {
                            swipeAxis = dx > dy ? .horizontal : .vertical
                        }

                        guard swipeAxis == .horizontal else { return }

                        // Direct assignment — no animation wrapper needed during drag.
                        // The DaySwipeOffsetModifier + drawingGroup handles smooth rendering.
                        dayTransitionOffset = value.translation.width * 0.35
                    }
                    .onEnded { value in
                        let axis = swipeAxis
                        swipeAxis = .undecided

                        guard axis == .horizontal else {
                            dayTransitionOffset = 0
                            return
                        }
                        handleSwipeTransition(value)
                    }
            )
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                focusComposerInputFromBackgroundTap()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                topHeaderStrip
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
            }
            .sheet(isPresented: $isCalendarPresented) {
                MainLoggingCalendarSheet(
                    selectedDate: summaryDateSelectionBinding,
                    onToday: {
                        Task { @MainActor in
                            await transitionToSummaryDate(Calendar.current.startOfDay(for: Date()))
                        }
                        isCalendarPresented = false
                    }
                )
            }
            .sheet(isPresented: $isProfilePresented) {
                HomeProfileBentoScreen()
                    .environmentObject(appStore)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
            .sheet(isPresented: $isNutritionSummaryPresented) {
                nutritionSummarySheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isStreakDrawerPresented) {
                HomeStreakDrawerView()
                    .environmentObject(appStore)
                    .presentationDetents([.fraction(0.8), .large])
                    .presentationDragIndicator(.visible)
            }
            .padding()
            .onChange(of: rowTextSignature) { _, _ in
                if suppressDebouncedParseOnce {
                    suppressDebouncedParseOnce = false
                    return
                }
                if latestParseInputKind == "image" {
                    clearImageContext()
                }
                if !trimmedNoteText.isEmpty, inputMode != .text {
                    inputMode = .text
                }
                scheduleDebouncedParse(for: noteText)
            }
            .onChange(of: inputMode) { oldMode, newMode in
                // Skip when handleCameraSourceSelection itself flipped the
                // mode to .camera — it already presents the custom camera.
                if newMode == .camera, oldMode != .camera, !isCustomCameraPresented, !isImagePickerPresented {
                    handleCameraSourceSelection(.takePicture)
                } else if newMode == .voice {
                    handleVoiceModeTapped()
                }
            }
            .onChange(of: selectedSummaryDate) { oldValue, newValue in
                let clamped = clampedSummaryDate(newValue)
                if !Calendar.current.isDate(clamped, inSameDayAs: newValue) {
                    selectedSummaryDate = clamped
                    return
                }
                // Only reset parse state when actually moving to a different calendar day
                if !Calendar.current.isDate(oldValue, inSameDayAs: newValue) {
                    if dateTransitionResetHandled {
                        dateTransitionResetHandled = false
                    } else {
                        protectDraftRowsForDateChange()
                        resetActiveParseStateForDateChange()
                    }
                }
                refreshDaySummary()
                refreshDayLogs()
            }
            .onAppear {
                saveCoordinator.configure(
                    apiClient: appStore.apiClient,
                    imageStorageService: appStore.imageStorageService,
                    deferredImageUploadStore: appStore.deferredImageUploadStore,
                    persistence: HomePendingSavePersistence(defaults: defaults),
                    telemetry: saveAttemptTelemetry
                )
                parseCoordinator.configure(
                    apiClient: appStore.apiClient,
                    saveCoordinator: saveCoordinator
                )
                restorePendingSaveContextIfNeeded()
                hydrateVisibleDayLogsFromDiskIfNeeded()
                bootstrapAuthenticatedHomeIfNeeded()
                // Surface the mindful-pause sheet once per day for emotional-eating users.
                if appStore.selectedChallenge == .emotionalEating, MindfulPauseGate.shouldShow() {
                    isMindfulPausePresented = true
                }
                // First-launch tutorial — no-op after the first run, the
                // controller persists its completion flag in UserDefaults.
                tutorialController.startIfNeeded()
            }
            .sheet(isPresented: $tutorialController.isPresented) {
                TutorialOverlay(controller: tutorialController)
            }
            .onChange(of: appStore.isSessionRestored) { _, ready in
                guard ready else { return }
                hydrateVisibleDayLogsFromDiskIfNeeded()
                bootstrapAuthenticatedHomeIfNeeded()
            }
            .onDisappear {
                debounceTask?.cancel()
                parseTask?.cancel()
                cancelAutoSaveTask()
                prefetchTask?.cancel()
                initialHomeBootstrapTask?.cancel()
                unresolvedRetryTask?.cancel()
                // Drop any pending PATCH tasks; inputRows state is cleared
                // on the next load anyway.
                for task in pendingPatchTasks.values { task.cancel() }
                pendingPatchTasks.removeAll()
                for task in pendingDeleteTasks.values { task.cancel() }
                pendingDeleteTasks.removeAll()
                for task in dateChangeDraftTasks.values { task.cancel() }
                dateChangeDraftTasks.removeAll()
                clearParseSchedulerState()
                parseCoordinator.clearAll()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCameraFromTabBar)) { _ in
                // Tap on the dock camera button → straight to the custom camera
                // (no action sheet). The camera's bottom-left album icon
                // handles "from photo library" once the user is inside it.
                handleCameraSourceSelection(.takePicture)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openVoiceFromTabBar)) { _ in
                inputMode = .voice
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNutritionSummaryFromTabBar)) { _ in
                refreshNutritionStateForVisibleDay()
                isNutritionSummaryPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutritionProgressDidChange)) { notification in
                refreshNutritionStateAfterProgressChange(notification)
                refreshCurrentStreak()
            }
            .sheet(isPresented: $isDetailsDrawerPresented) {
                detailsDrawer
            }
            .sheet(isPresented: $isImagePickerPresented) {
                HomeImagePicker(
                    sourceType: imagePickerSourceType,
                    onImagePicked: { image in
                        Task {
                            await handlePickedImage(image)
                        }
                    },
                    onCancel: {
                        inputMode = .text
                        selectedCameraSource = nil
                    }
                )
            }
            .fullScreenCover(isPresented: $isMindfulPausePresented) {
                MindfulPauseSheet(
                    onContinueLogging: {
                        MindfulPauseGate.markShown()
                        isMindfulPausePresented = false
                    },
                    onSkipForToday: {
                        MindfulPauseGate.markShown()
                        isMindfulPausePresented = false
                    }
                )
            }
            .fullScreenCover(isPresented: $isCustomCameraPresented) {
                CameraView(
                    onImageCaptured: { image in
                        isCustomCameraPresented = false
                        inputMode = .text
                        selectedCameraSource = nil
                        cameraDrawerImage = image
                        cameraDrawerState = .analyzing(image)
                        isCameraAnalysisSheetPresented = true
                        Task { await parseAndUpdateDrawer(image) }
                    },
                    onOpenPhotoLibrary: {
                        // After camera dismisses, open photo library
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            handleCameraSourceSelection(.photo)
                        }
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(item: $selectedRowDetails) { details in
                rowCalorieDetailsSheet(details)
            }
            .sheet(isPresented: $isCameraAnalysisSheetPresented, onDismiss: {
                cameraDrawerState = .idle
                cameraDrawerImage = nil
            }) {
                CameraResultDrawerView(
                    state: cameraDrawerState,
                    onLogIt: {
                        handleDrawerLogIt()
                    },
                    onDiscard: {
                        isCameraAnalysisSheetPresented = false
                    },
                    onRetry: {
                        if let image = cameraDrawerImage {
                            cameraDrawerState = .analyzing(image)
                            Task { await parseAndUpdateDrawer(image) }
                        }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
            .overlay(alignment: .bottom) {
                if isVoiceOverlayPresented {
                    VoiceRecordingOverlay(
                        transcribedText: speechService.transcribedText,
                        isListening: speechService.isListening,
                        audioLevel: speechService.audioLevel,
                        onCancel: {
                            speechService.stopListening()
                            setVoiceOverlayPresented(false)
                            inputMode = .text
                        },
                        onSilenceTimeout: {
                            speechService.stopListening()
                            setVoiceOverlayPresented(false)
                            inputMode = .text
                            parseInfoMessage = "No speech detected. Try again."
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                if parseInfoMessage == "No speech detected. Try again." {
                                    withAnimation { parseInfoMessage = nil }
                                }
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: isVoiceOverlayPresented)
                }
            }
            .overlay(alignment: .bottom) {
                if !isVoiceOverlayPresented {
                    bottomActionDock
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isVoiceOverlayPresented)
            .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .onChange(of: speechService.isListening) { wasListening, isNowListening in
                guard wasListening && !isNowListening && isVoiceOverlayPresented else { return }
                let finalText = speechService.transcribedText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                setVoiceOverlayPresented(false)

                guard !finalText.isEmpty else {
                    parseInfoMessage = "No speech detected. Try again."
                    inputMode = .text
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if parseInfoMessage == "No speech detected. Try again." {
                            withAnimation { parseInfoMessage = nil }
                        }
                    }
                    return
                }
                insertVoiceTranscription(finalText)
            }
            .onChange(of: speechService.audioLevel) { _, newLevel in
                guard isVoiceOverlayPresented else { return }
                handleVoiceHaptic(level: newLevel)
            }
            .onChange(of: speechService.error) { _, newError in
                guard let newError else { return }
                parseError = newError
                setVoiceOverlayPresented(false)
                inputMode = .text
            }
        }
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
