import SwiftUI
import Foundation
import PhotosUI
import UIKit

struct MainLoggingShellView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var speechService = SpeechRecognitionService()
    @StateObject private var saveCoordinator = SaveCoordinator()
    @StateObject private var parseCoordinator = ParseCoordinator()
    @State private var isVoiceOverlayPresented = false
    @State private var inputRows: [HomeLogRow] = [.empty()]
    @State private var parseInFlightCount = 0
    @State private var parseRequestSequence = 0
    @State private var parseResult: ParseLogResponse?
    @State private var parseError: String?
    @State private var parseInfoMessage: String?
    @State private var debounceTask: Task<Void, Never>?
    @State private var parseTask: Task<Void, Never>?
    @State private var activeParseRowID: UUID?
    @State private var queuedParseRowIDs: [UUID] = []
    @State private var inFlightParseSnapshot: InFlightParseSnapshot?
    @State private var pendingFollowupRequested = false
    @State private var latestQueuedNoteText: String?
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var unresolvedRetryTask: Task<Void, Never>?
    @State private var unresolvedRetryCount = 0
    @State private var isDetailsDrawerPresented = false
    @State private var editableItems: [EditableParsedItem] = []
    @State private var isSaving = false
    @State private var isSubmittingRestoredPendingSaves = false
    @State private var saveError: String?
    @State private var saveSuccessMessage: String?
    @State private var pendingSaveRequest: SaveLogRequest?
    @State private var pendingSaveFingerprint: String?
    @State private var pendingSaveIdempotencyKey: UUID?
    @State private var pendingSaveQueue: [PendingSaveQueueItem] = []
    @State private var isEscalating = false
    @State private var escalationError: String?
    @State private var escalationInfoMessage: String?
    @State private var escalationBlockedCode: String?
    @State private var selectedSummaryDate = Date()
    @State private var daySummary: DaySummaryResponse?
    @State private var isLoadingDaySummary = false
    @State private var daySummaryError: String?
    @State private var dayLogs: DayLogsResponse?
    @State private var isLoadingDayLogs = false
    /// Per-saved-log-id dismissal state for `HomeMealInsightCard`.
    /// Persisted in UserDefaults so dismissals survive app launches and day swipes.
    @State private var dismissedInsightLogIds: Set<String> = RecentFlaggedMealCard.loadDismissedLogIds()
    /// Once-per-day in-app pause for users whose biggest challenge is emotional eating.
    @State private var isMindfulPausePresented = false
    /// In-memory cache for adjacent days — keyed by "yyyy-MM-dd" date string.
    @State private var dayCacheSummary: [String: DaySummaryResponse] = [:]
    @State private var dayCacheLogs: [String: DayLogsResponse] = [:]
    @State private var prefetchTask: Task<Void, Never>?
    @State private var initialHomeBootstrapTask: Task<Void, Never>?
    @State private var hasBootstrappedAuthenticatedHome = false
    /// Per-row debounced PATCH task. A key is added when the client-side
    /// quantity fast path scales a row that already has a `serverLogId`; the
    /// task fires after `patchDebounceNs` and issues a `PATCH /v1/logs/:id`
    /// with the row's current items. Cancelled & replaced on each keystroke
    /// so a user adjusting 3 → 4 → 5 → 6 only results in one network call.
    @State private var pendingPatchTasks: [UUID: Task<Void, Never>] = [:]
    @State private var pendingDeleteTasks: [UUID: Task<Void, Never>] = [:]
    @State private var dateChangeDraftTasks: [UUID: Task<Void, Never>] = [:]
    @State private var preservedDraftRowsByDate: [String: [PreservedDateDraftRow]] = [:]
    @State private var dateTransitionResetHandled = false
    @State private var locallyDeletedPendingRowIDs: Set<UUID> = []
    @State private var locallyDeletedPendingSaveKeys: Set<String> = []
    private let patchDebounceNs: UInt64 = 1_500_000_000
    @FocusState private var isNoteEditorFocused: Bool
    @State private var flowStartedAt: Date?
    @State private var draftLoggedAt: Date?
    @State private var lastTimeToLogMs: Double?
    @State private var lastAutoSavedContentFingerprint: String?
    @State private var inputMode: HomeInputMode = .text
    @State private var detailsDrawerMode: DetailsDrawerMode = .full
    @State private var selectedRowDetails: RowCalorieDetails?
    @State private var rowDetailsPendingDeleteID: UUID?
    @State private var isRowDetailsDeleteConfirmationPresented = false
    /// Per-(row, itemIndex) retry tracking for unresolved placeholders.
    /// Key format: "<rowUUID>-<itemIndex>". Drives the in-flight spinner
    /// on Retry buttons in the drawer + dedupes concurrent taps.
    @State private var retryingPlaceholderKeys: Set<String> = []
    @State private var activeEditingRowID: UUID?
    @State private var selectedCameraSource: CameraInputSource?
    @State private var isImagePickerPresented = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var pendingImageData: Data?
    @State private var pendingImagePreviewData: Data?
    @State private var pendingImageMimeType: String?
    @State private var pendingImageStorageRef: String?
    /// Image data captured for post-save retry when the inline upload during
    /// `prepareSaveRequestForNetwork` fails. The food_log lands without an
    /// image_ref; once it's saved we kick off a background upload + PATCH.
    /// Keyed by idempotency key so concurrent saves don't clobber each other.
    @State private var deferredImageUploads: [String: Data] = [:]
    @State private var latestParseInputKind: String = "text"
    @State private var suppressDebouncedParseOnce = false
    @State private var isCalendarPresented = false
    @State private var isProfilePresented = false
    @State private var isNutritionSummaryPresented = false
    @State private var currentFoodLogStreak: Int?
    @State private var isLoadingFoodLogStreak = false
    @State private var isStreakDrawerPresented = false
    @State private var isKeyboardVisible = false
    @State private var isSyncInfoPresented = false
    /// Slide direction for day transitions: negative = slide left (going forward), positive = slide right (going back)
    @State private var dayTransitionOffset: CGFloat = 0
    /// Locks the swipe direction once determined — prevents fighting with ScrollView vertical scroll
    @State private var swipeAxis: SwipeAxis = .undecided
    @State private var isCustomCameraPresented = false
    @State private var cameraDrawerState: CameraDrawerState = .idle
    @State private var cameraDrawerImage: UIImage?
    @State private var isCameraAnalysisSheetPresented = false

    private enum SwipeAxis {
        case undecided, horizontal, vertical
    }
    // parseRequestIDs that have already been dispatched to auto-save (prevents re-saves).
    @State private var autoSavedParseIDs: Set<String> = []
    private let defaults = UserDefaults.standard
    private let autoSaveDelayNs: UInt64 = 1_500_000_000
    private let saveAttemptTelemetry = SaveAttemptTelemetry.shared

    private var activeParseSnapshots: [ParseSnapshot] {
        parseCoordinator.snapshots.values.sorted { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt {
                return lhs.capturedAt < rhs.capturedAt
            }
            return lhs.rowID.uuidString < rhs.rowID.uuidString
        }
    }

    private enum DetailsDrawerMode {
        case full
        case manualAdd
    }

    private enum CameraInputSource {
        case takePicture
        case photo

        var statusMessage: String {
            switch self {
            case .takePicture:
                return "Captured photo ready for parsing."
            case .photo:
                return "Selected photo ready for parsing."
            }
        }
    }

    private var summaryDateSelectionBinding: Binding<Date> {
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
                HomeProfileScreen()
                    .environmentObject(appStore)
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

    private var bottomActionDock: some View {
        MainLoggingBottomDock(
            shouldShowSyncExceptionPill: shouldShowSyncExceptionPill,
            syncStatusTitle: syncStatusTitle,
            syncStatusExplanation: syncStatusExplanation,
            currentFoodLogStreak: currentFoodLogStreak,
            isLoadingFoodLogStreak: isLoadingFoodLogStreak,
            isKeyboardVisible: isKeyboardVisible,
            isSyncInfoPresented: $isSyncInfoPresented,
            isStreakDrawerPresented: $isStreakDrawerPresented
        )
    }

    private var pendingSyncItemCount: Int {
        let unresolvedQueueItems = unresolvedPendingQueueItems
        var pendingKeys = Set(unresolvedQueueItems.map { pendingSyncKey(for: $0) })
        pendingKeys.formUnion(pendingPatchTasks.keys.map { "patch:\($0.uuidString)" })
        pendingKeys.formUnion(pendingDeleteTasks.keys.map { "delete:\($0.uuidString)" })

        let unsavedVisibleRows = saveError == nil ? inputRows.filter { row in
            guard !row.isSaved else { return false }
            guard !pendingKeys.contains("row:\(row.id.uuidString)") else { return false }
            return row.calories != nil || !row.parsedItems.isEmpty || row.parsedItem != nil
        } : []
        pendingKeys.formUnion(unsavedVisibleRows.map { "row:\($0.id.uuidString)" })
        return pendingKeys.count
    }

    private var shouldShowSyncExceptionPill: Bool {
        saveError != nil && pendingSyncItemCount > 0
    }

    private var syncStatusTitle: String {
        pendingSyncItemCount == 1 ? "1 item waiting" : "\(pendingSyncItemCount) items waiting"
    }

    private var syncStatusExplanation: String {
        "These items are visible here and included in your calories. Sync is retrying in the background."
    }

    private func pendingSyncKey(for item: PendingSaveQueueItem) -> String {
        if let rowID = item.rowID {
            return "row:\(rowID.uuidString)"
        }
        return "key:\(item.idempotencyKey)"
    }

    private var topHeaderStrip: some View {
        MainLoggingTopHeaderStrip(
            firstName: loggedInFirstName,
            dateTitle: todayPillTitle,
            colorScheme: colorScheme,
            isProfilePresented: $isProfilePresented,
            isCalendarPresented: $isCalendarPresented
        )
    }

    private var todayPillTitle: String {
        if Calendar.current.isDateInToday(selectedSummaryDate) {
            return "Today"
        }
        return HomeLoggingDateUtils.topDateFormatter.string(from: selectedSummaryDate)
    }

    private func focusComposerInputFromBackgroundTap() {
        guard !isVoiceOverlayPresented,
              !isDetailsDrawerPresented,
              !isProfilePresented,
              !isCalendarPresented,
              !isNutritionSummaryPresented,
              !isStreakDrawerPresented,
              !isCustomCameraPresented,
              !isCameraAnalysisSheetPresented else {
            return
        }

        inputMode = .text
        NotificationCenter.default.post(name: .focusComposerInputFromBackgroundTap, object: nil)
    }

    private var loggedInFirstName: String? {
        appStore.authSessionStore.session?.displayFirstName
    }

    private func handleSwipeTransition(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        // Use both distance and velocity — a fast flick with short distance should also work
        let velocity = value.predictedEndTranslation.width - value.translation.width

        guard abs(horizontal) >= 30 || abs(velocity) > 200 else {
            // Too small — snap back
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                dayTransitionOffset = 0
            }
            return
        }

        let days = horizontal > 0 ? -1 : 1
        shiftSelectedSummaryDate(byDays: days)
    }

    private func shiftSelectedSummaryDate(byDays days: Int) {
        guard let moved = Calendar.current.date(byAdding: .day, value: days, to: selectedSummaryDate) else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dayTransitionOffset = 0
            }
            return
        }

        let normalized = clampedSummaryDate(moved)
        guard !Calendar.current.isDate(normalized, inSameDayAs: selectedSummaryDate) else {
            // Can't move (e.g. already on today, tried to go forward) — bounce back with a light tap
            let rigidFeedback = UIImpactFeedbackGenerator(style: .rigid)
            rigidFeedback.impactOccurred(intensity: 0.5)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dayTransitionOffset = 0
            }
            return
        }

        // Haptic tick for successful day change
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        // Flush any pending save for the current day BEFORE leaving it, so typed
        // entries don't get lost when the user swipes away mid-debounce.
        Task { @MainActor in
            await flushPendingAutoSaveIfEligible()
            protectDraftRowsForDateChange()

            // Reset transient parse/flow state so it doesn't leak across days.
            resetActiveParseStateForDateChange()

            // Slide content out in swipe direction, then slide new content in from opposite side
            let slideOut: CGFloat = days > 0 ? -120 : 120
            withAnimation(.easeIn(duration: 0.12)) {
                dayTransitionOffset = slideOut
            }

            // After a brief pause, update the date and slide content back from the opposite side
            try? await Task.sleep(nanoseconds: 120_000_000)

            // Pre-apply cached data to prevent flicker during transition
            let dateStr = HomeLoggingDateUtils.summaryRequestFormatter.string(from: normalized)
            if let cachedLogs = dayCacheLogs[dateStr] {
                dayLogs = cachedLogs
                syncInputRowsFromDayLogs(cachedLogs.logs, for: cachedLogs.date)
            }
            if let cachedSummary = dayCacheSummary[dateStr] {
                daySummary = cachedSummary
                daySummaryError = nil
            }

            dateTransitionResetHandled = true
            selectedSummaryDate = normalized
            dayTransitionOffset = -slideOut * 0.6
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                dayTransitionOffset = 0
            }
        }
    }

    @MainActor
    private func transitionToSummaryDate(_ rawDate: Date) async {
        let normalized = clampedSummaryDate(rawDate)
        guard !Calendar.current.isDate(normalized, inSameDayAs: selectedSummaryDate) else { return }

        await flushPendingAutoSaveIfEligible()
        protectDraftRowsForDateChange()
        resetActiveParseStateForDateChange()

        dateTransitionResetHandled = true
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSummaryDate = normalized
        }
    }

    private func draftTimestampForSelectedDate(reference: Date = Date()) -> Date {
        HomeLoggingDateUtils.draftTimestamp(for: selectedSummaryDate, reference: reference)
    }

    private func ensureDraftTimingStarted() {
        let now = Date()
        if flowStartedAt == nil {
            flowStartedAt = now
        }
        if draftLoggedAt == nil {
            draftLoggedAt = draftTimestampForSelectedDate(reference: now)
        }
    }

    private func draftDayString() -> String? {
        draftLoggedAt.map { HomeLoggingDateUtils.summaryRequestFormatter.string(from: $0) }
    }

    private func currentDraftLoggedAtString(reference: Date = Date()) -> String {
        HomeLoggingDateUtils.loggedAtFormatter.string(
            from: draftLoggedAt ?? draftTimestampForSelectedDate(reference: reference)
        )
    }

    private func captureDateChangeDraftRows() -> [DateChangeDraftRow] {
        let snapshotRowIDs = Set(activeParseSnapshots.map(\.rowID))
        let loggedAt = currentDraftLoggedAtString()

        return inputRows.compactMap { row in
            guard !row.isSaved else { return nil }
            guard !snapshotRowIDs.contains(row.id) else { return nil }

            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            return DateChangeDraftRow(
                rowID: row.id,
                text: text,
                loggedAt: loggedAt,
                inputKind: normalizedInputKind(latestParseInputKind, fallback: "text")
            )
        }
    }

    private func protectDraftRowsForDateChange() {
        let drafts = captureDateChangeDraftRows()
        preserveCurrentDraftRowsForDateChange(backgroundDraftRowIDs: Set(drafts.map(\.rowID)))
        startDateChangeDraftPersistence(drafts)
    }

    private func preserveCurrentDraftRowsForDateChange(backgroundDraftRowIDs: Set<UUID>) {
        let dateString = draftDayString() ?? summaryDateString
        let rowsToPreserve = inputRows.compactMap { row -> PreservedDateDraftRow? in
            guard !row.isSaved else { return nil }
            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            var preservedRow = row
            preservedRow.clearParsePhase()
            preservedRow.showInsertShimmer = false
            preservedRow.showCalorieRevealShimmer = false
            preservedRow.showCalorieUpdateShimmer = false
            preservedRow.isDeleting = false

            let backgroundManaged = backgroundDraftRowIDs.contains(row.id)
            if backgroundManaged,
               preservedRow.calories == nil,
               preservedRow.parsedItem == nil,
               preservedRow.parsedItems.isEmpty {
                preservedRow.normalizedTextAtParse = HomeLoggingTextMatch.normalizedRowText(text)
            }

            return PreservedDateDraftRow(
                row: preservedRow,
                isBackgroundManaged: backgroundManaged
            )
        }

        guard !rowsToPreserve.isEmpty else { return }

        var existingRows = preservedDraftRowsByDate[dateString] ?? []
        var indexByRowID: [UUID: Int] = [:]
        for (index, existingRow) in existingRows.enumerated() {
            indexByRowID[existingRow.row.id] = index
        }

        for preservedRow in rowsToPreserve {
            if let index = indexByRowID[preservedRow.row.id] {
                existingRows[index] = preservedRow
            } else {
                indexByRowID[preservedRow.row.id] = existingRows.count
                existingRows.append(preservedRow)
            }
        }

        preservedDraftRowsByDate[dateString] = existingRows
    }

    private func startDateChangeDraftPersistence(_ drafts: [DateChangeDraftRow]) {
        for draft in drafts {
            dateChangeDraftTasks[draft.rowID]?.cancel()
            dateChangeDraftTasks[draft.rowID] = Task { @MainActor in
                await persistDateChangeDraft(draft)
                dateChangeDraftTasks[draft.rowID] = nil
            }
        }
    }

    @MainActor
    private func persistDateChangeDraft(_ draft: DateChangeDraftRow) async {
        guard appStore.isNetworkReachable else {
            markPreservedDateDraftNeedsParse(rowID: draft.rowID, loggedAt: draft.loggedAt)
            return
        }

        do {
            let response = try await appStore.apiClient.parseLog(
                ParseLogRequest(text: draft.text, loggedAt: draft.loggedAt)
            )
            guard let request = buildDateChangeDraftSaveRequest(
                draft: draft,
                response: response
            ) else {
                markPreservedDateDraftNeedsParse(rowID: draft.rowID, loggedAt: draft.loggedAt)
                return
            }

            let idempotencyKey = resolveIdempotencyKey(forRowID: draft.rowID)
            upsertPendingSaveQueueItem(
                request: request,
                fingerprint: saveRequestFingerprint(request),
                idempotencyKey: idempotencyKey,
                rowID: draft.rowID
            )

            _ = await submitSave(
                request: request,
                idempotencyKey: idempotencyKey,
                isRetry: false,
                intent: .dateChangeBackground
            )
        } catch {
            handleAuthFailureIfNeeded(error)
            markPreservedDateDraftNeedsParse(rowID: draft.rowID, loggedAt: draft.loggedAt)
        }
    }

    private func clampedSummaryDate(_ date: Date) -> Date {
        HomeLoggingDateUtils.clampedSummaryDate(date)
    }

    private var isParsing: Bool {
        parseInFlightCount > 0
    }

    private var hasActiveParseRequest: Bool {
        inFlightParseSnapshot != nil
    }

    private var hasDirtyRowsPendingParse: Bool {
        !orderedDirtyRowIDsForCurrentInput().isEmpty
    }

    /// The scrollable food rows + status strip. The title "What did you eat today?"
    /// is rendered separately in the body so it stays pinned during day-swipe animations.
    private var composeEntryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputSection

            homeStatusStrip
                .padding(.top, 8)
        }
    }

    private var nutritionSummarySheet: some View {
        MainLoggingNutritionSummarySheet(
            totals: visibleNutritionTotals,
            navigationTitle: summaryDateString == HomeLoggingDateUtils.summaryRequestFormatter.string(from: Date()) ? "Today" : summaryDateString
        )
    }

    private var visibleNutritionTotals: NutritionTotals {
        .visible(from: inputRows)
    }

    private func refreshNutritionStateForVisibleDay() {
        invalidateDayCache(for: summaryDateString)
        refreshDaySummary()
        refreshDayLogs()
    }

    private func refreshNutritionStateAfterProgressChange(_ notification: Notification) {
        guard let savedDay = notification.userInfo?["savedDay"] as? String else {
            refreshNutritionStateForVisibleDay()
            return
        }

        invalidateDayCache(for: savedDay)
        guard savedDay == summaryDateString else { return }
        refreshDaySummary()
        refreshDayLogs()
    }

    private var inputSection: some View {
        HM01LogComposerSection(
            rows: $inputRows,
            focusBinding: $isNoteEditorFocused,
            mode: inputMode,
            inlineEstimateText: nil,
            hasActiveParseRequest: hasActiveParseRequest,
            minimalStyle: true,
            onInputTapped: {
                inputMode = .text
            },
            onCaloriesTapped: { row in
                presentRowDetails(for: row)
            },
            onFocusedRowChanged: { rowID in
                activeEditingRowID = rowID
            },
            onServerBackedRowCleared: { row in
                handleServerBackedRowCleared(row)
            },
            onQuantityFastPathUpdated: { rowID in
                handleQuantityFastPathUpdate(rowID: rowID)
            }
        )
    }

    private var noteText: String {
        // Only consider active (unsaved) rows for parsing — saved rows are read-only history
        inputRows.filter { !$0.isSaved }.map(\.text).joined(separator: "\n")
    }

    private var trimmedNoteText: String {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parseCandidateRows: [String] {
        let normalized = inputRows.filter { !$0.isSaved }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var end = normalized.count
        while end > 0, normalized[end - 1].isEmpty {
            end -= 1
        }
        return Array(normalized.prefix(end))
    }

    private var rowTextSignature: String {
        parseCandidateRows.joined(separator: "\u{001F}")
    }

    private var parseActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HM02ParseAndSaveActionsSection(
                isNetworkReachable: appStore.isNetworkReachable,
                networkQualityHint: appStore.networkQualityHint,
                isParsing: isParsing,
                isSaving: isSaving,
                parseDisabled: isParsing || !appStore.isNetworkReachable || trimmedNoteText.isEmpty,
                openDetailsDisabled: parseResult == nil,
                saveDisabled: isSaving || !appStore.isNetworkReachable || buildSaveDraftRequest() == nil,
                retryDisabled: isSaving || !appStore.isNetworkReachable || pendingSaveRequest == nil || pendingSaveIdempotencyKey == nil,
                showSaveDisabledHint: false,
                saveSuccessMessage: saveSuccessMessage,
                lastTimeToLogLabel: lastTimeToLogMs.map { L10n.timeToLog($0 / 1000) },
                saveError: saveError,
                idempotencyKeyLabel: pendingSaveIdempotencyKey.map { L10n.idempotencyKey($0.uuidString.lowercased()) },
                onParseNow: triggerParseNow,
                onOpenDetails: {
                    detailsDrawerMode = .full
                    isDetailsDrawerPresented = true
                },
                onSave: startSaveFlow,
                onRetry: retryLastSave
            )
        }
    }

    @ViewBuilder
    private func parseMetaCard(_ result: ParseLogResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.xaxis")
                    Text("\(L10n.confidenceLabel) ")
                    RollingNumberText(value: result.confidence, fractionDigits: 3)
                }
                Spacer()
                Label(result.fallbackUsed ? L10n.fallbackUsedLabel : L10n.routeDisplayName(result.route), systemImage: "bolt.horizontal")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if result.needsClarification {
                Text(L10n.parseClarificationHint)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if let sources = result.sourcesUsed, !sources.isEmpty {
                Text("Sources: \(sources.map(HomeLoggingDisplayText.sourceDisplayName).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.08))
        )
    }

    private var detailPrimaryTextColor: Color {
        colorScheme == .dark ? .white : Color.primary.opacity(0.96)
    }

    private var detailSecondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.secondary.opacity(0.92)
    }

    private var detailCardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color(uiColor: .secondarySystemBackground)
    }

    private var detailElevatedFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color(uiColor: .systemBackground)
    }

    private var detailMutedFillColor: Color {
        colorScheme == .dark ? Color.gray.opacity(0.10) : Color.black.opacity(0.05)
    }

    private var detailBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }

    private var detailMetadataPillFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05)
    }

    @ViewBuilder
    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(detailSecondaryTextColor)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(detailPrimaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(detailElevatedFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(detailBorderColor, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var daySummarySection: some View {
        HM06DaySummarySection(
            selectedDate: $selectedSummaryDate,
            maximumDate: Calendar.current.startOfDay(for: Date()),
            isLoading: isLoadingDaySummary,
            daySummaryError: daySummaryError,
            daySummary: daySummary,
            onRetry: refreshDaySummary
        )
    }

    @ViewBuilder
    private func clarificationEscalationSection(_ result: ParseLogResponse) -> some View {
        HM04ClarificationEscalationSection(
            parseResult: result,
            isEscalating: isEscalating,
            escalationInfoMessage: escalationInfoMessage,
            escalationError: escalationError,
            disabledReason: escalationDisabledReason(result),
            canEscalate: canEscalate(result),
            onEscalate: startEscalationFlow
        )
    }

    @ViewBuilder
    private var detailsDrawer: some View {
        MainLoggingDetailsDrawer(
            isManualAdd: detailsDrawerMode == .manualAdd,
            parseResult: parseResult,
            totals: displayedTotals,
            items: displayedDrawerItems,
            onManualAddBackToText: {
                inputMode = .text
                detailsDrawerMode = .full
                isDetailsDrawerPresented = false
            },
            onItemQuantityChange: { itemOffset, quantity in
                applyActiveParseItemQuantity(itemOffset: itemOffset, quantity: quantity)
            },
            onRecalculate: {
                isDetailsDrawerPresented = false
                triggerParseNow()
            }
        )
    }

    @ViewBuilder
    private func rowCalorieDetailsSheet(_ details: RowCalorieDetails) -> some View {
        let liveDetails = liveRowCalorieDetails(for: details.id, fallback: details)
        MainLoggingRowCalorieDetailsSheet(
            details: liveDetails,
            isDeleteDisabled: isRowDetailsDeleteDisabled(rowID: liveDetails.id),
            isDeleteConfirmationPresented: $isRowDetailsDeleteConfirmationPresented,
            onDeleteTapped: {
                rowDetailsPendingDeleteID = liveDetails.id
                isRowDetailsDeleteConfirmationPresented = true
            },
            onConfirmDelete: {
                if let rowID = rowDetailsPendingDeleteID {
                    confirmRowDetailsDelete(rowID: rowID)
                }
                rowDetailsPendingDeleteID = nil
            },
            onCancelDelete: {
                rowDetailsPendingDeleteID = nil
            },
            onDone: {
                selectedRowDetails = nil
            },
            onItemQuantityChange: { itemOffset, quantity in
                applyRowItemQuantity(
                    rowID: liveDetails.id,
                    itemOffset: itemOffset,
                    quantity: quantity
                )
            }
        )
    }

    @ViewBuilder
    private func manualOverrideSection(_ details: RowCalorieDetails) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Manual Override Details")
                    .font(.headline)
                Spacer()
                Text("Provenance")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(detailMutedFillColor)
                    )
            }

            Text("Reason: Adjusted manually in app.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !details.manualEditedFields.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Edited fields")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(details.manualEditedFields, id: \.self) { field in
                                Text(field)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.primary.opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(Color.orange.opacity(0.18))
                                    )
                            }
                        }
                    }
                }
            }

            if !details.manualOriginalSources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Original source")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(details.manualOriginalSources, id: \.self) { source in
                        Text(source)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(detailMutedFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(detailBorderColor, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func rowServingSizeSection(_ details: RowCalorieDetails) -> some View {
        let entries = servingSizeEntries(for: details)
        VStack(alignment: .leading, spacing: 10) {
            Text("Serving Size")
                .font(.headline)
            Text("Choose from Food Database serving sizes.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(entries, id: \.offset) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.item.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    let selectedOptionOffset = selectedServingOptionOffset(
                        rowID: details.id,
                        itemOffset: entry.offset,
                        servingOptions: entry.options
                    )
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(entry.options.enumerated()), id: \.offset) { optionOffset, option in
                                let selected = selectedOptionOffset == optionOffset
                                Button {
                                    applyRowServingOption(
                                        rowID: details.id,
                                        itemOffset: entry.offset,
                                        option: option
                                    )
                                } label: {
                                    Text(option.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(selected ? Color.white : detailPrimaryTextColor)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule()
                                                .fill(selected ? Color.blue : detailMutedFillColor)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Serving option \(optionOffset + 1): \(option.label)"))
                            }
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(detailMutedFillColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(detailBorderColor, lineWidth: 1)
                        )
                )
            }
        }
    }

    private func shouldShowServingSizeSection(_ details: RowCalorieDetails) -> Bool {
        if HomeLoggingDisplayText.normalizedLookupValue(parseResult?.route ?? "") == "gemini" {
            return false
        }
        return !servingSizeEntries(for: details).isEmpty
    }

    private func servingSizeEntries(for details: RowCalorieDetails) -> [(offset: Int, item: ParsedFoodItem, options: [ParsedServingOption])] {
        Array(details.parsedItems.enumerated()).compactMap { itemOffset, item in
            if HomeLoggingServingOptionUtils.isGeminiParsedItem(item) {
                return nil
            }
            guard let servingOptions = rowServingOptions(rowID: details.id, itemOffset: itemOffset, fallback: item),
                  !servingOptions.isEmpty else {
                return nil
            }
            return (offset: itemOffset, item: item, options: servingOptions)
        }
    }

    @ViewBuilder
    private var homeStatusStrip: some View {
        HStack(spacing: 10) {
            if let saveSuccessMessage {
                Text(saveSuccessMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            } else if let parseError {
                if isConnectivityParseError(parseError) {
                    Text(L10n.parseConnectivityIssueLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.16))
                        )
                } else {
                    Text(parseError)
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            } else if let parseInfoMessage {
                Text(parseInfoMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if inputMode != .text {
                Text(modeStatusMessage(inputMode))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                EmptyView()
            }

            Spacer(minLength: 0)

            if shouldShowRetryParseButton {
                Button(L10n.retryParseButton) {
                    triggerParseNow()
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.bordered)
                .accessibilityHint(Text(L10n.retryParseHint))
            }
        }
    }

    private var shouldShowRetryParseButton: Bool {
        guard !isParsing else { return false }
        guard appStore.isNetworkReachable else { return false }
        guard !trimmedNoteText.isEmpty else { return false }
        if parseError != nil {
            return true
        }
        return parseInfoMessage == L10n.parseStillProcessingLabel
    }

    private func isConnectivityParseError(_ message: String) -> Bool {
        message == L10n.noNetworkParse || message == L10n.parseNetworkFailure
    }

    private func modeStatusMessage(_ mode: HomeInputMode) -> String {
        switch mode {
        case .text:
            return ""
        case .voice:
            return "Voice capture is in progress. You can continue with text right now."
        case .camera:
            if let selectedCameraSource {
                return selectedCameraSource.statusMessage
            }
            return ""
        case .manualAdd:
            return "Manual add tools are open in Details."
        }
    }

    private func presentRowDetails(for row: HomeLogRow) {
        guard let details = makeRowCalorieDetails(for: row) else { return }
        selectedRowDetails = details
    }

    private func liveRowCalorieDetails(for rowID: UUID, fallback: RowCalorieDetails) -> RowCalorieDetails {
        guard let row = inputRows.first(where: { $0.id == rowID }),
              let refreshed = makeRowCalorieDetails(for: row) else {
            return fallback
        }
        return refreshed
    }

    private func isRowDetailsDeleteDisabled(rowID: UUID) -> Bool {
        guard let row = inputRows.first(where: { $0.id == rowID }) else { return true }
        return row.isDeleting || pendingDeleteTasks[rowID] != nil
    }

    private func confirmRowDetailsDelete(rowID: UUID) {
        guard let row = inputRows.first(where: { $0.id == rowID }) else {
            selectedRowDetails = nil
            return
        }

        selectedRowDetails = nil
        rowDetailsPendingDeleteID = nil

        if serverBackedDeleteContext(for: row) != nil {
            handleServerBackedRowCleared(row)
        } else {
            removeLocalRowFromDetails(rowID: rowID)
        }
    }

    private func removeLocalRowFromDetails(rowID: UUID) {
        clearTransientWorkForDeletedRow(rowID: rowID)
        locallyDeletedPendingRowIDs.insert(rowID)
        let removedKeys = removePendingSaveQueueItems(forRowID: rowID)
        locallyDeletedPendingSaveKeys.formUnion(removedKeys)

        if let index = inputRows.firstIndex(where: { $0.id == rowID }) {
            withAnimation(.easeOut(duration: 0.14)) {
                inputRows.remove(at: index)
                if inputRows.isEmpty || inputRows.allSatisfy({ $0.isSaved }) {
                    inputRows.append(.empty())
                }
            }
        }

        if hasSaveableRowsPending {
            scheduleAutoSave()
        } else {
            cancelAutoSaveTask()
        }
    }

    private func makeRowCalorieDetails(for row: HomeLogRow) -> RowCalorieDetails? {
        guard let calories = row.calories else { return nil }
        guard let rowIndex = inputRows.firstIndex(where: { $0.id == row.id }) else { return nil }

        let resolvedItems = resolvedItems(for: row)
        let overridePreview = manualOverridePreview(for: row, rowIndex: rowIndex)
        let parseConfidence = parseResult?.confidence ?? 0
        let itemConfidenceValues = resolvedItems.map(\.matchConfidence).filter { $0.isFinite }
        let itemConfidence = itemConfidenceValues.isEmpty
            ? nil
            : itemConfidenceValues.reduce(0, +) / Double(itemConfidenceValues.count)
        let primaryConfidence = itemConfidence ?? parseConfidence
        let route = parseResult?.route
        let routeDisplayName = route.map { L10n.routeDisplayName($0) }
        let sourceLabel = HomeLoggingDisplayText.sourceLabelForRowItems(
            resolvedItems,
            route: route,
            routeDisplayName: routeDisplayName
        )
        let hasManualOverride = resolvedItems.contains {
            ($0.manualOverride ?? false) || ($0.sourceFamily?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "manual")
        }
        let aggregatedProtein = resolvedItems.isEmpty ? nil : resolvedItems.reduce(0) { $0 + $1.protein }
        let aggregatedCarbs = resolvedItems.isEmpty ? nil : resolvedItems.reduce(0) { $0 + $1.carbs }
        let aggregatedFat = resolvedItems.isEmpty ? nil : resolvedItems.reduce(0) { $0 + $1.fat }
        let displayName: String
        if resolvedItems.count > 1 {
            let trimmed = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            displayName = trimmed.isEmpty ? "\(resolvedItems.count) items" : trimmed
        } else {
            displayName = resolvedItems.first?.name ?? row.text
        }
        return RowCalorieDetails(
            id: row.id,
            rowText: row.text,
            displayName: displayName,
            calories: calories,
            protein: aggregatedProtein,
            carbs: aggregatedCarbs,
            fat: aggregatedFat,
            parseConfidence: parseConfidence,
            itemConfidence: itemConfidence,
            primaryConfidence: min(max(primaryConfidence, 0), 1),
            hasManualOverride: hasManualOverride,
            sourceLabel: sourceLabel,
            thoughtProcess: HomeLoggingDisplayText.thoughtProcessText(
                for: row,
                sourceLabel: sourceLabel,
                items: resolvedItems,
                needsClarification: parseResult?.needsClarification == true
            ),
            parsedItems: resolvedItems,
            manualEditedFields: overridePreview.editedFields,
            manualOriginalSources: overridePreview.originalSources,
            imagePreviewData: row.imagePreviewData,
            imageRef: row.imageRef
        )
    }

    private func manualOverridePreview(for row: HomeLogRow, rowIndex: Int) -> (editedFields: [String], originalSources: [String]) {
        var editedFieldSet: Set<String> = []
        var originalSourceSet: Set<String> = []
        let fallbackMap: [String: String] = [
            "name": "name",
            "quantity": "quantity",
            "unit": "unit",
            "calories": "calories",
            "protein": "protein",
            "carbs": "carbs",
            "fat": "fat",
            "nutritionSourceId": "source"
        ]

        for (itemOffset, item) in row.parsedItems.enumerated() {
            if let editableIndex = editableIndexForRowItem(rowIndex: rowIndex, itemOffset: itemOffset),
               editableItems.indices.contains(editableIndex) {
                let manualOverride = editableItems[editableIndex].asSaveParsedFoodItem().manualOverride
                for field in manualOverride?.editedFields ?? [] {
                    let label = fallbackMap[field] ?? field
                    editedFieldSet.insert(label)
                }
            } else if item.manualOverride == true || HomeLoggingDisplayText.normalizedLookupValue(item.sourceFamily ?? "") == "manual" {
                editedFieldSet.insert("nutrition")
            }

            let originalSourceID = (item.originalNutritionSourceId ?? item.nutritionSourceId)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !originalSourceID.isEmpty {
                originalSourceSet.insert(HomeLoggingDisplayText.sourceReferenceLabel(for: originalSourceID))
            }
        }

        return (
            editedFields: Array(editedFieldSet).sorted(),
            originalSources: Array(originalSourceSet).sorted()
        )
    }

    private func resolvedItems(for row: HomeLogRow) -> [ParsedFoodItem] {
        if !row.parsedItems.isEmpty {
            return row.parsedItems
        }
        if let parsedItem = row.parsedItem {
            return [parsedItem]
        }
        return []
    }

    private func rowServingOptions(rowID: UUID, itemOffset: Int, fallback: ParsedFoodItem) -> [ParsedServingOption]? {
        guard let rowIndex = inputRows.firstIndex(where: { $0.id == rowID }),
              inputRows[rowIndex].parsedItems.indices.contains(itemOffset) else {
            return fallback.servingOptions
        }
        return inputRows[rowIndex].parsedItems[itemOffset].servingOptions
    }

    private var displayedDrawerItems: [ParsedFoodItem] {
        if editableItems.isEmpty {
            return parseResult?.items ?? []
        }
        return editableItems.map { $0.asParsedFoodItem() }
    }

    @MainActor
    private func applyActiveParseItemQuantity(itemOffset: Int, quantity: Double) {
        if editableItems.isEmpty, let items = parseResult?.items, items.indices.contains(itemOffset) {
            editableItems = items.map(EditableParsedItem.init(apiItem:))
        }
        guard editableItems.indices.contains(itemOffset) else { return }
        editableItems[itemOffset].updateQuantity(quantity)
        scheduleAutoSave()
    }

    @MainActor
    private func applyRowItemQuantity(rowID: UUID, itemOffset: Int, quantity: Double) {
        guard let rowIndex = inputRows.firstIndex(where: { $0.id == rowID }) else { return }
        guard inputRows[rowIndex].parsedItems.indices.contains(itemOffset) else { return }
        applyRowParsedItemEdit(rowIndex: rowIndex, itemOffset: itemOffset) { editable in
            editable.updateQuantity(quantity)
        }
        handleQuantityFastPathUpdate(rowID: rowID)
    }

    private func applyRowServingOption(rowID: UUID, itemOffset: Int, option: ParsedServingOption) {
        guard let rowIndex = inputRows.firstIndex(where: { $0.id == rowID }) else { return }
        guard inputRows[rowIndex].parsedItems.indices.contains(itemOffset) else { return }
        applyRowParsedItemEdit(rowIndex: rowIndex, itemOffset: itemOffset) { editable in
            editable.applyServingOption(option)
        }
        handleQuantityFastPathUpdate(rowID: rowID)
    }

    private func selectedServingOptionOffset(rowID: UUID, itemOffset: Int, servingOptions: [ParsedServingOption]) -> Int? {
        guard let rowIndex = inputRows.firstIndex(where: { $0.id == rowID }),
              inputRows[rowIndex].parsedItems.indices.contains(itemOffset) else {
            return nil
        }
        let rowItem = inputRows[rowIndex].parsedItems[itemOffset]
        return HomeLoggingServingOptionUtils.selectedServingOptionOffset(
            rowItem: rowItem,
            servingOptions: servingOptions
        )
    }

    private func applyRowParsedItemEdit(
        rowIndex: Int,
        itemOffset: Int,
        mutate: (inout EditableParsedItem) -> Void
    ) {
        guard inputRows.indices.contains(rowIndex) else { return }
        guard inputRows[rowIndex].parsedItems.indices.contains(itemOffset) else { return }

        let currentItem = inputRows[rowIndex].parsedItems[itemOffset]
        let editableIndex = editableIndexForRowItem(rowIndex: rowIndex, itemOffset: itemOffset)

        var workingEditable: EditableParsedItem
        if let editableIndex, editableItems.indices.contains(editableIndex) {
            workingEditable = editableItems[editableIndex]
        } else {
            workingEditable = EditableParsedItem(apiItem: currentItem)
        }

        mutate(&workingEditable)
        let updatedItem = workingEditable.asParsedFoodItem()

        inputRows[rowIndex].parsedItems[itemOffset] = updatedItem
        inputRows[rowIndex].parsedItem = inputRows[rowIndex].parsedItems.first

        if let editableIndex, editableItems.indices.contains(editableIndex) {
            editableItems[editableIndex] = workingEditable
        } else {
            let newIndex = editableItems.count
            editableItems.append(workingEditable)
            if inputRows[rowIndex].editableItemIndices.count <= itemOffset {
                inputRows[rowIndex].editableItemIndices += Array(
                    repeating: newIndex,
                    count: itemOffset - inputRows[rowIndex].editableItemIndices.count + 1
                )
            } else {
                inputRows[rowIndex].editableItemIndices[itemOffset] = newIndex
            }
        }

        recalculateRowNutrition(rowIndex: rowIndex)
    }

    private func editableIndexForRowItem(rowIndex: Int, itemOffset: Int) -> Int? {
        guard inputRows.indices.contains(rowIndex) else { return nil }
        guard inputRows[rowIndex].parsedItems.indices.contains(itemOffset) else { return nil }

        let mappedIndices = inputRows[rowIndex].editableItemIndices
        if mappedIndices.indices.contains(itemOffset) {
            let mappedIndex = mappedIndices[itemOffset]
            if editableItems.indices.contains(mappedIndex) {
                return mappedIndex
            }
        }

        let rowItem = inputRows[rowIndex].parsedItems[itemOffset]
        let normalizedSource = HomeLoggingDisplayText.normalizedLookupValue(rowItem.nutritionSourceId)
        let normalizedName = HomeLoggingDisplayText.normalizedLookupValue(rowItem.name)

        if let exact = editableItems.firstIndex(where: { item in
            HomeLoggingDisplayText.normalizedLookupValue(item.nutritionSourceId) == normalizedSource &&
                HomeLoggingDisplayText.normalizedLookupValue(item.name) == normalizedName
        }) {
            return exact
        }

        if let bySource = editableItems.firstIndex(where: {
            HomeLoggingDisplayText.normalizedLookupValue($0.nutritionSourceId) == normalizedSource
        }) {
            return bySource
        }

        if let byName = editableItems.firstIndex(where: {
            HomeLoggingDisplayText.normalizedLookupValue($0.name) == normalizedName
        }) {
            return byName
        }

        return nil
    }

    private func recalculateRowNutrition(rowIndex: Int) {
        guard inputRows.indices.contains(rowIndex) else { return }
        let rowItems = inputRows[rowIndex].parsedItems
        guard !rowItems.isEmpty else { return }

        let calories = Int(max(0, rowItems.reduce(0) { $0 + $1.calories }).rounded())
        inputRows[rowIndex].calories = calories
        inputRows[rowIndex].calorieRangeText = inputRows[rowIndex].isApproximate
            ? estimatedCalorieRangeText(for: calories)
            : nil
    }

    // MARK: - Voice Input

    private func handleVoiceModeTapped() {
        Task {
            guard await speechService.requestAuthorization() else {
                parseError = "Microphone or speech recognition permission was denied. Enable them in Settings."
                inputMode = .text
                return
            }

            do {
                try speechService.startListening()
                setVoiceOverlayPresented(true)
            } catch {
                parseError = "Could not start voice recognition: \(error.localizedDescription)"
                inputMode = .text
            }
        }
    }

    @MainActor
    private func insertVoiceTranscription(_ text: String) {
        // Find the first empty unsaved row, or append a new one
        if let emptyIndex = inputRows.firstIndex(where: {
            !$0.isSaved && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            inputRows[emptyIndex].text = text
            inputRows[emptyIndex].showInsertShimmer = true
        } else {
            var newRow = HomeLogRow.empty()
            newRow.text = text
            newRow.showInsertShimmer = true
            inputRows.append(newRow)
        }

        // Track input source for save contract
        latestParseInputKind = "voice"

        // Switch back to text mode — rowTextSignature change triggers
        // scheduleDebouncedParse automatically via the existing onChange observer
        inputMode = .text

        ensureDraftTimingStarted()
    }

    // MARK: - Voice Helpers

    private func setVoiceOverlayPresented(_ presented: Bool) {
        isVoiceOverlayPresented = presented
        NotificationCenter.default.post(
            name: .voiceRecordingStateChanged,
            object: nil,
            userInfo: ["isRecording": presented]
        )
    }

    private static let voiceHapticGenerator = UIImpactFeedbackGenerator(style: .soft)
    @State private var lastHapticTime: Date = .distantPast

    private func handleVoiceHaptic(level: Float) {
        guard level > 0.3 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHapticTime) > 0.3 else { return }
        lastHapticTime = now
        Self.voiceHapticGenerator.impactOccurred(intensity: CGFloat(min(level, 1.0)))
    }

    // MARK: - Camera Input

    private func handleCameraSourceSelection(_ source: CameraInputSource) {
        selectedCameraSource = source
        inputMode = .camera
        switch source {
        case .takePicture:
            isCustomCameraPresented = true
        case .photo:
            imagePickerSourceType = .photoLibrary
            isImagePickerPresented = true
        }
    }

    /// Drawer row for an unresolved-placeholder item. Shows the original
    /// segment text + a Retry button (or a spinner while a retry is
    /// in flight). Tapping Retry calls `retryUnresolvedItem`.
    @ViewBuilder
    private func unresolvedItemRow(rowID: UUID, itemIndex: Int, item: ParsedFoodItem) -> some View {
        let key = "\(rowID.uuidString)-\(itemIndex)"
        let isRetrying = retryingPlaceholderKeys.contains(key)

        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("Couldn't parse — tap Retry")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await retryUnresolvedItem(rowID: rowID, itemIndex: itemIndex) }
            } label: {
                Group {
                    if isRetrying {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.primary)
                    } else {
                        Text("Retry")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(width: 64, height: 32)
                .background(
                    Capsule().fill(Color.red.opacity(0.12))
                )
                .overlay(
                    Capsule().stroke(Color.red.opacity(0.35), lineWidth: 1)
                )
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(isRetrying)
            .accessibilityLabel(Text("Retry parsing \(item.name)"))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.red.opacity(0.18), lineWidth: 1)
                )
        )
    }

    // MARK: - Per-item Retry (drawer)
    //
    // When the segment-aware parser couldn't resolve a segment it emits a
    // placeholder item; the drawer renders that with a Retry button.
    // Retry re-parses just that segment text and replaces the placeholder
    // with the new item if the second pass succeeds. In-memory only —
    // saved-row persistence (PATCH) is queued as a separate follow-up.

    @MainActor
    private func retryUnresolvedItem(rowID: UUID, itemIndex: Int) async {
        let key = "\(rowID.uuidString)-\(itemIndex)"
        guard !retryingPlaceholderKeys.contains(key) else { return }
        retryingPlaceholderKeys.insert(key)
        defer { retryingPlaceholderKeys.remove(key) }

        guard let rowIndex = inputRows.firstIndex(where: { $0.id == rowID }) else { return }
        guard itemIndex < inputRows[rowIndex].parsedItems.count else { return }
        let placeholder = inputRows[rowIndex].parsedItems[itemIndex]
        guard placeholder.isUnresolvedPlaceholder else { return }

        let segmentText = placeholder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segmentText.isEmpty else { return }

        let loggedAtIso = HomeLoggingDateUtils.loggedAtFormatter.string(from: draftLoggedAt ?? draftTimestampForSelectedDate())
        let request = ParseLogRequest(text: segmentText, loggedAt: loggedAtIso)

        do {
            let response = try await appStore.apiClient.parseLog(request)

            // Pick the first non-placeholder item the retry produced.
            // If the retry ALSO came back as a placeholder, leave the
            // existing one in place — the user can edit the text or try
            // again.
            guard let resolved = response.items.first(where: { !$0.isUnresolvedPlaceholder }) else {
                return
            }

            // Re-validate the row + item index — the row may have been
            // edited or removed during the in-flight retry.
            guard let freshRowIndex = inputRows.firstIndex(where: { $0.id == rowID }),
                  itemIndex < inputRows[freshRowIndex].parsedItems.count,
                  inputRows[freshRowIndex].parsedItems[itemIndex].isUnresolvedPlaceholder else {
                return
            }

            inputRows[freshRowIndex].parsedItems[itemIndex] = resolved

            // Recompute row totals from the updated items so the row's
            // headline calorie reflects the freshly-parsed item.
            let totalCalories = inputRows[freshRowIndex].parsedItems.reduce(0.0) { $0 + $1.calories }
            inputRows[freshRowIndex].calories = Int(totalCalories.rounded())
            inputRows[freshRowIndex].showCalorieUpdateShimmer = true

            // If this row has already been persisted (saved on a prior
            // day or auto-saved earlier), push the in-memory swap to the
            // server so the placeholder doesn't reappear on the next
            // day-summary fetch. `performPatchUpdate` reads the row's
            // current parsedItems and totals and PATCHes the log,
            // refreshes the day cache, and posts the
            // `nutritionProgressDidChange` notification — same flow used
            // for any other row edit. Soft-fail on errors (the in-memory
            // state is still correct).
            if let serverLogId = inputRows[freshRowIndex].serverLogId {
                await performPatchUpdate(rowID: rowID, serverLogId: serverLogId)
            }
        } catch {
            // Soft fail — keep placeholder. The button stays available.
            // We could surface a toast here in a follow-up.
        }
    }

    // MARK: - Custom Camera Drawer Flow

    @MainActor
    private func parseAndUpdateDrawer(_ image: UIImage) async {
        guard let prepared = prepareImagePayload(from: image) else {
            withAnimation {
                cameraDrawerState = .error("Unable to process this image.", image)
            }
            return
        }

        ensureDraftTimingStarted()

        do {
            let response = try await appStore.apiClient.parseImageLog(
                imageData: prepared.uploadData,
                mimeType: prepared.mimeType,
                loggedAt: HomeLoggingDateUtils.loggedAtFormatter.string(from: draftLoggedAt ?? draftTimestampForSelectedDate())
            )

            // Store the parse result and prepared data for when the user confirms
            parseResult = response
            pendingImageData = prepared.uploadData
            pendingImagePreviewData = prepared.previewData
            pendingImageMimeType = prepared.mimeType
            pendingImageStorageRef = nil
            latestParseInputKind = "image"

            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                cameraDrawerState = .parsed(image, response.items, response.totals)
            }
        } catch {
            handleAuthFailureIfNeeded(error)
            withAnimation {
                cameraDrawerState = .error(userFriendlyParseError(error), image)
            }
        }
    }

    @MainActor
    private func handleDrawerLogIt() {
        guard case .parsed(_, let items, _) = cameraDrawerState,
              let response = parseResult else { return }

        // Populate the input row with a short display name.
        // Full detail (brand, protein content, flavor, etc.) lives in the items
        // and is shown in the details drawer — the home screen just needs a readable label.
        let rowText = HomeLoggingDisplayText.shortenedFoodLabel(items: items, extractedText: response.extractedText)

        var row = HomeLogRow.empty()
        row.text = rowText
        row.imagePreviewData = pendingImagePreviewData
        row.imageRef = pendingImageStorageRef
        suppressDebouncedParseOnce = true

        // Preserve existing rows (both saved history and unsaved drafts the user typed)
        // instead of wiping them. Insert the camera row before the trailing empty row.
        let savedRows = inputRows.filter { $0.isSaved }
        let unsavedNonEmpty = inputRows.filter {
            !$0.isSaved && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        inputRows = savedRows + unsavedNonEmpty + [row]
        clearParseSchedulerState()

        latestParseInputKind = normalizedInputKind(response.inputKind, fallback: "image")
        editableItems = response.items.map(EditableParsedItem.init(apiItem:))

        // Find the camera row we just inserted (the one with the image data)
        let cameraRowIndex = inputRows.lastIndex(where: { $0.id == row.id })
        let cameraRowIDSet: Set<UUID> = [row.id]
        applyRowParseResult(response, targetRowIDs: cameraRowIDSet)
        if let idx = cameraRowIndex {
            inputRows[idx].imagePreviewData = pendingImagePreviewData
            inputRows[idx].imageRef = pendingImageStorageRef
        }

        parseInfoMessage = nil
        parseError = nil
        saveError = nil
        appStore.setError(nil)
        upsertParseSnapshot(
            rowID: row.id,
            response: response,
            fallbackRawText: rowText
        )
        scheduleAutoSave()

        // Dismiss the sheet — food appears on home screen
        isCameraAnalysisSheetPresented = false
    }

    @MainActor
    private func handlePickedImage(_ image: UIImage) async {
        // Dismiss the picker sheet first, then open the analysis drawer —
        // identical flow to the camera capture path so both feel the same.
        isImagePickerPresented = false
        inputMode = .text
        selectedCameraSource = nil

        debounceTask?.cancel()
        parseTask?.cancel()
        cancelAutoSaveTask()
        parseRequestSequence += 1
        parseCoordinator.clearAll()
        autoSavedParseIDs = []
        clearPendingSaveContext()
        appStore.setError(nil)
        parseError = nil
        saveError = nil
        saveSuccessMessage = nil
        escalationError = nil
        escalationInfoMessage = nil
        escalationBlockedCode = nil

        // iOS needs a beat between sheet dismissal and the next sheet presentation.
        try? await Task.sleep(for: .milliseconds(350))

        cameraDrawerImage = image
        cameraDrawerState = .analyzing(image)
        isCameraAnalysisSheetPresented = true
        await parseAndUpdateDrawer(image)
    }

    private func clearImageContext() {
        pendingImageData = nil
        pendingImagePreviewData = nil
        pendingImageMimeType = nil
        pendingImageStorageRef = nil
        latestParseInputKind = "text"
        selectedCameraSource = nil
        for index in inputRows.indices {
            inputRows[index].imagePreviewData = nil
            inputRows[index].imageRef = nil
        }
    }

    private func canonicalParseRawText(
        response: ParseLogResponse,
        fallbackRawText: String
    ) -> String {
        let extracted = (response.extractedText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !extracted.isEmpty {
            return String(extracted.prefix(500))
        }

        let fallback = fallbackRawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty {
            return String(fallback.prefix(500))
        }

        let itemFallback = response.items.map(\.name).joined(separator: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(itemFallback.prefix(500))
    }

    private func upsertParseSnapshot(
        rowID: UUID,
        response: ParseLogResponse,
        fallbackRawText: String,
        loggedAt: String? = nil,
        rowItems: [ParsedFoodItem]? = nil
    ) {
        let rowItemsSnapshot = rowItems
            ?? inputRows.first(where: { $0.id == rowID })?.parsedItems
            ?? response.items
        let rowEntry = ParseSnapshot(
            rowID: rowID,
            parseRequestId: response.parseRequestId,
            parseVersion: response.parseVersion,
            rawText: canonicalParseRawText(response: response, fallbackRawText: fallbackRawText),
            loggedAt: loggedAt ?? currentDraftLoggedAtString(),
            response: response,
            rowItems: rowItemsSnapshot,
            capturedAt: Date()
        )
        parseCoordinator.commit(snapshot: rowEntry)
    }

    private func prepareImagePayload(from image: UIImage) -> PreparedImagePayload? {
        let maxBytes = 600_000
        let dimensionAttempts: [CGFloat] = [1920, 1600, 1280, 1024]
        let qualityAttempts: [CGFloat] = [0.85, 0.78, 0.70, 0.62, 0.55, 0.45, 0.35]
        var smallestData: Data?

        for dimension in dimensionAttempts {
            let resized = resizeImageIfNeeded(image, maxDimension: dimension)
            for quality in qualityAttempts {
                guard let data = resized.jpegData(compressionQuality: quality) else {
                    continue
                }
                if smallestData.map({ data.count < $0.count }) != false {
                    smallestData = data
                }
                if data.count <= maxBytes {
                    return PreparedImagePayload(uploadData: data, previewData: data, mimeType: "image/jpeg")
                }
            }
        }

        if let smallestData {
            return PreparedImagePayload(uploadData: smallestData, previewData: smallestData, mimeType: "image/jpeg")
        }
        return nil
    }

    private func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else {
            return image
        }

        let scale = maxDimension / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }



    @MainActor
    private func scheduleDebouncedParse(for newValue: String) {
        debounceTask?.cancel()
        cancelAutoSaveTask()
        unresolvedRetryTask?.cancel()
        // Only mutate @State if the value is actually changing — avoids unnecessary re-renders
        if unresolvedRetryCount != 0 { unresolvedRetryCount = 0 }
        if parseError != nil { parseError = nil }
        if parseInfoMessage != nil { parseInfoMessage = nil }
        if saveError != nil { saveError = nil }
        if escalationError != nil { escalationError = nil }
        if escalationInfoMessage != nil { escalationInfoMessage = nil }
        if escalationBlockedCode != nil { escalationBlockedCode = nil }

        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parseResult = nil
            editableItems = []
            isEscalating = false
            flowStartedAt = nil
            draftLoggedAt = nil
            lastTimeToLogMs = nil
            lastAutoSavedContentFingerprint = nil
            autoSavedParseIDs = []
            parseCoordinator.clearAll()
            clearParseSchedulerState()
            let clearedRowIDs = Set(inputRows.filter { !$0.isSaved }.map(\.id))
            if !clearedRowIDs.isEmpty {
                let filteredQueue = pendingSaveQueue.filter { item in
                    guard item.serverLogId == nil, let rowID = item.rowID else {
                        return true
                    }
                    return !clearedRowIDs.contains(rowID)
                }
                if filteredQueue.count != pendingSaveQueue.count {
                    saveCoordinator.setPendingItems(filteredQueue, persist: true)
                    syncPendingQueueFromCoordinator(refreshRetryState: true)
                } else {
                    refreshRetryStateFromPendingQueue()
                }
            }
            // Preserve saved (history) rows — only reset the active input row
            let savedRows = inputRows.filter { $0.isSaved }
            inputRows = savedRows + [HomeLogRow.empty()]
            clearImageContext()
            clearPendingSaveContext()
            return
        }

        ensureDraftTimingStarted()

        if shouldDeferDebouncedParse(for: newValue) {
            // Defer ownership sync to after debounce — running it per-keystroke
            // iterates all rows, calls predictedLoadingRouteHint (regex), and
            // mutates parsePhase on every row, which tanks typing performance.
            return
        }

        let dirtyRowIDs = orderedDirtyRowIDsForCurrentInput()
        guard !dirtyRowIDs.isEmpty else {
            if !hasActiveParseRequest {
                clearParseSchedulerState()
            } else {
                queuedParseRowIDs = []
                latestQueuedNoteText = nil
                pendingFollowupRequested = false
                // Defer synchronizeParseOwnership to debounce callback
            }
            return
        }

        if !hasActiveParseRequest {
            activeParseRowID = dirtyRowIDs.first
            queuedParseRowIDs = Array(dirtyRowIDs.dropFirst())
        } else {
            queuedParseRowIDs = dirtyRowIDs.filter { $0 != activeParseRowID }
        }
        // Defer synchronizeParseOwnership to debounce callback
        let nonEmptyRowCount = inputRows.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let debounceNanos: UInt64 = nonEmptyRowCount > 1 ? 1_500_000_000 : 1_000_000_000

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                handleQueuedOrImmediateParseRequest(for: trimmed)
            }
        }
    }

    @MainActor
    private func triggerParseNow() {
        debounceTask?.cancel()
        unresolvedRetryTask?.cancel()
        let trimmed = trimmedNoteText
        guard !trimmed.isEmpty else { return }
        ensureDraftTimingStarted()

        let dirtyRowIDs = orderedDirtyRowIDsForCurrentInput()
        guard !dirtyRowIDs.isEmpty else {
            if !hasActiveParseRequest {
                clearParseSchedulerState()
            } else {
                queuedParseRowIDs = []
                latestQueuedNoteText = nil
                pendingFollowupRequested = false
                synchronizeParseOwnership()
            }
            return
        }

        if !hasActiveParseRequest {
            activeParseRowID = dirtyRowIDs.first
            queuedParseRowIDs = Array(dirtyRowIDs.dropFirst())
        }
        handleQueuedOrImmediateParseRequest(for: trimmed)
    }

    @MainActor
    private func parseCurrentText(_ text: String, requestSequence: Int) async {
        guard !text.isEmpty else { return }
        guard let snapshot = inFlightParseSnapshot, snapshot.requestSequence == requestSequence else { return }
        var shouldAdvanceToNextRow = true
        if !appStore.isNetworkReachable {
            parseInfoMessage = nil
            parseError = L10n.noNetworkParse
            parseTask = nil
            inFlightParseSnapshot = nil
            activeParseRowID = snapshot.activeRowID
            queuedParseRowIDs = orderedDirtyRowIDsForCurrentInput().filter { $0 != snapshot.activeRowID }
            pendingFollowupRequested = false
            latestQueuedNoteText = nil
            synchronizeParseOwnership()
            return
        }
        let startedAt = Date()
        parseInFlightCount += 1
        defer {
            parseInFlightCount = max(0, parseInFlightCount - 1)
            parseTask = nil
            inFlightParseSnapshot = nil
            if !Task.isCancelled {
                if shouldAdvanceToNextRow {
                    processNextQueuedParseIfNeeded()
                } else {
                    synchronizeParseOwnership()
                }
            }
        }

        do {
            let response: ParseLogResponse
            let durationMs: Double
            if let cachedResponse = parseCoordinator.cachedResponse(
                rowID: snapshot.activeRowID,
                text: text,
                loggedAt: snapshot.loggedAt
            ) {
                response = cachedResponse
                durationMs = 0
            } else {
                let request = ParseLogRequest(text: text, loggedAt: snapshot.loggedAt)
                response = try await appStore.apiClient.parseLog(request)
                durationMs = elapsedMs(since: startedAt)
                parseCoordinator.storeCachedResponse(
                    response,
                    rowID: snapshot.activeRowID,
                    text: text,
                    loggedAt: snapshot.loggedAt
                )
            }

            // Guard: if the target row no longer exists (e.g. user swiped to a different
            // day while the parse was in flight), silently discard the response instead
            // of applying it to some other day's data.
            guard inputRows.contains(where: { $0.id == snapshot.activeRowID }) else {
                shouldAdvanceToNextRow = false
                return
            }

            // Staleness guard: the user may have edited the row's text while
            // this parse was in flight (e.g. typed "chicken tenders", then
            // edited to "3 pieces chicken tenders" before the response came
            // back). Applying the stale response would map 1-piece calories
            // onto the new text AND stamp normalizedTextAtParse with the new
            // text, making the row look fresh — so `rowNeedsFreshParse` would
            // return false and no follow-up parse would fire. Instead, discard
            // the response here and let the deferred
            // `processNextQueuedParseIfNeeded()` (via shouldAdvanceToNextRow)
            // dispatch a fresh parse against the edited text.
            if let currentRow = inputRows.first(where: { $0.id == snapshot.activeRowID }) {
                let normalizedSent = HomeLoggingTextMatch.normalizedRowText(snapshot.text)
                let normalizedCurrent = HomeLoggingTextMatch.normalizedRowText(currentRow.text)
                if !normalizedSent.isEmpty && normalizedSent != normalizedCurrent {
                    // Leave the row marked dirty (we deliberately don't touch
                    // calories/parsedItems/normalizedTextAtParse) and let the
                    // defer block re-dispatch against the new text.
                    emitParseTelemetrySuccess(response: response, durationMs: durationMs, uiApplied: false)
                    return
                }
            }
#if DEBUG
            if let cacheDebug = response.cacheDebug {
                let reasonSummary = (response.reasonCodes ?? []).joined(separator: ",")
                let retryAfterSummary = response.retryAfterSeconds.map(String.init) ?? "nil"
                print("[parse_cache_debug] route=\(response.route) cacheHit=\(response.cacheHit) reasonCodes=\(reasonSummary) retryAfterSeconds=\(retryAfterSummary) scope=\(cacheDebug.scope) hash=\(cacheDebug.textHash) normalized=\(cacheDebug.normalizedText)")
            } else {
                let reasonSummary = (response.reasonCodes ?? []).joined(separator: ",")
                let retryAfterSummary = response.retryAfterSeconds.map(String.init) ?? "nil"
                print("[parse_cache_debug] route=\(response.route) cacheHit=\(response.cacheHit) reasonCodes=\(reasonSummary) retryAfterSeconds=\(retryAfterSummary)")
            }
#endif
            if shouldHoldUnresolvedResponse(response) {
                // Mark only this row as unresolved — don't block the rest of the queue
                if let idx = inputRows.firstIndex(where: { $0.id == snapshot.activeRowID }) {
                    inputRows[idx].setParseUnresolved()
                }
                logUnresolvedParseDiagnostics(response)
                emitParseTelemetrySuccess(response: response, durationMs: durationMs, uiApplied: false)
                // shouldAdvanceToNextRow stays true → defer will call processNextQueuedParseIfNeeded()
                return
            }

            unresolvedRetryCount = 0
            unresolvedRetryTask?.cancel()
            latestParseInputKind = normalizedInputKind(response.inputKind, fallback: "text")
            applyRowParseResult(response, targetRowIDs: [snapshot.activeRowID])
            parseInfoMessage = nil
            parseError = nil
            saveError = nil
            escalationError = nil
            escalationInfoMessage = nil
            escalationBlockedCode = nil
            clearPendingSaveContext()
            appStore.setError(nil)
            emitParseTelemetrySuccess(response: response, durationMs: durationMs, uiApplied: true)

            // Store this row's result with the rawText that was actually sent to the backend.
            // This is the fix for the 422 rawText mismatch: buildSaveDraftRequest/autoSaveIfNeeded
            // will use the committed row snapshot rawText instead of trimmedNoteText.
            //
            // Also snapshot the row's per-row parsedItems (computed by
            // applyRowParseResult immediately above). When multiple rows are
            // parsed together, response.items contains ALL items but the row's
            // parsedItems is already filtered to just this row's item(s). The
            // save path uses this snapshot so one row's food_log doesn't end up
            // carrying another row's macros.
            let rowItemsSnapshot = inputRows.first(where: { $0.id == snapshot.activeRowID })?.parsedItems
                ?? response.items
            upsertParseSnapshot(
                rowID: snapshot.activeRowID,
                response: response,
                fallbackRawText: text,
                loggedAt: snapshot.loggedAt,
                rowItems: rowItemsSnapshot
            )

            let remainingDirtyRowIDs = orderedDirtyRowIDsForCurrentInput()
            activeParseRowID = remainingDirtyRowIDs.first
            queuedParseRowIDs = Array(remainingDirtyRowIDs.dropFirst())
            pendingFollowupRequested = !remainingDirtyRowIDs.isEmpty
            latestQueuedNoteText = remainingDirtyRowIDs.isEmpty ? nil : trimmedNoteText

            // Always show accumulated results so the UI never goes blank while the queue drains.
            parseResult = response
            // Use each entry's row-specific items (not the full response.items)
            // so items from a combined multi-row parse aren't duplicated in the
            // details drawer once the individual rows have their own entries.
            editableItems = activeParseSnapshots
                .flatMap { $0.rowItems }
                .map(EditableParsedItem.init(apiItem:))

            if remainingDirtyRowIDs.isEmpty {
                scheduleDetailsDrawer(for: response)
            }
            // Save completed rows even if other rows are still dirty/queued.
            // This prevents visible calorie rows from being left unsaved.
            scheduleAutoSave()
        } catch {
            let durationMs = elapsedMs(since: startedAt)
            if error is CancellationError || Task.isCancelled {
                return
            }
            shouldAdvanceToNextRow = false
            unresolvedRetryTask?.cancel()
            parseCoordinator.markFailed(rowID: snapshot.activeRowID)
            handleAuthFailureIfNeeded(error)
            activeParseRowID = snapshot.activeRowID
            queuedParseRowIDs = orderedDirtyRowIDsForCurrentInput().filter { $0 != snapshot.activeRowID }
            pendingFollowupRequested = false
            latestQueuedNoteText = nil
            let message = userFriendlyParseError(error)
            parseInfoMessage = nil
            parseError = message
            appStore.setError(message)
            emitParseTelemetryFailure(error: error, durationMs: durationMs, uiApplied: true)
            // Parse failure on one row should not block autosave for already
            // parsed rows that have visible calories.
            if hasSaveableRowsPending {
                scheduleAutoSave()
            }
        }
    }

    private func shouldHoldUnresolvedResponse(_ response: ParseLogResponse) -> Bool {
        guard response.items.isEmpty else { return false }
        if isTrustedZeroNutritionResponse(response) {
            return false
        }
        return response.route == "unresolved" || response.route == "gemini"
    }

    private func isTrustedZeroNutritionResponse(_ response: ParseLogResponse) -> Bool {
        guard response.items.isEmpty else { return false }
        guard !response.needsClarification else { return false }
        guard response.confidence >= 0.70 else { return false }
        return response.totals.calories <= 0.05 &&
            response.totals.protein <= 0.05 &&
            response.totals.carbs <= 0.05 &&
            response.totals.fat <= 0.05
    }

    private func logUnresolvedParseDiagnostics(_ response: ParseLogResponse) {
#if DEBUG
        let reasonSummary = (response.reasonCodes ?? []).joined(separator: ",")
        let retryAfterSummary = response.retryAfterSeconds.map(String.init) ?? "nil"
        print(
            "[parse_unresolved_debug] route=\(response.route) fallbackUsed=\(response.fallbackUsed) " +
                "needsClarification=\(response.needsClarification) reasonCodes=\(reasonSummary) " +
                "retryAfterSeconds=\(retryAfterSummary) confidence=\(response.confidence)"
        )
#endif
    }

    private func shouldDeferDebouncedParse(for rawText: String) -> Bool {
        guard rawText.contains("\n") else { return false }
        let lines = rawText.components(separatedBy: .newlines)
        guard let lastLine = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines), !lastLine.isEmpty else {
            return false
        }

        let sanitized = lastLine.replacingOccurrences(of: "[,;:]+$", with: "", options: .regularExpression)
        return sanitized.range(of: #"^\d+(?:[./]\d+)?$"#, options: .regularExpression) != nil
    }

    @MainActor
    private func handleQueuedOrImmediateParseRequest(for text: String) {
        guard !text.isEmpty else { return }
        let dirtyRowIDs = orderedDirtyRowIDsForCurrentInput()
        guard let firstDirtyRowID = dirtyRowIDs.first else {
            clearParseSchedulerState()
            return
        }

        if hasActiveParseRequest {
            if activeParseRowID == nil {
                activeParseRowID = firstDirtyRowID
            }
            queuedParseRowIDs = dirtyRowIDs.filter { $0 != activeParseRowID }
            latestQueuedNoteText = text
            pendingFollowupRequested = true
            synchronizeParseOwnership()
            return
        }

        let rowText = inputRows.first(where: { $0.id == firstDirtyRowID })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? text
        startTextParse(
            text: rowText.isEmpty ? text : rowText,
            activeRowID: firstDirtyRowID,
            dirtyRowIDs: dirtyRowIDs
        )
    }

    @MainActor
    private func startTextParse(
        text: String,
        activeRowID: UUID,
        dirtyRowIDs: [UUID]
    ) {
        parseRequestSequence += 1
        let loggedAt = currentDraftLoggedAtString()
        inFlightParseSnapshot = InFlightParseSnapshot(
            text: text,
            loggedAt: loggedAt,
            requestSequence: parseRequestSequence,
            activeRowID: activeRowID,
            dirtyRowIDsAtDispatch: dirtyRowIDs
        )
        activeParseRowID = activeRowID
        queuedParseRowIDs = Array(dirtyRowIDs.dropFirst())
        pendingFollowupRequested = false
        latestQueuedNoteText = nil
        parseInfoMessage = nil
        parseError = nil
        appStore.setError(nil)
        parseCoordinator.markInFlight(rowID: activeRowID)
        synchronizeParseOwnership()
        parseTask = Task { @MainActor in
            await parseCurrentText(text, requestSequence: parseRequestSequence)
        }
    }

    @MainActor
    private func processNextQueuedParseIfNeeded() {
        let dirtyRowIDs = orderedDirtyRowIDsForCurrentInput()
        guard let nextActiveRowID = dirtyRowIDs.first else {
            clearParseSchedulerState()
            return
        }

        activeParseRowID = nextActiveRowID
        queuedParseRowIDs = Array(dirtyRowIDs.dropFirst())
        synchronizeParseOwnership()

        let nextText = inputRows.first(where: { $0.id == nextActiveRowID })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !nextText.isEmpty else { return }

        startTextParse(
            text: nextText,
            activeRowID: nextActiveRowID,
            dirtyRowIDs: dirtyRowIDs
        )
    }

    private func clearParseSchedulerState() {
        if let activeParseRowID {
            parseCoordinator.cancelInFlight(rowID: activeParseRowID)
        }
        activeParseRowID = nil
        queuedParseRowIDs = []
        inFlightParseSnapshot = nil
        pendingFollowupRequested = false
        latestQueuedNoteText = nil
        synchronizeParseOwnership()
    }

    /// Clears ALL per-day transient parse state. Called when the user changes the
    /// selected date (swipe or calendar pick) so parse spinners / partial results
    /// from the previous day don't leak onto the new day's view.
    private func resetActiveParseStateForDateChange() {
        // Cancel in-flight tasks first so their completion handlers bail out
        parseTask?.cancel()
        debounceTask?.cancel()
        cancelAutoSaveTask()
        unresolvedRetryTask?.cancel()

        // Drop active draft rows immediately on date changes so a draft from
        // one day cannot follow the user into another day while the network
        // reload is still in flight.
        let savedRows = inputRows.filter { $0.isSaved }
        inputRows = savedRows.isEmpty ? [HomeLogRow.empty()] : savedRows

        if parseResult != nil { parseResult = nil }
        if !editableItems.isEmpty { editableItems = [] }
        if activeParseRowID != nil { activeParseRowID = nil }
        if !queuedParseRowIDs.isEmpty { queuedParseRowIDs = [] }
        if inFlightParseSnapshot != nil { inFlightParseSnapshot = nil }
        if !autoSavedParseIDs.isEmpty { autoSavedParseIDs = [] }
        parseCoordinator.clearAll()
        if parseInFlightCount != 0 { parseInFlightCount = 0 }
        if unresolvedRetryCount != 0 { unresolvedRetryCount = 0 }

        // Clear transient error/info messages
        if parseError != nil { parseError = nil }
        if parseInfoMessage != nil { parseInfoMessage = nil }
        if saveError != nil { saveError = nil }
        if escalationError != nil { escalationError = nil }
        if escalationInfoMessage != nil { escalationInfoMessage = nil }
        if escalationBlockedCode != nil { escalationBlockedCode = nil }
        if saveSuccessMessage != nil { saveSuccessMessage = nil }

        // Reset flow tracking (new day = new flow)
        if flowStartedAt != nil { flowStartedAt = nil }
        if draftLoggedAt != nil { draftLoggedAt = nil }
        if lastTimeToLogMs != nil { lastTimeToLogMs = nil }
        if lastAutoSavedContentFingerprint != nil { lastAutoSavedContentFingerprint = nil }

        // Clear image-related @State vars (but NOT inputRows image data —
        // that gets replaced when syncInputRowsFromDayLogs runs)
        pendingImageData = nil
        pendingImagePreviewData = nil
        pendingImageMimeType = nil
        pendingImageStorageRef = nil
        latestParseInputKind = "text"
        selectedCameraSource = nil
    }

    private func synchronizeParseOwnership() {
        let queuedSet = Set(queuedParseRowIDs)
        for index in inputRows.indices {
            let rowID = inputRows[index].id
            if hasActiveParseRequest, rowID == activeParseRowID {
                // Only mutate if not already in .active state to avoid re-rendering
                if !inputRows[index].isLoading {
                    let startedAt = inputRows[index].loadingStatusStartedAt ?? Date()
                    inputRows[index].setParseActive(
                        routeHint: HomeLogRow.predictedLoadingRouteHint(for: inputRows[index].text),
                        startedAt: startedAt
                    )
                }
            } else if !hasActiveParseRequest, rowID == activeParseRowID, parseError != nil {
                if !inputRows[index].isFailed {
                    inputRows[index].setParseFailed()
                }
            } else if queuedSet.contains(rowID) {
                if !inputRows[index].isQueued {
                    inputRows[index].setParseQueued()
                }
            } else if inputRows[index].isUnresolved {
                // Preserve "Edit & Retry" — user needs to act on this row
                continue
            } else {
                if inputRows[index].parsePhase != .idle {
                    inputRows[index].clearParsePhase()
                }
            }
        }
        updateParseQueueInfoMessage()
    }

    private func updateParseQueueInfoMessage() {
        guard parseError == nil else { return }
        if hasActiveParseRequest && !queuedParseRowIDs.isEmpty {
            parseInfoMessage = L10n.parseQueuedLabel
        } else if parseInfoMessage == L10n.parseQueuedLabel {
            parseInfoMessage = nil
        }
    }

    private func orderedDirtyRowIDsForCurrentInput() -> [UUID] {
        inputRows.compactMap { row in
            rowNeedsFreshParse(row) ? row.id : nil
        }
    }

    private func rowNeedsFreshParse(_ row: HomeLogRow) -> Bool {
        let normalizedCurrentText = HomeLoggingTextMatch.normalizedRowText(row.text)
        guard !normalizedCurrentText.isEmpty else {
            return false
        }

        if let normalizedTextAtParse = row.normalizedTextAtParse {
            return normalizedTextAtParse != normalizedCurrentText
        }

        if row.calories != nil {
            return false
        }

        // Row has content but no parse snapshot yet.
        return row.parsedItem == nil && row.parsedItems.isEmpty
    }

    private func applyRowParseResult(_ response: ParseLogResponse, targetRowIDs: Set<UUID>? = nil) {
        let targetRowIDSet = targetRowIDs ?? Set(inputRows.map(\.id))
        let geminiAuthoritative = isGeminiAuthoritativeResponse(response)
        let approximateDisplay = response.needsClarification || response.confidence < 0.70

        let nonEmptyIndices = inputRows.indices.filter {
            !inputRows[$0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !nonEmptyIndices.isEmpty else { return }

        let candidateRowIndices = nonEmptyIndices.filter { targetRowIDSet.contains(inputRows[$0].id) }
        guard !candidateRowIndices.isEmpty else { return }

        let rowsNeedingFreshMapping: Set<Int> = Set(candidateRowIndices.filter { rowIndex in
            let row = inputRows[rowIndex]
            let normalized = HomeLoggingTextMatch.normalizedRowText(row.text)
            guard !normalized.isEmpty else { return false }
            if row.normalizedTextAtParse == nil { return true }
            if row.normalizedTextAtParse != normalized { return true }
            return row.calories == nil || (row.parsedItem == nil && row.parsedItems.isEmpty)
        })

        let lockedRowIndices: Set<Int> = Set(candidateRowIndices.filter { rowIndex in
            guard let existingCalories = inputRows[rowIndex].calories, existingCalories > 0 else {
                return false
            }
            let normalized = HomeLoggingTextMatch.normalizedRowText(inputRows[rowIndex].text)
            guard !normalized.isEmpty else { return false }
            return inputRows[rowIndex].normalizedTextAtParse == normalized
        })

        for rowIndex in candidateRowIndices where rowsNeedingFreshMapping.contains(rowIndex) && !lockedRowIndices.contains(rowIndex) {
            inputRows[rowIndex].calories = nil
            inputRows[rowIndex].calorieRangeText = nil
            inputRows[rowIndex].isApproximate = false
            inputRows[rowIndex].parsedItem = nil
            inputRows[rowIndex].parsedItems = []
            inputRows[rowIndex].editableItemIndices = []
            inputRows[rowIndex].normalizedTextAtParse = nil
        }
        var mappedCaloriesByRow: [Int: Int] = [:]
        var mappedItemsByRow: [Int: ParsedFoodItem] = [:]
        var mappedItemOffsetsByRow: [Int: Int] = [:]
        var usedItemOffsets: Set<Int> = []

        // Whole-note text parsing remains backend-driven, but queued UI should only update the active target row.
        // Restrict direct in-order mapping to full-application cases; targeted passes rely on row/item matching.
        if targetRowIDs == nil, geminiAuthoritative {
            let assignCount = min(nonEmptyIndices.count, response.items.count)
            for offset in 0..<assignCount {
                let rowIndex = nonEmptyIndices[offset]
                let itemOffset = offset
                guard let normalizedCalories = normalizedRowCalories(
                    from: response.items[itemOffset].calories,
                    response: response
                ) else {
                    continue
                }
                mappedCaloriesByRow[rowIndex] = normalizedCalories
                mappedItemsByRow[rowIndex] = response.items[itemOffset]
                mappedItemOffsetsByRow[rowIndex] = itemOffset
                usedItemOffsets.insert(itemOffset)
            }
        } else if targetRowIDs == nil, nonEmptyIndices.count == response.items.count {
            // Non-Gemini mode: in-order assignment only when parser rows line up with UI rows.
            for (itemOffset, rowIndex) in nonEmptyIndices.enumerated() {
                guard let normalizedCalories = normalizedRowCalories(
                    from: response.items[itemOffset].calories,
                    response: response
                ) else {
                    continue
                }
                mappedCaloriesByRow[rowIndex] = normalizedCalories
                mappedItemsByRow[rowIndex] = response.items[itemOffset]
                mappedItemOffsetsByRow[rowIndex] = itemOffset
                usedItemOffsets.insert(itemOffset)
            }
        }

        // Second attempt: best-match remap for parser-expanded or parser-collapsed responses.
        for rowIndex in candidateRowIndices where mappedCaloriesByRow[rowIndex] == nil {
            let rowText = inputRows[rowIndex].text
            var bestOffset: Int?
            var bestScore = 0.0

            for (itemOffset, item) in response.items.enumerated() where !usedItemOffsets.contains(itemOffset) {
                let score = HomeLoggingTextMatch.rowItemMatchScore(rowText: rowText, itemName: item.name)
                if score > bestScore {
                    bestScore = score
                    bestOffset = itemOffset
                }
            }

            let bestMatchThreshold = geminiAuthoritative ? 0.20 : 0.35
            if let bestOffset, bestScore >= bestMatchThreshold {
                if let normalizedCalories = normalizedRowCalories(
                    from: response.items[bestOffset].calories,
                    response: response
                ) {
                    mappedCaloriesByRow[rowIndex] = normalizedCalories
                    mappedItemsByRow[rowIndex] = response.items[bestOffset]
                    mappedItemOffsetsByRow[rowIndex] = bestOffset
                    usedItemOffsets.insert(bestOffset)
                }
            }
        }

        // Final fallback: assign remaining parser items in order only for high-confidence non-Gemini routes.
        // For Gemini/clarification flows this can create misleading duplicated values across rows.
        let unmatchedRowIndices = candidateRowIndices.filter {
            rowsNeedingFreshMapping.contains($0) && mappedCaloriesByRow[$0] == nil
        }
        let remainingItemOffsets = response.items.indices.filter { !usedItemOffsets.contains($0) }
        let canUseSequentialFallback = !geminiAuthoritative && !response.needsClarification && response.confidence >= 0.75
        if canUseSequentialFallback, !unmatchedRowIndices.isEmpty, !remainingItemOffsets.isEmpty {
            let assignCount = min(unmatchedRowIndices.count, remainingItemOffsets.count)
            for offset in 0..<assignCount {
                let rowIndex = unmatchedRowIndices[offset]
                let itemOffset = remainingItemOffsets[offset]
                guard let normalizedCalories = normalizedRowCalories(
                    from: response.items[itemOffset].calories,
                    response: response
                ) else {
                    continue
                }
                mappedCaloriesByRow[rowIndex] = normalizedCalories
                mappedItemsByRow[rowIndex] = response.items[itemOffset]
                mappedItemOffsetsByRow[rowIndex] = itemOffset
                usedItemOffsets.insert(itemOffset)
            }
        }

        debugRowParseMapping(
            response: response,
            nonEmptyIndices: nonEmptyIndices,
            rowsNeedingFreshMapping: rowsNeedingFreshMapping,
            lockedRowIndices: lockedRowIndices,
            mappedCaloriesByRow: mappedCaloriesByRow
        )

        for rowIndex in candidateRowIndices where rowsNeedingFreshMapping.contains(rowIndex) {
            if let mapped = mappedCaloriesByRow[rowIndex] {
                if lockedRowIndices.contains(rowIndex) {
                    continue
                }
                // Trigger calorie reveal shimmer when calories appear for the first time
                if inputRows[rowIndex].calories == nil && mapped > 0 {
                    inputRows[rowIndex].showCalorieRevealShimmer = true
                }
                inputRows[rowIndex].calories = mapped
                inputRows[rowIndex].isApproximate = approximateDisplay
                inputRows[rowIndex].calorieRangeText = approximateDisplay ? estimatedCalorieRangeText(for: mapped) : nil
                inputRows[rowIndex].parsedItem = mappedItemsByRow[rowIndex]
                inputRows[rowIndex].parsedItems = mappedItemsByRow[rowIndex].map { [$0] } ?? []
                inputRows[rowIndex].editableItemIndices = mappedItemOffsetsByRow[rowIndex].map { [$0] } ?? []
                inputRows[rowIndex].normalizedTextAtParse = HomeLoggingTextMatch.normalizedRowText(inputRows[rowIndex].text)
            }
        }

        // Multi-item-to-single-row override: when only one row is being
        // parsed (whether because the caller scoped via `targetRowIDs` or
        // because we're parsing the full input and only one row has text),
        // ALL parser items belong to that row. Without this branch, the
        // per-row loop above would assign just one item and silently drop
        // the rest — the canonical bug where typing
        // "2 naan, butter paneer masala, rice bowl" yielded only Naan.
        // The original code restricted this to `targetRowIDs == nil`, but
        // typing into a specific row sets `targetRowIDs = [thatRowID]`,
        // which is exactly the case that needs the multi-item assignment.
        if candidateRowIndices.count == 1,
           let normalizedTotalsCalories = normalizedRowCalories(from: response.totals.calories, response: response) {
            let onlyRowIndex = candidateRowIndices[0]
            if rowsNeedingFreshMapping.contains(onlyRowIndex) {
                inputRows[onlyRowIndex].calories = normalizedTotalsCalories
                inputRows[onlyRowIndex].isApproximate = approximateDisplay
                inputRows[onlyRowIndex].calorieRangeText = approximateDisplay
                    ? estimatedCalorieRangeText(for: normalizedTotalsCalories)
                    : nil
                if let firstItem = response.items.first {
                    inputRows[onlyRowIndex].parsedItem = firstItem
                }
                inputRows[onlyRowIndex].parsedItems = response.items
                inputRows[onlyRowIndex].editableItemIndices = Array(response.items.indices)
                inputRows[onlyRowIndex].normalizedTextAtParse = HomeLoggingTextMatch.normalizedRowText(inputRows[onlyRowIndex].text)
            }
        }
    }

    private func estimatedCalorieRangeText(for calories: Int) -> String {
        let lower = max(0, Int((Double(calories) * 0.8).rounded()))
        let upper = max(lower + 1, Int((Double(calories) * 1.2).rounded()))
        return "\(lower)-\(upper) cal"
    }

    private func normalizedRowCalories(from rawCalories: Double, response: ParseLogResponse) -> Int? {
        let rounded = Int(rawCalories.rounded())
        guard rounded >= 0 else {
            return nil
        }

        // Keep non-Gemini clarification rows from showing empty zero values.
        if response.needsClarification && rounded == 0 && !isGeminiAuthoritativeResponse(response) {
            return nil
        }

        return rounded
    }

    private func isGeminiAuthoritativeResponse(_ response: ParseLogResponse) -> Bool {
        response.route == "gemini" && !response.items.isEmpty
    }

    private func debugRowParseMapping(
        response: ParseLogResponse,
        nonEmptyIndices: [Int],
        rowsNeedingFreshMapping: Set<Int>,
        lockedRowIndices: Set<Int>,
        mappedCaloriesByRow: [Int: Int]
    ) {
#if DEBUG
        let rowSummary = nonEmptyIndices.map { rowIndex in
            let action = rowsNeedingFreshMapping.contains(rowIndex) ? "update" : "keep"
            let lockState = lockedRowIndices.contains(rowIndex) ? "locked" : "free"
            let mapped = mappedCaloriesByRow[rowIndex].map(String.init) ?? "nil"
            let normalized = HomeLoggingTextMatch.normalizedRowText(inputRows[rowIndex].text)
            return "#\(rowIndex){action=\(action),lock=\(lockState),mapped=\(mapped),text=\(normalized)}"
        }.joined(separator: " | ")
        print("[parse_row_map] route=\(response.route) confidence=\(String(format: "%.3f", response.confidence)) rows=\(rowSummary)")
#endif
    }

    private func scheduleDetailsDrawer(for response: ParseLogResponse) {
        detailsDrawerMode = .full
    }

    private func canEscalate(_ result: ParseLogResponse) -> Bool {
        guard appStore.isNetworkReachable else { return false }
        guard result.needsClarification else { return false }
        guard !isEscalating else { return false }
        if result.budget.escalationAllowed == false {
            return false
        }
        if escalationBlockedCode == "ESCALATION_DISABLED" || escalationBlockedCode == "BUDGET_EXCEEDED" {
            return false
        }
        return true
    }

    private func escalationDisabledReason(_ result: ParseLogResponse) -> String? {
        if result.budget.escalationAllowed == false || escalationBlockedCode == "BUDGET_EXCEEDED" {
            return L10n.escalationBudgetReason
        }
        if escalationBlockedCode == "ESCALATION_DISABLED" {
            return L10n.escalationConfigReason
        }
        return nil
    }

    private func startEscalationFlow() {
        guard appStore.isNetworkReachable else {
            escalationError = L10n.noNetworkEscalate
            return
        }
        guard let parseResult else {
            escalationError = L10n.parseBeforeEscalation
            return
        }

        guard parseResult.needsClarification else {
            escalationError = L10n.escalationNotRequired
            return
        }

        if parseResult.budget.escalationAllowed == false {
            escalationBlockedCode = "BUDGET_EXCEEDED"
            escalationError = L10n.escalationBudgetBlocked
            return
        }

        Task {
            await escalateCurrentParse(parseResult)
        }
    }

    private func escalateCurrentParse(_ current: ParseLogResponse) async {
        isEscalating = true
        escalationError = nil
        escalationInfoMessage = nil
        defer { isEscalating = false }

        let request = EscalateParseRequest(
            parseRequestId: current.parseRequestId,
            loggedAt: current.loggedAt
        )

        do {
            let response = try await appStore.apiClient.escalateParse(request)
            parseResult = ParseLogResponse(
                requestId: response.requestId,
                parseRequestId: response.parseRequestId,
                parseVersion: response.parseVersion,
                route: response.route,
                cacheHit: false,
                sourcesUsed: response.sourcesUsed,
                fallbackUsed: false,
                fallbackModel: response.model,
                budget: response.budget,
                needsClarification: false,
                clarificationQuestions: [],
                reasonCodes: nil,
                retryAfterSeconds: nil,
                parseDurationMs: response.parseDurationMs,
                loggedAt: response.loggedAt,
                confidence: response.confidence,
                totals: response.totals,
                items: response.items,
                assumptions: [],
                cacheDebug: nil,
                inputKind: "text",
                extractedText: nil,
                imageMeta: nil,
                visionModel: nil,
                visionFallbackUsed: nil,
                dietaryFlags: nil
            )
            editableItems = response.items.map(EditableParsedItem.init(apiItem:))
            clearParseSchedulerState()
            if let parseResult {
                applyRowParseResult(parseResult)
            }
            parseInfoMessage = nil
            parseError = nil
            escalationBlockedCode = nil
            escalationError = nil
            escalationInfoMessage = L10n.escalationCompleted
            clearPendingSaveContext()
            appStore.setError(nil)
        } catch {
            handleAuthFailureIfNeeded(error)
            let mapped = userFriendlyEscalationError(error)
            escalationBlockedCode = mapped.blockCode
            escalationError = mapped.message
            escalationInfoMessage = nil
            appStore.setError(mapped.message)
        }
    }

    private var displayedTotals: NutritionTotals {
        if editableItems.isEmpty {
            return parseResult?.totals ?? NutritionTotals(calories: 0, protein: 0, carbs: 0, fat: 0)
        }

        let calories = editableItems.reduce(0.0) { $0 + $1.calories }
        let protein = editableItems.reduce(0.0) { $0 + $1.protein }
        let carbs = editableItems.reduce(0.0) { $0 + $1.carbs }
        let fat = editableItems.reduce(0.0) { $0 + $1.fat }
        return NutritionTotals(
            calories: HomeLoggingDisplayText.roundOneDecimal(calories),
            protein: HomeLoggingDisplayText.roundOneDecimal(protein),
            carbs: HomeLoggingDisplayText.roundOneDecimal(carbs),
            fat: HomeLoggingDisplayText.roundOneDecimal(fat)
        )
    }

    private func buildSaveDraftRequest() -> SaveLogRequest? {
        guard let parseResult else { return nil }
        guard !hasDirtyRowsPendingParse else { return nil }
        guard activeParseRowID == nil else { return nil }
        guard queuedParseRowIDs.isEmpty else { return nil }
        guard !hasActiveParseRequest else { return nil }
        guard !pendingFollowupRequested else { return nil }

        // Use the rawText that was actually sent to the backend for this parse.
        // For text parses, use the last completed row's rawText (fixes the 422
        // mismatch where trimmedNoteText included all rows but the parseRequest
        // stored only the individual row text).
        // For image parses without a committed row snapshot, fall back to trimmedNoteText.
        let rawText: String
        if let lastRow = activeParseSnapshots.last {
            rawText = lastRow.rawText
        } else {
            rawText = trimmedNoteText
        }
        guard !rawText.isEmpty else { return nil }
        let effectiveLoggedAt = HomeLoggingDateUtils.loggedAtFormatter.string(from: draftLoggedAt ?? draftTimestampForSelectedDate())
        let inputKind = normalizedInputKind(parseResult.inputKind, fallback: latestParseInputKind)
        let currentImageRef = pendingImageStorageRef ??
            inputRows.compactMap(\.imageRef).first
        var saveItems = editableItems.map { $0.asSaveParsedFoodItem() }
        if saveItems.isEmpty && hasVisibleUnsavedCalorieRows {
            saveItems = [
                fallbackSaveItem(
                    rawText: rawText,
                    totals: displayedTotals,
                    confidence: parseResult.confidence,
                    nutritionSourceId: parseResult.items.first?.nutritionSourceId
                )
            ]
        }
        guard !saveItems.isEmpty else { return nil }

        return SaveLogRequest(
            parseRequestId: parseResult.parseRequestId,
            parseVersion: parseResult.parseVersion,
            parsedLog: SaveLogBody(
                rawText: rawText,
                loggedAt: effectiveLoggedAt,
                inputKind: inputKind,
                imageRef: currentImageRef,
                confidence: parseResult.confidence,
                totals: displayedTotals,
                sourcesUsed: parseResult.sourcesUsed,
                assumptions: parseResult.assumptions,
                items: saveItems
            )
        )
    }

    private enum SaveIntent {
        case manual
        case retry
        case auto
        case dateChangeBackground
    }

    private struct SaveSubmissionResult {
        let didSucceed: Bool
        let savedDay: String?
    }

    private struct DateChangeDraftRow {
        let rowID: UUID
        let text: String
        let loggedAt: String
        let inputKind: String
    }

    private struct PreservedDateDraftRow {
        var row: HomeLogRow
        var isBackgroundManaged: Bool
    }

    private func startSaveFlow() {
        guard appStore.isNetworkReachable else {
            saveError = L10n.noNetworkSave
            return
        }

        guard let request = buildSaveDraftRequest() else {
            saveError = L10n.parseBeforeSave
            return
        }

        let fingerprint = saveRequestFingerprint(request)
        let requestToSave = request
        let idempotencyKey: UUID
        let isRetry: Bool

        if let pendingSaveIdempotencyKey, pendingSaveFingerprint == fingerprint {
            idempotencyKey = pendingSaveIdempotencyKey
            isRetry = true
        } else {
            idempotencyKey = UUID()
            pendingSaveFingerprint = fingerprint
            pendingSaveRequest = requestToSave
            pendingSaveIdempotencyKey = idempotencyKey
            persistPendingSaveContext(rowID: activeEditingRowID)
            isRetry = false
        }

        Task {
            await submitSave(
                request: requestToSave,
                idempotencyKey: idempotencyKey,
                isRetry: isRetry,
                intent: .manual
            )
        }
    }

    // MARK: - Quantity Fast-Path Persistence

    /// Called from the composer after the client-side quantity fast path
    /// rescales a row's items. Routes persistence based on whether the row
    /// was loaded from the server (serverLogId present → PATCH) or is a
    /// newly-composed row the user is still typing (serverLogId nil → let
    /// the existing auto-save/POST flow pick up the scaled items via
    /// buildRowSaveRequest).
    private func handleQuantityFastPathUpdate(rowID: UUID) {
        guard let row = inputRows.first(where: { $0.id == rowID }) else { return }

        if let serverLogId = row.serverLogId {
            schedulePatchUpdate(rowID: rowID, serverLogId: serverLogId)
        } else {
            // New row, not yet saved server-side. The existing auto-save
            // loop reads inputRows[rowID].parsedItems when building the save
            // request, so the scaled items will be persisted on the next
            // auto-save tick. Nudge the timer so the edit doesn't sit idle.
            if activeParseSnapshots.contains(where: { $0.rowID == rowID }) {
                scheduleAutoSave()
            }
        }
    }

    /// Debounced PATCH scheduler for edits to server-backed rows. If the
    /// user keeps adjusting the number, each keystroke cancels the previous
    /// task and restarts the timer — so one sustained edit session becomes
    /// one network call.
    private func schedulePatchUpdate(rowID: UUID, serverLogId: String) {
        pendingPatchTasks[rowID]?.cancel()
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: patchDebounceNs)
            guard !Task.isCancelled else { return }
            await performPatchUpdate(rowID: rowID, serverLogId: serverLogId)
        }
        pendingPatchTasks[rowID] = task
    }

    /// Build and dispatch the PATCH. Reads the row's CURRENT state at call
    /// time so we always persist the latest scaled values even if multiple
    /// edits were debounced together.
    private func performPatchUpdate(rowID: UUID, serverLogId: String) async {
        guard appStore.isNetworkReachable else {
            pendingPatchTasks[rowID] = nil
            saveError = L10n.noNetworkSave
            return
        }
        guard let row = inputRows.first(where: { $0.id == rowID }),
              !row.parsedItems.isEmpty else {
            pendingPatchTasks[rowID] = nil
            return
        }

        let items: [SaveParsedFoodItem] = row.parsedItems.map { item in
            SaveParsedFoodItem(
                name: item.name,
                quantity: item.amount ?? item.quantity,
                amount: item.amount ?? item.quantity,
                unit: item.unitNormalized ?? item.unit,
                unitNormalized: item.unitNormalized ?? item.unit,
                grams: item.grams,
                gramsPerUnit: item.gramsPerUnit,
                calories: item.calories,
                protein: item.protein,
                carbs: item.carbs,
                fat: item.fat,
                nutritionSourceId: item.nutritionSourceId,
                originalNutritionSourceId: item.originalNutritionSourceId,
                sourceFamily: item.sourceFamily,
                matchConfidence: item.matchConfidence,
                // Product rule: persist visible calorie rows without blocking on clarification.
                needsClarification: false,
                manualOverride: (item.manualOverride == true)
                    ? SaveManualOverride(enabled: true, reason: nil, editedFields: [])
                    : nil
            )
        }

        // Recompute totals from items so server validation passes.
        let totals = NutritionTotals(
            calories: row.parsedItems.reduce(0) { $0 + $1.calories },
            protein: row.parsedItems.reduce(0) { $0 + $1.protein },
            carbs: row.parsedItems.reduce(0) { $0 + $1.carbs },
            fat: row.parsedItems.reduce(0) { $0 + $1.fat }
        )

        // Intentionally pass loggedAt: nil so the backend preserves the
        // original food_logs.logged_at — a quantity fast-path edit shouldn't
        // "move" the entry to today just because the user adjusted a number.
        let body = PatchLogBody(
            rawText: row.text.trimmingCharacters(in: .whitespacesAndNewlines),
            loggedAt: nil,
            inputKind: "text",
            imageRef: row.imageRef,
            confidence: row.parsedItem.map { $0.matchConfidence } ?? 0.85,
            totals: totals,
            sourcesUsed: nil,
            assumptions: nil,
            items: items
        )
        let request = PatchLogRequest(
            parseRequestId: nil,
            parseVersion: nil,
            parsedLog: body
        )

        do {
            _ = try await appStore.apiClient.patchLog(id: serverLogId, request: request)
            // Re-mark the row as saved and invalidate the day cache so the
            // next refresh reads the updated totals. Use serverLoggedAt —
            // the original day — so we don't accidentally invalidate today's
            // cache for an edit to yesterday's entry.
            if let idx = inputRows.firstIndex(where: { $0.id == rowID }) {
                inputRows[idx].isSaved = true
            }
            let savedDay = HomeLoggingDateUtils.summaryDayString(
                fromLoggedAt: row.serverLoggedAt ?? summaryDateString,
                fallback: summaryDateString
            )
            await refreshDayAfterMutation(
                savedDay,
                postNutritionNotification: true,
                reconcilePendingQueueAfterLoad: true
            )
        } catch is CancellationError {
            return
        } catch {
            handleAuthFailureIfNeeded(error)
            // Keep the row editable so the user can try again; surface a
            // lightweight error without blocking the flow.
            saveError = userFriendlySaveError(error)
        }
        pendingPatchTasks[rowID] = nil
    }

    /// Convert a SaveLogRequest (POST-flavored) into a PatchLogRequest and
    /// send it to the backend. Preserves the parseRequestId/parseVersion
    /// from the save request since the edit did go through a fresh parse
    /// (the client-side fast path uses `performPatchUpdate` instead, which
    /// omits parse references).
    private func submitRowPatch(
        serverLogId: String,
        saveRequest: SaveLogRequest,
        rowID: UUID
    ) async {
        guard appStore.isNetworkReachable else { return }
        let startedAt = Date()
        saveAttemptTelemetry.emit(
            parseRequestId: saveRequest.parseRequestId,
            rowID: rowID,
            outcome: .attempted,
            errorCode: nil,
            latencyMs: nil,
            source: .patch
        )

        // Copy the SaveLogBody into a PatchLogBody, dropping loggedAt so the
        // backend keeps the original. A text-change edit with re-parse
        // shouldn't bump the entry forward in time.
        let src = saveRequest.parsedLog
        let patchBody = PatchLogBody(
            rawText: src.rawText,
            loggedAt: nil,
            inputKind: src.inputKind,
            imageRef: src.imageRef,
            confidence: src.confidence,
            totals: src.totals,
            sourcesUsed: src.sourcesUsed,
            assumptions: src.assumptions,
            items: src.items
        )
        let patchRequest = PatchLogRequest(
            parseRequestId: saveRequest.parseRequestId,
            parseVersion: saveRequest.parseVersion,
            parsedLog: patchBody
        )

        do {
            _ = try await appStore.apiClient.patchLog(id: serverLogId, request: patchRequest)
            saveAttemptTelemetry.emit(
                parseRequestId: saveRequest.parseRequestId,
                rowID: rowID,
                outcome: .succeeded,
                errorCode: nil,
                latencyMs: Int(elapsedMs(since: startedAt)),
                source: .patch
            )
            // Prefer the row's original loggedAt (the day the entry actually
            // belongs to) over the save request's loggedAt (which reflects
            // when the re-parse fired).
            let originalDay = inputRows.first(where: { $0.id == rowID })?.serverLoggedAt
            let savedDay = HomeLoggingDateUtils.summaryDayString(
                fromLoggedAt: originalDay ?? saveRequest.parsedLog.loggedAt,
                fallback: summaryDateString
            )
            if let idx = inputRows.firstIndex(where: { $0.id == rowID }) {
                inputRows[idx].isSaved = true
            }
            await refreshDayAfterMutation(savedDay)
        } catch is CancellationError {
            return
        } catch {
            handleAuthFailureIfNeeded(error)
            saveError = userFriendlySaveError(error)
            saveAttemptTelemetry.emit(
                parseRequestId: saveRequest.parseRequestId,
                rowID: rowID,
                outcome: .failed,
                errorCode: saveAttemptErrorCode(error),
                latencyMs: Int(elapsedMs(since: startedAt)),
                source: .patch
            )
        }
    }

    // MARK: - Delete Saved Row

    private func handleServerBackedRowCleared(_ row: HomeLogRow) {
        guard let deleteContext = serverBackedDeleteContext(for: row) else { return }
        let serverLogId = deleteContext.serverLogId

        isNoteEditorFocused = false
        activeEditingRowID = nil
        NotificationCenter.default.post(name: .dismissKeyboardFromTabBar, object: nil)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        clearTransientWorkForDeletedRow(rowID: row.id)
        _ = removePendingSaveQueueItems(forRowID: row.id)
        locallyDeletedPendingRowIDs.remove(row.id)
        pendingDeleteTasks[row.id]?.cancel()

        let originalIndex = inputRows.firstIndex(where: { $0.id == row.id }) ?? inputRows.count
        var restoredRow = row
        restoredRow.serverLogId = serverLogId
        restoredRow.serverLoggedAt = restoredRow.serverLoggedAt ?? deleteContext.savedDay
        restoredRow.isSaved = true
        restoredRow.parsePhase = .idle
        restoredRow.isDeleting = false

        if let index = inputRows.firstIndex(where: { $0.id == row.id }) {
            inputRows[index] = restoredRow
            inputRows[index].isDeleting = true
        }

        let savedDay = deleteContext.savedDay
        removeDeletedLogFromVisibleDayLogs(logId: serverLogId, dateString: savedDay)
        saveError = nil

        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                inputRows.removeAll { $0.id == row.id }
                if inputRows.allSatisfy({ $0.isSaved }) {
                    inputRows.append(.empty())
                }
            }
            await deleteServerBackedRow(
                row: restoredRow,
                serverLogId: serverLogId,
                savedDay: savedDay,
                originalIndex: originalIndex
            )
        }
        pendingDeleteTasks[row.id] = task
    }

    private func serverBackedDeleteContext(for row: HomeLogRow) -> (serverLogId: String, savedDay: String)? {
        if let serverLogId = row.serverLogId {
            return (
                serverLogId,
                HomeLoggingDateUtils.summaryDayString(
                    fromLoggedAt: row.serverLoggedAt ?? summaryDateString,
                    fallback: summaryDateString
                )
            )
        }

        guard let queuedItem = pendingQueueItem(forRowID: row.id),
              let serverLogId = queuedItem.serverLogId else {
            return nil
        }

        return (serverLogId, queuedItem.dateString)
    }

    private func clearTransientWorkForDeletedRow(rowID: UUID) {
        pendingPatchTasks[rowID]?.cancel()
        pendingPatchTasks[rowID] = nil

        if activeParseRowID == rowID {
            parseTask?.cancel()
            parseTask = nil
            activeParseRowID = nil
            parseCoordinator.cancelInFlight(rowID: rowID)
        }
        queuedParseRowIDs.removeAll { $0 == rowID }
        if inFlightParseSnapshot?.activeRowID == rowID {
            inFlightParseSnapshot = nil
        }

        let removedParseIDs = activeParseSnapshots
            .filter { $0.rowID == rowID }
            .map(\.parseRequestId)
        if !removedParseIDs.isEmpty {
            autoSavedParseIDs.subtract(removedParseIDs)
        }
        parseCoordinator.removeSnapshot(rowID: rowID)
        synchronizeParseOwnership()
    }

    private func deleteServerBackedRow(
        row: HomeLogRow,
        serverLogId: String,
        savedDay: String,
        originalIndex: Int
    ) async {
        defer { pendingDeleteTasks[row.id] = nil }

        guard appStore.isNetworkReachable else {
            restoreDeletedRow(row, at: originalIndex)
            saveError = L10n.noNetworkSave
            return
        }

        do {
            let response = try await appStore.apiClient.deleteLog(id: serverLogId)
            await deleteSavedLogFromAppleHealthIfEnabled(row: row, healthSync: response.healthSync)
            await refreshDayAfterMutation(savedDay)
        } catch is CancellationError {
            return
        } catch {
            handleAuthFailureIfNeeded(error)
            restoreDeletedRow(row, at: originalIndex)
            saveError = userFriendlySaveError(error)
        }
    }

    private func restoreDeletedRow(_ row: HomeLogRow, at originalIndex: Int) {
        guard !inputRows.contains(where: { $0.id == row.id }) else { return }
        var restored = row
        restored.isDeleting = false
        let insertIndex = min(max(originalIndex, 0), inputRows.count)
        inputRows.insert(restored, at: insertIndex)
    }

    private func removeDeletedLogFromVisibleDayLogs(logId: String, dateString: String) {
        guard summaryDateString == dateString else { return }
        if let existing = dayLogs, existing.date == dateString {
            dayLogs = DayLogsResponse(
                date: existing.date,
                timezone: existing.timezone,
                logs: existing.logs.filter { $0.id != logId }
            )
        }
        if let cached = dayCacheLogs[dateString] {
            dayCacheLogs[dateString] = DayLogsResponse(
                date: cached.date,
                timezone: cached.timezone,
                logs: cached.logs.filter { $0.id != logId }
            )
        }
    }

    private func refreshDayAfterMutation(
        _ dateString: String,
        postNutritionNotification: Bool = true,
        reconcilePendingQueueAfterLoad: Bool = false
    ) async {
        invalidateDayCache(for: dateString)
        await loadDaySummary(forcedDate: dateString, skipCache: true)
        await loadDayLogs(forcedDate: dateString, skipCache: true)

        if reconcilePendingQueueAfterLoad, let logs = dayLogs, logs.date == dateString {
            reconcilePendingSaveQueue(with: logs.logs, for: dateString)
        }

        if postNutritionNotification {
            NotificationCenter.default.post(
                name: .nutritionProgressDidChange,
                object: nil,
                userInfo: ["savedDay": dateString]
            )
        }
    }

    private func cancelAutoSaveTask() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
    }

    private func scheduleAutoSaveTask(
        after delayNs: UInt64,
        forceReschedule: Bool = false
    ) {
        if forceReschedule {
            cancelAutoSaveTask()
        } else if autoSaveTask != nil {
            return
        }

        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                autoSaveTask = nil
            }
            await autoSaveIfNeeded()
        }
    }

    private func retryLastSave() {
        guard appStore.isNetworkReachable else {
            saveError = L10n.noNetworkRetry
            return
        }
        guard let pendingSaveRequest, let pendingSaveIdempotencyKey else {
            saveError = L10n.noPreviousRetry
            return
        }

        Task {
            await submitSave(
                request: pendingSaveRequest,
                idempotencyKey: pendingSaveIdempotencyKey,
                isRetry: true,
                intent: .retry
            )
        }
    }

    private func scheduleAutoSave() {
        // Persist each pending row's context immediately so drafts survive
        // an app close during the auto-save delay window.
        let saveableEntries = activeParseSnapshots.filter(isAutoSaveEligibleEntry(_:))

        for entry in saveableEntries {
            guard let request = buildRowSaveRequest(for: entry) else { continue }
            let key = resolveIdempotencyKey(forRowID: entry.rowID)
            upsertPendingSaveQueueItem(
                request: request,
                fingerprint: saveRequestFingerprint(request),
                idempotencyKey: key,
                rowID: entry.rowID
            )
            saveAttemptTelemetry.emit(
                parseRequestId: entry.parseRequestId,
                rowID: entry.rowID,
                outcome: .attempted,
                errorCode: nil,
                latencyMs: nil,
                source: .auto
            )
        }
        scheduleAutoSaveTask(after: autoSaveDelayNs)
    }

    private func rescheduleAutoSaveAfterActiveSave() {
        scheduleAutoSaveTask(after: 500_000_000, forceReschedule: true)
    }

    private var hasSaveableRowsPending: Bool {
        activeParseSnapshots.contains(where: { isAutoSaveEligibleEntry($0) }) ||
            hasQueuedPendingSaves
    }

    private var hasQueuedPendingSaves: Bool {
        pendingSaveQueue.contains { item in
            item.serverLogId == nil && UUID(uuidString: item.idempotencyKey) != nil
        }
    }

    private func autoSaveIfNeeded() async {
        guard appStore.isNetworkReachable else { return }
        guard !isSaving else {
            if hasSaveableRowsPending {
                rescheduleAutoSaveAfterActiveSave()
            }
            return
        }

        if await flushQueuedPendingSavesIfNeeded() {
            return
        }

        // Save each completed row independently using the per-row rawText.
        // This fixes the 422 mismatch: each save request uses the exact rawText
        // that was stored in parse_requests on the backend.
        let snapshots = activeParseSnapshots
        let rowsToSave = snapshots.filter(isAutoSaveEligibleEntry(_:))
        let saveableRowIDs = Set(rowsToSave.map(\.rowID))
        for entry in snapshots {
            guard let row = inputRows.first(where: { $0.id == entry.rowID }),
                  row.calories != nil,
                  !saveableRowIDs.contains(entry.rowID) else {
                continue
            }
            let skippedOutcome: SaveAttemptOutcome = autoSavedParseIDs.contains(entry.parseRequestId)
                ? .skippedDuplicate
                : .skippedNoEligibleState
            saveAttemptTelemetry.emit(
                parseRequestId: entry.parseRequestId,
                rowID: entry.rowID,
                outcome: skippedOutcome,
                errorCode: nil,
                latencyMs: nil,
                source: .auto
            )
        }

        for entry in rowsToSave {
            guard let request = buildRowSaveRequest(for: entry) else { continue }

            // If the row was loaded from the server (has a serverLogId),
            // this is an EDIT — not a new entry. Route through PATCH so the
            // backend updates the existing food_log instead of POSTing a
            // duplicate. Covers the case where the user opens a saved row,
            // changes more than just the quantity (triggering a full
            // re-parse), and the standard auto-save fires.
            let row = inputRows.first(where: { $0.id == entry.rowID })
            if let serverLogId = row?.serverLogId ?? pendingQueueItem(forRowID: entry.rowID)?.serverLogId {
                autoSavedParseIDs.insert(entry.parseRequestId)
                await submitRowPatch(
                    serverLogId: serverLogId,
                    saveRequest: request,
                    rowID: entry.rowID
                )
                continue
            }

            // Reuse the queued key for this row so retries / repeated auto-save
            // passes cannot create duplicate rows with new idempotency keys.
            let idempotencyKey = resolveIdempotencyKey(forRowID: entry.rowID)
            pendingSaveFingerprint = saveRequestFingerprint(request)
            pendingSaveRequest = request
            pendingSaveIdempotencyKey = idempotencyKey
            persistPendingSaveContext(rowID: entry.rowID)

            // Mark before the call so a retry loop can't stack up (idempotency key
            // on the backend is the real guard against duplicate writes).
            autoSavedParseIDs.insert(entry.parseRequestId)

            await submitSave(
                request: request,
                idempotencyKey: idempotencyKey,
                isRetry: false,
                intent: .auto
            )
        }

        // Fall back to the single-request image path when no row snapshots exist.
        if snapshots.isEmpty {
            guard parseResult != nil else { return }
            guard hasVisibleUnsavedCalorieRows else { return }
            guard let request = buildSaveDraftRequest() else { return }
            let contentFingerprint = autoSaveContentFingerprint(request)
            if contentFingerprint == lastAutoSavedContentFingerprint { return }
            let pendingImageRowID = inputRows.first(where: { !$0.isSaved && $0.imagePreviewData != nil })?.id
            let idempotencyKey = resolveIdempotencyKey(forRowID: pendingImageRowID)
            pendingSaveFingerprint = saveRequestFingerprint(request)
            pendingSaveRequest = request
            pendingSaveIdempotencyKey = idempotencyKey
            persistPendingSaveContext(
                rowID: pendingImageRowID,
                imageUploadData: pendingImageData,
                imagePreviewData: pendingImagePreviewData,
                imageMimeType: pendingImageMimeType
            )
            await submitSave(request: request, idempotencyKey: idempotencyKey, isRetry: false, intent: .auto)
        }
    }

    @discardableResult
    private func flushQueuedPendingSavesIfNeeded() async -> Bool {
        let candidates = saveCoordinator.consumeSubmissionCandidates()
        syncPendingQueueFromCoordinator(refreshRetryState: true)

        guard !candidates.isEmpty else { return false }

        var refreshDates: Set<String> = []

        for candidate in candidates {
            let result = await submitSave(
                request: candidate.item.request,
                idempotencyKey: candidate.idempotencyKey,
                isRetry: (candidate.item.attemptCount ?? 0) > 0,
                intent: .auto,
                deferRefresh: true
            )
            if let savedDay = result.savedDay {
                refreshDates.insert(savedDay)
            }
        }

        for savedDay in refreshDates.sorted() {
            await refreshDayAfterMutation(savedDay)
        }

        return true
    }

    /// Forces a pending auto-save to fire RIGHT NOW instead of waiting for the
    /// 10-second debounce. Called before a date change so typed entries aren't
    /// lost when the user swipes away mid-debounce. Safe to call even if nothing
    /// is eligible — it just returns quickly.
    private func flushPendingAutoSaveIfEligible() async {
        // Bail early if nothing to save
        let snapshots = activeParseSnapshots
        let hasCompletedRow = snapshots.contains(where: { isAutoSaveEligibleEntry($0) })
        let hasLegacyParse = snapshots.isEmpty &&
            parseResult != nil &&
            hasVisibleUnsavedCalorieRows

        guard hasCompletedRow || hasLegacyParse || hasQueuedPendingSaves else { return }

        // Cancel the debounced auto-save task and run immediately
        cancelAutoSaveTask()
        await autoSaveIfNeeded()
    }

    private func isAutoSaveEligibleEntry(_ entry: ParseSnapshot) -> Bool {
        SaveEligibility.isRowEligible(
            row: inputRows.first(where: { $0.id == entry.rowID }),
            snapshot: entry,
            autoSavedParseIDs: autoSavedParseIDs
        )
    }

    private var hasVisibleUnsavedCalorieRows: Bool {
        inputRows.contains { row in
            !row.isSaved && row.calories != nil
        }
    }

    /// Build a save request for one completed row using that row's individual rawText.
    ///
    /// Item source priority:
    /// 1. The row's current `parsedItems` — captures any client-side scaling
    ///    from the quantity fast path (e.g. user changed "3" to "4" after the
    ///    parse landed). This is the authoritative UI state.
    /// 2. `entry.rowItems` — the snapshot captured when the parse response
    ///    was applied. Used when the row is no longer in `inputRows` (e.g.
    ///    cleared between save-loop iterations).
    /// 3. `response.items` — last resort. Only correct for single-row parses.
    private func buildRowSaveRequest(for entry: ParseSnapshot) -> SaveLogRequest? {
        let response = entry.response
        let currentRow = inputRows.first(where: { $0.id == entry.rowID })
        let sourceItems: [ParsedFoodItem]
        if let row = currentRow, !row.parsedItems.isEmpty {
            sourceItems = row.parsedItems
        } else if let row = currentRow, let singleItem = row.parsedItem {
            sourceItems = [singleItem]
        } else if !entry.rowItems.isEmpty {
            sourceItems = entry.rowItems
        } else {
            sourceItems = response.items
        }
        let effectiveLoggedAt = entry.loggedAt
        let items: [SaveParsedFoodItem]
        if sourceItems.isEmpty {
            let hasDisplayedCalories = currentRow?.calories != nil || response.totals.calories > 0
            guard hasDisplayedCalories else { return nil }
            let fallbackTotals = NutritionTotals(
                calories: Double(currentRow?.calories ?? Int(response.totals.calories.rounded())),
                protein: response.totals.protein,
                carbs: response.totals.carbs,
                fat: response.totals.fat
            )
            items = [
                fallbackSaveItem(
                    rawText: entry.rawText,
                    totals: fallbackTotals,
                    confidence: response.confidence,
                    nutritionSourceId: currentRow?.parsedItem?.nutritionSourceId ?? response.items.first?.nutritionSourceId
                )
            ]
        } else {
            items = sourceItems.map { item in
                SaveParsedFoodItem(
                    name: item.name,
                    quantity: item.amount ?? item.quantity,
                    amount: item.amount ?? item.quantity,
                    unit: item.unitNormalized ?? item.unit,
                    unitNormalized: item.unitNormalized ?? item.unit,
                    grams: item.grams,
                    gramsPerUnit: item.gramsPerUnit,
                    calories: item.calories,
                    protein: item.protein,
                    carbs: item.carbs,
                    fat: item.fat,
                    nutritionSourceId: item.nutritionSourceId,
                    originalNutritionSourceId: item.originalNutritionSourceId,
                    sourceFamily: item.sourceFamily,
                    matchConfidence: item.matchConfidence,
                    // Product rule: persist visible calorie rows without blocking on clarification.
                    needsClarification: false,
                    manualOverride: (item.manualOverride == true)
                        ? SaveManualOverride(enabled: true, reason: nil, editedFields: [])
                        : nil
                )
            }
        }
        guard !items.isEmpty else { return nil }
        let rowTotals = NutritionTotals(
            calories: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.calories }),
            protein: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.protein }),
            carbs: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.carbs }),
            fat: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.fat })
        )

        return SaveLogRequest(
            parseRequestId: entry.parseRequestId,
            parseVersion: entry.parseVersion,
            parsedLog: SaveLogBody(
                rawText: entry.rawText,
                loggedAt: effectiveLoggedAt,
                inputKind: normalizedInputKind(response.inputKind, fallback: "text"),
                imageRef: nil,
                confidence: response.confidence,
                totals: rowTotals,
                sourcesUsed: response.sourcesUsed,
                assumptions: response.assumptions,
                items: items
            )
        )
    }

    private func buildDateChangeDraftSaveRequest(
        draft: DateChangeDraftRow,
        response: ParseLogResponse
    ) -> SaveLogRequest? {
        let sourceItems = response.items
        let items: [SaveParsedFoodItem]

        if sourceItems.isEmpty {
            guard response.totals.calories > 0 || isTrustedZeroNutritionResponse(response) else {
                return nil
            }
            items = [
                fallbackSaveItem(
                    rawText: draft.text,
                    totals: response.totals,
                    confidence: response.confidence,
                    nutritionSourceId: response.items.first?.nutritionSourceId
                )
            ]
        } else {
            items = sourceItems.map { item in
                SaveParsedFoodItem(
                    name: item.name,
                    quantity: item.amount ?? item.quantity,
                    amount: item.amount ?? item.quantity,
                    unit: item.unitNormalized ?? item.unit,
                    unitNormalized: item.unitNormalized ?? item.unit,
                    grams: item.grams,
                    gramsPerUnit: item.gramsPerUnit,
                    calories: item.calories,
                    protein: item.protein,
                    carbs: item.carbs,
                    fat: item.fat,
                    nutritionSourceId: item.nutritionSourceId,
                    originalNutritionSourceId: item.originalNutritionSourceId,
                    sourceFamily: item.sourceFamily,
                    matchConfidence: item.matchConfidence,
                    needsClarification: false,
                    manualOverride: (item.manualOverride == true)
                        ? SaveManualOverride(enabled: true, reason: nil, editedFields: [])
                        : nil
                )
            }
        }

        guard !items.isEmpty else { return nil }

        let rowTotals = NutritionTotals(
            calories: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.calories }),
            protein: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.protein }),
            carbs: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.carbs }),
            fat: HomeLoggingDisplayText.roundOneDecimal(items.reduce(0) { $0 + $1.fat })
        )

        return SaveLogRequest(
            parseRequestId: response.parseRequestId,
            parseVersion: response.parseVersion,
            parsedLog: SaveLogBody(
                rawText: canonicalParseRawText(response: response, fallbackRawText: draft.text),
                loggedAt: draft.loggedAt,
                inputKind: draft.inputKind,
                imageRef: nil,
                confidence: response.confidence,
                totals: rowTotals,
                sourcesUsed: response.sourcesUsed,
                assumptions: response.assumptions,
                items: items
            )
        )
    }

    private func fallbackSaveItem(
        rawText: String,
        totals: NutritionTotals,
        confidence: Double,
        nutritionSourceId: String?
    ) -> SaveParsedFoodItem {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemName = trimmedText.isEmpty ? "Meal estimate" : trimmedText
        let sourceId = nutritionSourceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSourceId = (sourceId?.isEmpty == false) ? sourceId! : kUnresolvedPlaceholderSourceId

        let calories = HomeLoggingDisplayText.roundOneDecimal(max(0, totals.calories))
        let protein = HomeLoggingDisplayText.roundOneDecimal(max(0, totals.protein))
        let carbs = HomeLoggingDisplayText.roundOneDecimal(max(0, totals.carbs))
        let fat = HomeLoggingDisplayText.roundOneDecimal(max(0, totals.fat))
        let clampedConfidence = min(max(confidence, 0), 1)

        return SaveParsedFoodItem(
            name: itemName,
            quantity: 1,
            amount: 1,
            unit: "serving",
            unitNormalized: "serving",
            // This is a synthetic fallback item for a displayed calorie
            // estimate, not a real serving-weight measurement. Persist a
            // neutral placeholder instead of corrupting grams with calorie
            // values (e.g. 650 cal -> 650 g).
            grams: 1,
            gramsPerUnit: 1,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            nutritionSourceId: resolvedSourceId,
            originalNutritionSourceId: resolvedSourceId,
            sourceFamily: nil,
            matchConfidence: clampedConfidence,
            needsClarification: false,
            manualOverride: nil
        )
    }

    private func autoSaveContentFingerprint(_ request: SaveLogRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        struct Payload: Codable {
            let parseRequestId: String
            let rawText: String
            let inputKind: String?
            let imageRef: String?
            let totals: NutritionTotals
            let items: [SaveParsedFoodItem]
        }
        let payload = Payload(
            parseRequestId: request.parseRequestId,
            rawText: request.parsedLog.rawText,
            inputKind: request.parsedLog.inputKind,
            imageRef: request.parsedLog.imageRef,
            totals: request.parsedLog.totals,
            items: request.parsedLog.items
        )
        guard let data = try? encoder.encode(payload) else {
            return UUID().uuidString
        }
        return data.base64EncodedString()
    }

    private func normalizedInputKind(_ rawValue: String?, fallback: String = "text") -> String {
        HomeLoggingRowFactory.normalizedInputKind(rawValue, fallback: fallback)
    }

    private func requestWithImageRef(_ request: SaveLogRequest, imageRef: String?) -> SaveLogRequest {
        SaveLogRequest(
            parseRequestId: request.parseRequestId,
            parseVersion: request.parseVersion,
            parsedLog: SaveLogBody(
                rawText: request.parsedLog.rawText,
                loggedAt: request.parsedLog.loggedAt,
                inputKind: normalizedInputKind(request.parsedLog.inputKind, fallback: latestParseInputKind),
                imageRef: imageRef,
                confidence: request.parsedLog.confidence,
                totals: request.parsedLog.totals,
                sourcesUsed: request.parsedLog.sourcesUsed,
                assumptions: request.parsedLog.assumptions,
                items: request.parsedLog.items
            )
        )
    }

    private func prepareSaveRequestForNetwork(_ request: SaveLogRequest, idempotencyKey: UUID) async throws -> SaveLogRequest {
        var prepared = request
        let kind = normalizedInputKind(prepared.parsedLog.inputKind, fallback: latestParseInputKind)
        let queuedItem = pendingQueueItem(for: idempotencyKey)

        if kind == "image" {
            if let existingRef = pendingImageStorageRef ?? prepared.parsedLog.imageRef,
               !existingRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prepared = requestWithImageRef(prepared, imageRef: existingRef)
            } else if let imageData = pendingImageData ?? queuedItem?.imageUploadData ?? inputRows.compactMap(\.imagePreviewData).first {
                // Image upload is decoupled from save: nutrition data must
                // never be lost just because Supabase Storage is unhappy.
                // We attempt the upload inline so the food_log can land
                // with image_ref populated on the happy path; if anything
                // throws (missing bucket, expired Supabase JWT, network
                // blip, RLS misconfig…), we stash the bytes and retry the
                // upload + PATCH /v1/logs/:id/image-ref once the save
                // succeeds. The user gets their meal logged either way.
                do {
                    let imageRef = try await appStore.imageStorageService.uploadJPEG(
                        imageData,
                        userIdentifierHint: appStore.authSessionStore.session?.userID
                    )
                    pendingImageStorageRef = imageRef
                    prepared = requestWithImageRef(prepared, imageRef: imageRef)
                    for index in inputRows.indices where inputRows[index].imagePreviewData != nil {
                        inputRows[index].imageRef = imageRef
                    }
                } catch {
                    let queueKey = idempotencyKey.uuidString.lowercased()
                    deferredImageUploads[queueKey] = imageData
                    NSLog("[MainLogging] Inline image upload failed; deferring to post-save retry: \(error)")
                    // Leave prepared with imageRef = nil so the save proceeds.
                }
            }
        }

        if pendingSaveIdempotencyKey == idempotencyKey {
            pendingSaveRequest = prepared
            pendingSaveFingerprint = saveRequestFingerprint(prepared)
            persistPendingSaveContext()
        }
        if containsPendingQueueItem(for: idempotencyKey) {
            upsertPendingSaveQueueItem(
                request: prepared,
                fingerprint: saveRequestFingerprint(prepared),
                idempotencyKey: idempotencyKey,
                rowID: queuedItem?.rowID,
                imageUploadData: queuedItem?.imageUploadData,
                imagePreviewData: queuedItem?.imagePreviewData,
                imageMimeType: queuedItem?.imageMimeType,
                serverLogId: queuedItem?.serverLogId
            )
        }

        return prepared
    }

    @discardableResult
    private func submitSave(
        request: SaveLogRequest,
        idempotencyKey: UUID,
        isRetry: Bool,
        intent: SaveIntent,
        deferRefresh: Bool = false
    ) async -> SaveSubmissionResult {
        let queueKey = idempotencyKey.uuidString.lowercased()
        let submittedRowID = pendingQueueItem(for: idempotencyKey)?.rowID
        let telemetryRowID = submittedRowID ?? UUID()
        let startedAt = Date()
        saveAttemptTelemetry.emit(
            parseRequestId: request.parseRequestId,
            rowID: telemetryRowID,
            outcome: .attempted,
            errorCode: nil,
            latencyMs: nil,
            source: telemetrySource(for: intent)
        )
        isSaving = true
        saveError = nil
        markPendingSaveAttemptStarted(idempotencyKey: idempotencyKey)
        defer { isSaving = false }

        let executionResult = await saveCoordinator.executeSaveResult(
            request: request,
            idempotencyKey: idempotencyKey,
            prepareForNetwork: { request, key in
                try await prepareSaveRequestForNetwork(request, idempotencyKey: key)
            }
        )

        switch executionResult {
        case .success(let success):
            let savedDay = await handleSubmitSaveSuccess(
                success,
                queueKey: queueKey,
                submittedRowID: submittedRowID,
                telemetryRowID: telemetryRowID,
                idempotencyKey: idempotencyKey,
                intent: intent,
                isRetry: isRetry,
                startedAt: startedAt,
                deferRefresh: deferRefresh
            )
            return SaveSubmissionResult(didSucceed: true, savedDay: savedDay)
        case .failure(let failure):
            await handleSubmitSaveFailure(
                failure,
                telemetryRowID: telemetryRowID,
                idempotencyKey: idempotencyKey,
                intent: intent,
                isRetry: isRetry,
                startedAt: startedAt
            )
            return SaveSubmissionResult(didSucceed: false, savedDay: nil)
        }
    }

    private func handleSubmitSaveSuccess(
        _ success: SaveExecutionSuccess,
        queueKey: String,
        submittedRowID: UUID?,
        telemetryRowID: UUID,
        idempotencyKey: UUID,
        intent: SaveIntent,
        isRetry: Bool,
        startedAt: Date,
        deferRefresh: Bool
    ) async -> String {
        let effectiveRequest = success.preparedRequest
        let response = success.response
        let savedDay = HomeLoggingDateUtils.summaryDayString(
            fromLoggedAt: effectiveRequest.parsedLog.loggedAt,
            fallback: summaryDateString
        )
        if shouldDiscardCompletedSave(queueKey: queueKey, rowID: submittedRowID) {
            await deleteLateArrivingSave(logId: response.logId, savedDay: savedDay, queueKey: queueKey, rowID: submittedRowID)
            return savedDay
        }

        let prefix = isRetry ? L10n.retrySucceededPrefix : L10n.savedSuccessfullyPrefix
        let timeToLogMs = flowStartedAt.map { elapsedMs(since: $0) }
        if intent == .auto {
            saveSuccessMessage = nil
            lastAutoSavedContentFingerprint = autoSaveContentFingerprint(effectiveRequest)
        } else if intent == .dateChangeBackground {
            saveSuccessMessage = nil
        } else {
            if let timeToLogMs {
                saveSuccessMessage = L10n.saveSuccessWithTTL(prefix: prefix, logID: response.logId, day: savedDay, ttlSeconds: timeToLogMs / 1000)
                lastTimeToLogMs = timeToLogMs
            } else {
                saveSuccessMessage = L10n.saveSuccessWithoutTTL(prefix: prefix, logID: response.logId, day: savedDay)
            }
        }

        let syncedToHealth = await syncSavedLogToAppleHealthIfEnabled(effectiveRequest, response: response)
        if syncedToHealth {
            if intent == .auto {
                saveSuccessMessage = nil
            } else if let current = saveSuccessMessage, !current.isEmpty {
                saveSuccessMessage = "\(current) • Synced to Apple Health"
            }
        }

        saveError = nil
        appStore.setError(nil)
        emitSaveTelemetrySuccess(
            request: effectiveRequest,
            durationMs: elapsedMs(since: startedAt),
            isRetry: isRetry,
            logId: response.logId,
            timeToLogMs: timeToLogMs
        )
        saveAttemptTelemetry.emit(
            parseRequestId: effectiveRequest.parseRequestId,
            rowID: telemetryRowID,
            outcome: .succeeded,
            errorCode: nil,
            latencyMs: Int(elapsedMs(since: startedAt)),
            source: telemetrySource(for: intent)
        )
        markPendingSaveSucceeded(
            idempotencyKey: idempotencyKey,
            logId: response.logId,
            preparedRequest: effectiveRequest
        )
        if let submittedRowID {
            removePreservedDateDraft(rowID: submittedRowID, for: savedDay)
        }
        // If the inline image upload failed during
        // prepareSaveRequestForNetwork (Supabase storage unhappy, network
        // blip, expired storage JWT, missing bucket), the bytes were
        // stashed in deferredImageUploads. Now that the food_log row is
        // durable, retry the upload + PATCH the image_ref in a detached
        // task so the user's meal is saved and the photo attaches when
        // storage cooperates.
        scheduleDeferredImageUploadRetry(
            idempotencyKey: idempotencyKey,
            logId: response.logId,
            inputKind: effectiveRequest.parsedLog.inputKind ?? latestParseInputKind
        )
        if intent != .dateChangeBackground {
            clearPendingSaveContext()
        }
        if intent == .manual || intent == .retry {
            flowStartedAt = nil
            draftLoggedAt = nil
        }
        if intent != .dateChangeBackground,
           let parsedDate = HomeLoggingDateUtils.summaryRequestFormatter.date(from: savedDay) {
            selectedSummaryDate = parsedDate
        }
        if intent != .dateChangeBackground || savedDay == summaryDateString {
            promoteSavedRow(
                for: effectiveRequest,
                idempotencyKey: idempotencyKey,
                logId: response.logId
            )
        }
        // Cancel prefetch to prevent it from re-populating cache with stale data
        prefetchTask?.cancel()
        if intent == .dateChangeBackground, savedDay != summaryDateString {
            invalidateDayCache(for: savedDay)
            NotificationCenter.default.post(
                name: .nutritionProgressDidChange,
                object: nil,
                userInfo: ["savedDay": savedDay]
            )
        } else if deferRefresh {
            invalidateDayCache(for: savedDay)
        } else {
            await refreshDayAfterMutation(savedDay)
        }
        return savedDay
    }

    private func handleSubmitSaveFailure(
        _ failure: SaveExecutionFailure,
        telemetryRowID: UUID,
        idempotencyKey: UUID,
        intent: SaveIntent,
        isRetry: Bool,
        startedAt: Date
    ) async {
        let effectiveRequest = failure.effectiveRequest
        let error = failure.error
        saveSuccessMessage = nil
        handleAuthFailureIfNeeded(error)
        let message: String
        if error is ImageStorageServiceError {
            message = (error as? LocalizedError)?.errorDescription ?? "Image upload failed."
        } else {
            message = userFriendlySaveError(error)
        }
        if intent == .dateChangeBackground {
            _ = saveCoordinator.handleFailure(
                idempotencyKey: idempotencyKey,
                message: message,
                error: error
            )
            syncPendingQueueFromCoordinator(refreshRetryState: true)
            emitSaveTelemetryFailure(
                request: effectiveRequest,
                error: error,
                durationMs: elapsedMs(since: startedAt),
                isRetry: isRetry
            )
            saveAttemptTelemetry.emit(
                parseRequestId: effectiveRequest.parseRequestId,
                rowID: telemetryRowID,
                outcome: .failed,
                errorCode: saveAttemptErrorCode(error),
                latencyMs: Int(elapsedMs(since: startedAt)),
                source: telemetrySource(for: intent)
            )
            return
        }
        saveError = message
        appStore.setError(message)
        await handlePendingSaveFailure(
            idempotencyKey: idempotencyKey,
            request: effectiveRequest,
            error: error,
            message: message
        )
        emitSaveTelemetryFailure(
            request: effectiveRequest,
            error: error,
            durationMs: elapsedMs(since: startedAt),
            isRetry: isRetry
        )
        saveAttemptTelemetry.emit(
            parseRequestId: effectiveRequest.parseRequestId,
            rowID: telemetryRowID,
            outcome: .failed,
            errorCode: saveAttemptErrorCode(error),
            latencyMs: Int(elapsedMs(since: startedAt)),
            source: telemetrySource(for: intent)
        )
    }

    private func shouldDiscardCompletedSave(queueKey: String, rowID: UUID?) -> Bool {
        locallyDeletedPendingSaveKeys.contains(queueKey) ||
            rowID.map { locallyDeletedPendingRowIDs.contains($0) } == true
    }

    private func deleteLateArrivingSave(logId: String, savedDay: String, queueKey: String, rowID: UUID?) async {
        removePendingSave(idempotencyKey: queueKey)
        locallyDeletedPendingSaveKeys.remove(queueKey)
        if let rowID {
            locallyDeletedPendingRowIDs.remove(rowID)
        }

        do {
            try await saveCoordinator.deleteLog(id: logId)
            await refreshDayAfterMutation(savedDay)
        } catch {
            handleAuthFailureIfNeeded(error)
            saveError = userFriendlySaveError(error)
        }
    }

    /// Retries an image upload that failed during the inline path inside
    /// `prepareSaveRequestForNetwork`. By the time this runs, the food_log
    /// row is already saved without an image_ref — we just need to attach
    /// the photo when storage cooperates.
    ///
    /// Persistence model:
    ///
    ///   1. The bytes are written to the on-disk
    ///      `DeferredImageUploadStore` keyed by `logId` BEFORE the retry
    ///      task fires, so a force-quit between save success and the
    ///      detached upload doesn't lose the photo.
    ///   2. The detached task tries the upload + `PATCH /image-ref`. On
    ///      success it removes the disk entry. On failure the entry stays;
    ///      `AppStore.drainDeferredImageUploads()` picks it up at the next
    ///      launch (or whenever the user re-auths).
    ///   3. If the disk store is unavailable (init failed), behavior
    ///      degrades to in-memory-only — same as before this commit.
    ///
    /// The meal is already logged; the photo is a best-effort attachment.
    private func scheduleDeferredImageUploadRetry(
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

    private func promoteSavedRow(for request: SaveLogRequest, idempotencyKey: UUID, logId: String) {
        let queuedItem = pendingQueueItem(for: idempotencyKey)
        let savedLoggedAt = request.parsedLog.loggedAt
        var promotedRowID: UUID?

        if let rowID = queuedItem?.rowID,
           let index = inputRows.firstIndex(where: { $0.id == rowID }) {
            promoteInputRow(at: index, logId: logId, loggedAt: savedLoggedAt, imageRef: request.parsedLog.imageRef)
            promotedRowID = rowID
        }

        if promotedRowID == nil {
            let requestText = HomeLoggingTextMatch.normalizedRowText(request.parsedLog.rawText)
            let isImageSave = normalizedInputKind(request.parsedLog.inputKind, fallback: latestParseInputKind) == "image"
            if let index = inputRows.firstIndex(where: { row in
                guard !row.isSaved else { return false }
                if isImageSave, row.imagePreviewData != nil || row.imageRef != nil {
                    return true
                }
                return !requestText.isEmpty && HomeLoggingTextMatch.normalizedRowText(row.text) == requestText
            }) {
                promoteInputRow(at: index, logId: logId, loggedAt: savedLoggedAt, imageRef: request.parsedLog.imageRef)
                promotedRowID = inputRows[index].id
            }
        }

        if promotedRowID == nil, let queuedItem {
            let optimisticRow = HomeLoggingRowFactory.makePendingSaveRow(from: queuedItem)
            if !inputRows.contains(where: { $0.serverLogId == logId }) {
                let trailingEmptyIndex = inputRows.lastIndex { row in
                    !row.isSaved && row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                inputRows.insert(optimisticRow, at: trailingEmptyIndex ?? inputRows.count)
            }
        }

        if inputRows.allSatisfy({ $0.isSaved }) {
            inputRows.append(.empty())
        }
    }

    private func promoteInputRow(at index: Int, logId: String, loggedAt: String, imageRef: String?) {
        guard inputRows.indices.contains(index) else { return }
        inputRows[index].isSaved = true
        inputRows[index].serverLogId = logId
        inputRows[index].serverLoggedAt = loggedAt
        inputRows[index].parsePhase = .idle
        if inputRows[index].imageRef == nil {
            inputRows[index].imageRef = imageRef
        }
        if inputRows[index].imageRef != nil {
            inputRows[index].imagePreviewData = nil
        }
    }

    private func syncSavedLogToAppleHealthIfEnabled(_ request: SaveLogRequest, response: SaveLogResponse) async -> Bool {
        guard appStore.isHealthSyncEnabled else { return false }

        let loggedAtDate = HomeLoggingDateUtils.loggedAtFormatter.date(from: request.parsedLog.loggedAt) ??
            ISO8601DateFormatter().date(from: request.parsedLog.loggedAt) ??
            Date()
        do {
            return try await appStore.syncNutritionToAppleHealth(
                totals: request.parsedLog.totals,
                loggedAt: loggedAtDate,
                logId: response.logId,
                healthWriteKey: response.healthSync?.healthWriteKey ?? response.logId
            )
        } catch {
            if let healthError = error as? HealthKitServiceError,
               case .notAuthorized = healthError {
                appStore.disconnectAppleHealth()
            }
            return false
        }
    }

    private func deleteSavedLogFromAppleHealthIfEnabled(row: HomeLogRow, healthSync: HealthSyncResponse?) async {
        guard appStore.isHealthSyncEnabled else { return }
        guard let serverLogId = row.serverLogId else { return }

        let loggedAtText = row.serverLoggedAt ?? HomeLoggingDateUtils.loggedAtFormatter.string(from: selectedSummaryDate)
        let loggedAtDate = HomeLoggingDateUtils.loggedAtFormatter.date(from: loggedAtText) ??
            ISO8601DateFormatter().date(from: loggedAtText) ??
            selectedSummaryDate
        let totals = NutritionTotals(
            calories: row.parsedItems.isEmpty ? Double(row.calories ?? 0) : row.parsedItems.reduce(0) { $0 + $1.calories },
            protein: row.parsedItems.reduce(0) { $0 + $1.protein },
            carbs: row.parsedItems.reduce(0) { $0 + $1.carbs },
            fat: row.parsedItems.reduce(0) { $0 + $1.fat }
        )

        do {
            _ = try await appStore.deleteNutritionFromAppleHealth(
                totals: totals,
                loggedAt: loggedAtDate,
                logId: serverLogId,
                healthWriteKey: healthSync?.healthWriteKey ?? serverLogId
            )
        } catch {
            if let healthError = error as? HealthKitServiceError,
               case .notAuthorized = healthError {
                appStore.disconnectAppleHealth()
            }
            // Apple Health cleanup is best-effort and must not resurrect a log
            // after the backend delete has already succeeded.
        }
    }

    private func emitParseTelemetrySuccess(response: ParseLogResponse, durationMs: Double, uiApplied: Bool) {
        let reasonSummary = (response.reasonCodes ?? []).joined(separator: ",")
        TelemetryClient.shared.emit(
            TelemetryEvent(
                eventName: "parse_request",
                feature: "parse",
                outcome: .success,
                durationMs: durationMs,
                timestamp: TelemetryClient.shared.nowISO8601(),
                environment: appStore.configuration.environment.rawValue,
                backendRequestId: response.requestId,
                backendErrorCode: nil,
                httpStatusCode: nil,
                parseRequestId: response.parseRequestId,
                parseVersion: response.parseVersion,
                details: [
                    "route": .string(response.route),
                    "cacheHit": .bool(response.cacheHit),
                    "fallbackUsed": .bool(response.fallbackUsed),
                    "needsClarification": .bool(response.needsClarification),
                    "reasonCodes": .string(reasonSummary),
                    "retryAfterSeconds": .int(response.retryAfterSeconds ?? 0),
                    "uiApplied": .bool(uiApplied)
                ]
            )
        )
    }

    private func emitParseTelemetryFailure(error: Error, durationMs: Double, uiApplied: Bool) {
        let metadata = telemetryErrorMetadata(error)
        TelemetryClient.shared.emit(
            TelemetryEvent(
                eventName: "parse_request",
                feature: "parse",
                outcome: .failure,
                durationMs: durationMs,
                timestamp: TelemetryClient.shared.nowISO8601(),
                environment: appStore.configuration.environment.rawValue,
                backendRequestId: metadata.backendRequestId,
                backendErrorCode: metadata.backendErrorCode,
                httpStatusCode: metadata.httpStatusCode,
                parseRequestId: parseResult?.parseRequestId,
                parseVersion: parseResult?.parseVersion,
                details: [
                    "uiApplied": .bool(uiApplied),
                    "errorMessage": .string((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                ]
            )
        )
    }

    private func emitSaveTelemetrySuccess(request: SaveLogRequest, durationMs: Double, isRetry: Bool, logId: String) {
        emitSaveTelemetrySuccess(request: request, durationMs: durationMs, isRetry: isRetry, logId: logId, timeToLogMs: nil)
    }

    private func emitSaveTelemetrySuccess(
        request: SaveLogRequest,
        durationMs: Double,
        isRetry: Bool,
        logId: String,
        timeToLogMs: Double?
    ) {
        var details: [String: TelemetryValue] = [
            "isRetry": .bool(isRetry),
            "itemsCount": .int(request.parsedLog.items.count),
            "rawTextLength": .int(request.parsedLog.rawText.count),
            "logId": .string(logId)
        ]
        if let timeToLogMs {
            details["timeToLogMs"] = .int(Int(timeToLogMs.rounded()))
        }

        TelemetryClient.shared.emit(
            TelemetryEvent(
                eventName: "save_log",
                feature: "save",
                outcome: .success,
                durationMs: durationMs,
                timestamp: TelemetryClient.shared.nowISO8601(),
                environment: appStore.configuration.environment.rawValue,
                backendRequestId: nil,
                backendErrorCode: nil,
                httpStatusCode: nil,
                parseRequestId: request.parseRequestId,
                parseVersion: request.parseVersion,
                details: details
            )
        )
    }

    private func emitSaveTelemetryFailure(request: SaveLogRequest, error: Error, durationMs: Double, isRetry: Bool) {
        let metadata = telemetryErrorMetadata(error)
        TelemetryClient.shared.emit(
            TelemetryEvent(
                eventName: "save_log",
                feature: "save",
                outcome: .failure,
                durationMs: durationMs,
                timestamp: TelemetryClient.shared.nowISO8601(),
                environment: appStore.configuration.environment.rawValue,
                backendRequestId: metadata.backendRequestId,
                backendErrorCode: metadata.backendErrorCode,
                httpStatusCode: metadata.httpStatusCode,
                parseRequestId: request.parseRequestId,
                parseVersion: request.parseVersion,
                details: [
                    "isRetry": .bool(isRetry),
                    "itemsCount": .int(request.parsedLog.items.count),
                    "rawTextLength": .int(request.parsedLog.rawText.count),
                    "errorMessage": .string((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                ]
            )
        )
    }

    private func telemetryErrorMetadata(_ error: Error) -> (backendRequestId: String?, backendErrorCode: String?, httpStatusCode: Int?) {
        guard let apiError = error as? APIClientError else {
            return (nil, nil, nil)
        }

        switch apiError {
        case let .server(statusCode, payload):
            return (payload.requestId, payload.code, statusCode)
        case let .unexpectedStatus(code):
            return (nil, "UNEXPECTED_STATUS", code)
        default:
            return (nil, nil, nil)
        }
    }

    private func saveAttemptErrorCode(_ error: Error) -> String? {
        let metadata = telemetryErrorMetadata(error)
        if let backendCode = metadata.backendErrorCode, !backendCode.isEmpty {
            return backendCode
        }
        if let statusCode = metadata.httpStatusCode {
            return "HTTP_\(statusCode)"
        }
        return nil
    }

    private func telemetrySource(for intent: SaveIntent) -> SaveAttemptSource {
        switch intent {
        case .manual:
            return .manual
        case .retry:
            return .retry
        case .auto, .dateChangeBackground:
            return .auto
        }
    }

    private func elapsedMs(since startedAt: Date) -> Double {
        (Date().timeIntervalSince(startedAt) * 1000).rounded()
    }

    private func hydrateVisibleDayLogsFromDiskIfNeeded() {
        let dateString = summaryDateString
        guard dayLogs == nil, let cached = loadDayLogsFromCache(date: dateString) else { return }
        dayLogs = cached
        dayCacheLogs[dateString] = cached
        syncInputRowsFromDayLogs(cached.logs, for: cached.date)
    }

    private func bootstrapAuthenticatedHomeIfNeeded() {
        guard appStore.isSessionRestored, !hasBootstrappedAuthenticatedHome else { return }
        hasBootstrappedAuthenticatedHome = true

        submitRestoredPendingSaveIfPossible()
        refreshDaySummary()

        initialHomeBootstrapTask?.cancel()
        initialHomeBootstrapTask = Task { @MainActor in
            await loadDayLogs(skipCache: true)
            guard !Task.isCancelled else { return }
            refreshCurrentStreak()
            prefetchAdjacentDays(around: selectedSummaryDate)
        }
    }

    private func refreshDaySummary() {
        // Stale-while-revalidate: paint any cached summary instantly, THEN
        // always hit the network so stale cache (e.g. from a prior save whose
        // reload failed silently, or entries made in another session) gets
        // corrected. Previously this function never hit the network if the
        // cache was populated — leaving users with stale totals.
        Task {
            let dateToLoad = summaryDateString
            if let cached = dayCacheSummary[dateToLoad] {
                daySummary = cached
                daySummaryError = nil
            }
            await loadDaySummary(skipCache: true)
        }
    }

    private func refreshDayLogs() {
        // Stale-while-revalidate: same rationale as refreshDaySummary. Paint
        // any cached logs instantly, then always hit the network so rows
        // saved on another device — or any save whose post-reload failed —
        // become visible.
        Task {
            let dateToLoad = summaryDateString
            if let cached = dayCacheLogs[dateToLoad], cached.date == dateToLoad {
                dayLogs = cached
                syncInputRowsFromDayLogs(cached.logs, for: cached.date)
            }
            await loadDayLogs(skipCache: true)
        }
    }

    private func refreshCurrentStreak() {
        guard appStore.configuration.progressFeatureEnabled else {
            currentFoodLogStreak = nil
            return
        }

        Task { @MainActor in
            isLoadingFoodLogStreak = true
            defer { isLoadingFoodLogStreak = false }

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let formatter = HomeLoggingDateUtils.summaryRequestFormatter
            do {
                let response = try await appStore.apiClient.getStreaks(
                    range: 30,
                    to: formatter.string(from: today),
                    timezone: TimeZone.current.identifier
                )
                currentFoodLogStreak = response.currentDays
            } catch {
                handleAuthFailureIfNeeded(error)
            }
        }
    }

    private func loadDayLogs(forcedDate: String? = nil, isRetry: Bool = false, skipCache: Bool = false) async {
        let dateToLoad = forcedDate ?? summaryDateString

        // Serve from cache only if the date still matches what the user is viewing.
        // This prevents stale cache from a prefetch or a race condition from showing
        // wrong data.
        if !skipCache, let cached = dayCacheLogs[dateToLoad], cached.date == dateToLoad {
            // Double-check the user hasn't swiped to a different day while we were loading
            guard summaryDateString == dateToLoad || forcedDate != nil else { return }
            dayLogs = cached
            syncInputRowsFromDayLogs(cached.logs, for: cached.date)
            return
        }

        isLoadingDayLogs = true
        defer { isLoadingDayLogs = false }

        guard appStore.isNetworkReachable else { return }

        do {
            let response = try await appStore.apiClient.getDayLogs(date: dateToLoad)

            // Validate the response is for the date we requested
            guard response.date == dateToLoad else {
#if DEBUG
                print("[loadDayLogs] date mismatch: requested=\(dateToLoad) got=\(response.date) — discarding")
#endif
                return
            }
            // Verify user is still viewing this date (they may have swiped during the network call)
            guard summaryDateString == dateToLoad || forcedDate != nil else {
                // Still cache it for when they come back
                dayCacheLogs[dateToLoad] = response
                persistDayLogsToCache(response, date: dateToLoad)
                return
            }

            dayLogs = response
            dayCacheLogs[dateToLoad] = response
            persistDayLogsToCache(response, date: dateToLoad)
            syncInputRowsFromDayLogs(response.logs, for: response.date)
        } catch is CancellationError {
            // ignore
        } catch {
            handleAuthFailureIfNeeded(error)
            if !isRetry && isTransientLoadError(error) {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await loadDayLogs(forcedDate: forcedDate, isRetry: true, skipCache: skipCache)
            }
        }
    }

    // MARK: - Day Logs Disk Cache

    private func persistDayLogsToCache(_ response: DayLogsResponse, date: String) {
        HomeDayLogsDiskCache.persist(response, date: date, defaults: defaults)
    }

    private func loadDayLogsFromCache(date: String) -> DayLogsResponse? {
        HomeDayLogsDiskCache.load(date: date, defaults: defaults)
    }

    private func removeDayLogsCacheEntry(date: String) {
        HomeDayLogsDiskCache.remove(date: date, defaults: defaults)
    }

    private func pendingRowsForDate(_ dateString: String, excluding serverEntries: [DayLogEntry]) -> [HomeLogRow] {
        let serverLogIds = Set(serverEntries.map(\.id))
        return pendingSaveQueue
            .filter { item in
                guard item.dateString == dateString else { return false }
                if item.serverLogId.map({ serverLogIds.contains($0) }) == true {
                    return false
                }
                return !serverEntries.contains { HomeLoggingRowFactory.pendingSaveItem(item, matchesServerLog: $0) }
            }
            .sorted { $0.createdAt < $1.createdAt }
            .map(HomeLoggingRowFactory.makePendingSaveRow)
    }

    private func preservedDraftRowsForDate(
        _ dateString: String,
        pendingRows: [HomeLogRow],
        activeRows: [HomeLogRow]
    ) -> [HomeLogRow] {
        guard let preservedRows = preservedDraftRowsByDate[dateString], !preservedRows.isEmpty else {
            return []
        }

        let pendingRowIDs = Set(pendingRows.map(\.id))
        let activeRowIDs = Set(activeRows.map(\.id))

        return preservedRows.compactMap { preserved in
            var row = preserved.row
            let normalizedText = HomeLoggingTextMatch.normalizedRowText(row.text)
            guard !normalizedText.isEmpty else { return nil }
            guard !pendingRowIDs.contains(row.id) else { return nil }
            guard !activeRowIDs.contains(row.id) else { return nil }

            if preserved.isBackgroundManaged,
               row.calories == nil,
               row.parsedItem == nil,
               row.parsedItems.isEmpty {
                row.normalizedTextAtParse = normalizedText
            }

            row.clearParsePhase()
            return row
        }
    }

    private func removePreservedDateDraft(rowID: UUID, for dateString: String) {
        guard var preservedRows = preservedDraftRowsByDate[dateString] else { return }
        preservedRows.removeAll { $0.row.id == rowID }
        if preservedRows.isEmpty {
            preservedDraftRowsByDate.removeValue(forKey: dateString)
        } else {
            preservedDraftRowsByDate[dateString] = preservedRows
        }
    }

    private func markPreservedDateDraftNeedsParse(rowID: UUID, loggedAt: String) {
        let dateString = HomeLoggingDateUtils.summaryDayString(fromLoggedAt: loggedAt, fallback: summaryDateString)
        guard var preservedRows = preservedDraftRowsByDate[dateString],
              let preservedIndex = preservedRows.firstIndex(where: { $0.row.id == rowID }) else {
            return
        }

        preservedRows[preservedIndex].isBackgroundManaged = false
        preservedRows[preservedIndex].row.normalizedTextAtParse = nil
        preservedDraftRowsByDate[dateString] = preservedRows

        guard summaryDateString == dateString,
              let rowIndex = inputRows.firstIndex(where: { $0.id == rowID }) else {
            return
        }

        inputRows[rowIndex].normalizedTextAtParse = nil
        inputRows[rowIndex].clearParsePhase()
        scheduleDebouncedParse(for: noteText)
    }

    private func syncInputRowsFromDayLogs(_ entries: [DayLogEntry], for dateString: String) {
        reconcilePendingSaveQueue(with: entries, for: dateString)
        let currentActiveRows = inputRows.filter { !$0.isSaved }
        let shouldKeepActiveRows = draftDayString() == dateString || (draftLoggedAt == nil && dateString == summaryDateString)
        let activeServerLogIds = shouldKeepActiveRows
            ? Set(currentActiveRows.compactMap(\.serverLogId))
            : []
        let currentSavedRowOrder: [String: Int] = Dictionary(
            uniqueKeysWithValues: inputRows.enumerated().compactMap { index, row in
                row.serverLogId.map { ($0, index) }
            }
        )
        let savedRows: [HomeLogRow] = entries
            .filter { !activeServerLogIds.contains($0.id) }
            .map(HomeLoggingRowFactory.makeSavedRow)
        let orderedSavedRows = savedRows.enumerated()
            .sorted { lhs, rhs in
                let lhsOrder = lhs.element.serverLogId.flatMap { currentSavedRowOrder[$0] }
                let rhsOrder = rhs.element.serverLogId.flatMap { currentSavedRowOrder[$0] }

                switch (lhsOrder, rhsOrder) {
                case let (lhs?, rhs?):
                    return lhs < rhs
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)

        // Merge server state into the existing visible order. This keeps rows from
        // jumping during optimistic save -> stale cache -> fresh server refresh cycles.
        let pendingRows = pendingRowsForDate(dateString, excluding: entries)
        let pendingRowIDs = Set(pendingRows.map(\.id))
        let activeRows: [HomeLogRow]
        if shouldKeepActiveRows {
            activeRows = currentActiveRows.filter { !pendingRowIDs.contains($0.id) }
        } else {
            activeRows = []
        }
        let preservedRows = preservedDraftRowsForDate(
            dateString,
            pendingRows: pendingRows,
            activeRows: activeRows
        )
        let nextRows = mergeRowsPreservingVisibleOrder(
            currentRows: inputRows,
            candidateRows: orderedSavedRows + pendingRows + preservedRows + activeRows
        )
        if inputRowsSyncSignature(inputRows) != inputRowsSyncSignature(nextRows) {
            inputRows = nextRows
        }

        // Ensure there's always at least one empty active row for input
        if inputRows.allSatisfy({ $0.isSaved }) {
            inputRows.append(.empty())
        }
    }

    private func inputRowsSyncSignature(_ rows: [HomeLogRow]) -> String {
        rows.map { row in
            [
                row.id.uuidString,
                row.serverLogId ?? "",
                HomeLoggingTextMatch.normalizedRowText(row.text),
                row.calories.map(String.init) ?? "",
                row.isSaved ? "saved" : "draft"
            ].joined(separator: "|")
        }
        .joined(separator: "\n")
    }

    private func mergeRowsPreservingVisibleOrder(
        currentRows: [HomeLogRow],
        candidateRows: [HomeLogRow]
    ) -> [HomeLogRow] {
        var remainingByServerLogId: [String: HomeLogRow] = [:]
        var remainingByRowId: [UUID: HomeLogRow] = [:]
        var candidateOrder: [String] = []

        for row in candidateRows {
            if let serverLogId = row.serverLogId {
                let key = "server:\(serverLogId)"
                if remainingByServerLogId[serverLogId] == nil {
                    candidateOrder.append(key)
                }
                remainingByServerLogId[serverLogId] = row
            } else {
                let key = "row:\(row.id.uuidString)"
                if remainingByRowId[row.id] == nil {
                    candidateOrder.append(key)
                }
                remainingByRowId[row.id] = row
            }
        }

        var output: [HomeLogRow] = []
        var usedKeys = Set<String>()

        func appendIfUnused(_ row: HomeLogRow) {
            let key = row.serverLogId.map { "server:\($0)" } ?? "row:\(row.id.uuidString)"
            guard !usedKeys.contains(key) else { return }
            output.append(row)
            usedKeys.insert(key)
        }

        for current in currentRows {
            if let serverLogId = current.serverLogId,
               let replacement = remainingByServerLogId.removeValue(forKey: serverLogId) {
                appendIfUnused(replacement)
                continue
            }

            if let replacement = remainingByRowId.removeValue(forKey: current.id) {
                appendIfUnused(replacement)
            }
        }

        for key in candidateOrder where !usedKeys.contains(key) {
            if key.hasPrefix("server:") {
                let serverLogId = String(key.dropFirst("server:".count))
                if let row = remainingByServerLogId.removeValue(forKey: serverLogId) {
                    appendIfUnused(row)
                }
            } else if key.hasPrefix("row:") {
                let rowIDText = String(key.dropFirst("row:".count))
                if let rowID = UUID(uuidString: rowIDText),
                   let row = remainingByRowId.removeValue(forKey: rowID) {
                    appendIfUnused(row)
                }
            }
        }

        return output
    }

    private func loadDaySummary(forcedDate: String? = nil, isRetry: Bool = false, skipCache: Bool = false) async {
        let dateToLoad = forcedDate ?? summaryDateString

        // Serve from cache if available — instant, no loading spinner
        if !skipCache, let cached = dayCacheSummary[dateToLoad] {
            daySummary = cached
            daySummaryError = nil
            return
        }

        isLoadingDaySummary = true
        daySummaryError = nil
        defer { isLoadingDaySummary = false }

        guard appStore.isNetworkReachable else {
            daySummaryError = L10n.noNetworkSummary
            return
        }

        do {
            let response = try await appStore.apiClient.getDaySummary(date: dateToLoad)
            daySummary = response
            daySummaryError = nil
            dayCacheSummary[dateToLoad] = response
        } catch {
            handleAuthFailureIfNeeded(error)

            if !isRetry && isTransientLoadError(error) {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await loadDaySummary(forcedDate: forcedDate, isRetry: true, skipCache: skipCache)
                return
            }

            daySummaryError = userFriendlyDaySummaryError(error)
            if daySummary?.date != dateToLoad {
                daySummary = nil
            }
        }
    }

    /// Silently prefetch the previous 10 days in the background so swiping is instant.
    /// Runs with low priority and doesn't show loading indicators or errors.
    private func prefetchAdjacentDays(around date: Date, count: Int = 15) {
        prefetchTask?.cancel()
        prefetchTask = Task(priority: .utility) {
            let calendar = Calendar.current
            let formatter = HomeLoggingDateUtils.summaryRequestFormatter

            // Check if any days in the range need fetching
            var needsFetch = false
            for offset in 1...count {
                let pastDate = calendar.date(byAdding: .day, value: -offset, to: date) ?? date
                let dateStr = formatter.string(from: pastDate)
                if dayCacheSummary[dateStr] == nil || dayCacheLogs[dateStr] == nil {
                    needsFetch = true
                    break
                }
            }
            guard needsFetch, !Task.isCancelled else { return }

            // Batch fetch: single request for the entire range
            let toDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            let fromDate = calendar.date(byAdding: .day, value: -count, to: date) ?? date
            let toStr = formatter.string(from: toDate)
            let fromStr = formatter.string(from: fromDate)

            guard !Task.isCancelled else { return }

            do {
                let range = try await appStore.apiClient.getDayRange(from: fromStr, to: toStr)
                guard !Task.isCancelled else { return }
                for summary in range.summaries {
                    dayCacheSummary[summary.date] = summary
                }
                for logs in range.logs {
                    dayCacheLogs[logs.date] = logs
                    persistDayLogsToCache(logs, date: logs.date)
                }
            } catch {
                // Fallback: fetch individually if batch fails
                for offset in 1...count {
                    guard !Task.isCancelled else { return }
                    let pastDate = calendar.date(byAdding: .day, value: -offset, to: date) ?? date
                    let dateStr = formatter.string(from: pastDate)
                    guard dayCacheSummary[dateStr] == nil || dayCacheLogs[dateStr] == nil else { continue }

                    async let summaryResult = try? appStore.apiClient.getDaySummary(date: dateStr)
                    async let logsResult = try? appStore.apiClient.getDayLogs(date: dateStr)
                    if let summary = await summaryResult { dayCacheSummary[dateStr] = summary }
                    if let logs = await logsResult {
                        dayCacheLogs[dateStr] = logs
                        persistDayLogsToCache(logs, date: dateStr)
                    }
                }
            }
        }
    }

    /// Invalidate cache for a specific date (e.g. after saving a new log entry).
    private func invalidateDayCache(for dateString: String) {
        dayCacheSummary.removeValue(forKey: dateString)
        dayCacheLogs.removeValue(forKey: dateString)
        removeDayLogsCacheEntry(date: dateString)
    }

    /// Returns true for errors that are transient and worth retrying automatically.
    private func isTransientLoadError(_ error: Error) -> Bool {
        if let apiErr = error as? APIClientError, case .networkFailure = apiErr {
            return true
        }
        let nsErr = error as NSError
        let transientCodes: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorCannotConnectToHost
        ]
        return nsErr.domain == NSURLErrorDomain && transientCodes.contains(nsErr.code)
    }

    private var summaryDateString: String {
        HomeLoggingDateUtils.summaryRequestFormatter.string(from: selectedSummaryDate)
    }

    private func userFriendlyDaySummaryError(_ error: Error) -> String {
        HomeLoggingErrorText.daySummaryError(error)
    }

    private func clearPendingSaveContext() {
        pendingSaveRequest = nil
        pendingSaveFingerprint = nil
        pendingSaveIdempotencyKey = nil
    }

    private func pendingQueueItem(for idempotencyKey: UUID) -> PendingSaveQueueItem? {
        let queueKey = idempotencyKey.uuidString.lowercased()
        return pendingSaveQueue.first { $0.idempotencyKey == queueKey }
    }

    private func pendingQueueItem(forRowID rowID: UUID) -> PendingSaveQueueItem? {
        pendingSaveQueue.first { $0.rowID == rowID }
    }

    private func containsPendingQueueItem(for idempotencyKey: UUID) -> Bool {
        pendingQueueItem(for: idempotencyKey) != nil
    }

    private func resolveIdempotencyKey(forRowID rowID: UUID?) -> UUID {
        IdempotencyKeyResolver.resolve(
            rowID: rowID,
            queue: pendingSaveQueue
        )
    }

    private var unresolvedPendingQueueItems: [PendingSaveQueueItem] {
        pendingSaveQueue.filter { $0.serverLogId == nil }
    }

    private func firstUnresolvedPendingQueueItem() -> PendingSaveQueueItem? {
        unresolvedPendingQueueItems.first
    }

    private func syncPendingQueueFromCoordinator(refreshRetryState: Bool = false) {
        pendingSaveQueue = saveCoordinator.pendingItems
        if refreshRetryState {
            refreshRetryStateFromPendingQueue()
        }
    }

    private func upsertPendingSaveQueueItem(
        request: SaveLogRequest,
        fingerprint: String,
        idempotencyKey: UUID,
        rowID: UUID?,
        imageUploadData: Data? = nil,
        imagePreviewData: Data? = nil,
        imageMimeType: String? = nil,
        serverLogId: String? = nil
    ) {
        saveCoordinator.upsertPendingItem(
            request: request,
            fingerprint: fingerprint,
            idempotencyKey: idempotencyKey,
            rowID: rowID,
            imageUploadData: imageUploadData,
            imagePreviewData: imagePreviewData,
            imageMimeType: imageMimeType,
            serverLogId: serverLogId
        )
        syncPendingQueueFromCoordinator(refreshRetryState: true)
    }

    private func refreshRetryStateFromPendingQueue() {
        if let context = saveCoordinator.retryContext() {
            pendingSaveRequest = context.request
            pendingSaveFingerprint = context.fingerprint
            pendingSaveIdempotencyKey = context.idempotencyKey
            return
        }

        guard let item = firstUnresolvedPendingQueueItem(),
              let key = UUID(uuidString: item.idempotencyKey) else {
            pendingSaveRequest = nil
            pendingSaveFingerprint = nil
            pendingSaveIdempotencyKey = nil
            return
        }

        pendingSaveRequest = item.request
        pendingSaveFingerprint = item.fingerprint
        pendingSaveIdempotencyKey = key
    }

    private func markPendingSaveAttemptStarted(idempotencyKey: UUID) {
        saveCoordinator.markAttemptStarted(idempotencyKey: idempotencyKey)
        syncPendingQueueFromCoordinator()
    }

    private func handlePendingSaveFailure(
        idempotencyKey: UUID,
        request: SaveLogRequest,
        error: Error,
        message: String
    ) async {
        let nonRetryable = saveCoordinator.handleFailure(
            idempotencyKey: idempotencyKey,
            message: message,
            error: error
        )
        syncPendingQueueFromCoordinator(refreshRetryState: true)

        if nonRetryable {
            let failedDay = HomeLoggingDateUtils.summaryDayString(
                fromLoggedAt: request.parsedLog.loggedAt,
                fallback: summaryDateString
            )
            await refreshDayAfterMutation(failedDay, postNutritionNotification: false)
        }
    }

    private func markPendingSaveSucceeded(idempotencyKey: UUID, logId: String, preparedRequest: SaveLogRequest) {
        saveCoordinator.markSucceeded(
            idempotencyKey: idempotencyKey,
            logId: logId,
            preparedRequest: preparedRequest,
            fingerprint: saveRequestFingerprint(preparedRequest)
        )
        syncPendingQueueFromCoordinator(refreshRetryState: true)
    }

    private func removePendingSave(idempotencyKey: String) {
        saveCoordinator.removePendingSave(idempotencyKey: idempotencyKey)
        syncPendingQueueFromCoordinator(refreshRetryState: true)
    }

    @discardableResult
    private func removePendingSaveQueueItems(forRowID rowID: UUID) -> Set<String> {
        let removed = saveCoordinator.removePendingItems(forRowID: rowID)
        syncPendingQueueFromCoordinator(refreshRetryState: true)
        return removed
    }

    private func reconcilePendingSaveQueue(with logs: [DayLogEntry], for dateString: String) {
        saveCoordinator.reconcilePendingQueue(with: logs, for: dateString)
        syncPendingQueueFromCoordinator(refreshRetryState: true)
    }

    private func saveRequestFingerprint(_ request: SaveLogRequest) -> String {
        HomeLoggingSaveRequestUtils.fingerprint(request)
    }

    private func userFriendlySaveError(_ error: Error) -> String {
        HomeLoggingErrorText.saveError(error)
    }

    private func userFriendlyParseError(_ error: Error) -> String {
        HomeLoggingErrorText.parseError(error)
    }

    private func userFriendlyEscalationError(_ error: Error) -> (message: String, blockCode: String?) {
        HomeLoggingErrorText.escalationError(error)
    }

    private func handleAuthFailureIfNeeded(_ error: Error) {
        _ = appStore.handleAuthFailureIfNeeded(error)
    }

    private func persistPendingSaveContext(
        rowID: UUID? = nil,
        imageUploadData: Data? = nil,
        imagePreviewData: Data? = nil,
        imageMimeType: String? = nil
    ) {
        guard let pendingSaveRequest, let pendingSaveFingerprint, let pendingSaveIdempotencyKey else {
            return
        }
        upsertPendingSaveQueueItem(
            request: pendingSaveRequest,
            fingerprint: pendingSaveFingerprint,
            idempotencyKey: pendingSaveIdempotencyKey,
            rowID: rowID,
            imageUploadData: imageUploadData,
            imagePreviewData: imagePreviewData,
            imageMimeType: imageMimeType
        )
    }

    private func restorePendingSaveContextIfNeeded() {
        guard pendingSaveQueue.isEmpty else {
            return
        }
        let restored = saveCoordinator.loadRecoverableQueue(
            isRecoverable: isRecoverablePendingSaveItem
        )
        pendingSaveQueue = restored.queue
        refreshRetryStateFromPendingQueue()
    }

    private func submitRestoredPendingSaveIfPossible() {
        guard appStore.isNetworkReachable, !isSaving, !isSubmittingRestoredPendingSaves else { return }

        Task { @MainActor in
            isSubmittingRestoredPendingSaves = true
            defer { isSubmittingRestoredPendingSaves = false }

            let report = await saveCoordinator.flushAll(reason: .startup) { candidate in
                await submitSave(
                    request: candidate.item.request,
                    idempotencyKey: candidate.idempotencyKey,
                    isRetry: true,
                    intent: .auto
                ).didSucceed
            }
            syncPendingQueueFromCoordinator()
            guard report.attempted > 0 else { return }
        }
    }

    private func isRecoverablePendingSaveItem(_ item: PendingSaveQueueItem) -> Bool {
        HomeLoggingSaveRequestUtils.isRecoverablePendingSaveItem(item)
    }

    private func saveDraftPreviewJSON() -> String {
        guard let request = buildSaveDraftRequest() else {
            return "{}"
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(request), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

}

#Preview {
    MainLoggingShellView()
        .environmentObject(AppStore())
}
