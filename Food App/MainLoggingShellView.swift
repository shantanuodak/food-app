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

    var bottomActionDock: some View {
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

    var pendingSyncItemCount: Int {
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

    var shouldShowSyncExceptionPill: Bool {
        saveError != nil && pendingSyncItemCount > 0
    }

    var syncStatusTitle: String {
        pendingSyncItemCount == 1 ? "1 item waiting" : "\(pendingSyncItemCount) items waiting"
    }

    var syncStatusExplanation: String {
        "These items are visible here and included in your calories. Sync is retrying in the background."
    }

    func pendingSyncKey(for item: PendingSaveQueueItem) -> String {
        if let rowID = item.rowID {
            return "row:\(rowID.uuidString)"
        }
        return "key:\(item.idempotencyKey)"
    }

    var topHeaderStrip: some View {
        MainLoggingTopHeaderStrip(
            firstName: loggedInFirstName,
            dateTitle: todayPillTitle,
            colorScheme: colorScheme,
            isProfilePresented: $isProfilePresented,
            isCalendarPresented: $isCalendarPresented
        )
    }

    var todayPillTitle: String {
        if Calendar.current.isDateInToday(selectedSummaryDate) {
            return "Today"
        }
        return HomeLoggingDateUtils.topDateFormatter.string(from: selectedSummaryDate)
    }

    func focusComposerInputFromBackgroundTap() {
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

    var loggedInFirstName: String? {
        appStore.authSessionStore.session?.displayFirstName
    }

    var isParsing: Bool {
        parseInFlightCount > 0
    }

    var hasActiveParseRequest: Bool {
        inFlightParseSnapshot != nil
    }

    var hasDirtyRowsPendingParse: Bool {
        !orderedDirtyRowIDsForCurrentInput().isEmpty
    }

    /// The scrollable food rows + status strip. The title "What did you eat today?"
    /// is rendered separately in the body so it stays pinned during day-swipe animations.
    var composeEntryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputSection

            homeStatusStrip
                .padding(.top, 8)
        }
    }

    var nutritionSummarySheet: some View {
        MainLoggingNutritionSummarySheet(
            totals: visibleNutritionTotals,
            navigationTitle: summaryDateString == HomeLoggingDateUtils.summaryRequestFormatter.string(from: Date()) ? "Today" : summaryDateString
        )
    }

    var visibleNutritionTotals: NutritionTotals {
        .visible(from: inputRows)
    }

    func refreshNutritionStateForVisibleDay() {
        invalidateDayCache(for: summaryDateString)
        refreshDaySummary()
        refreshDayLogs()
    }

    func refreshNutritionStateAfterProgressChange(_ notification: Notification) {
        guard let savedDay = notification.userInfo?["savedDay"] as? String else {
            refreshNutritionStateForVisibleDay()
            return
        }

        invalidateDayCache(for: savedDay)
        guard savedDay == summaryDateString else { return }
        refreshDaySummary()
        refreshDayLogs()
    }

    var inputSection: some View {
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

    var noteText: String {
        // Only consider active (unsaved) rows for parsing — saved rows are read-only history
        inputRows.filter { !$0.isSaved }.map(\.text).joined(separator: "\n")
    }

    var trimmedNoteText: String {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var parseCandidateRows: [String] {
        let normalized = inputRows.filter { !$0.isSaved }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var end = normalized.count
        while end > 0, normalized[end - 1].isEmpty {
            end -= 1
        }
        return Array(normalized.prefix(end))
    }

    var rowTextSignature: String {
        parseCandidateRows.joined(separator: "\u{001F}")
    }

    // MARK: - Voice Input

    static let voiceHapticGenerator = UIImpactFeedbackGenerator(style: .soft)
    @State var lastHapticTime: Date = .distantPast

    func canEscalate(_ result: ParseLogResponse) -> Bool {
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

    func escalationDisabledReason(_ result: ParseLogResponse) -> String? {
        if result.budget.escalationAllowed == false || escalationBlockedCode == "BUDGET_EXCEEDED" {
            return L10n.escalationBudgetReason
        }
        if escalationBlockedCode == "ESCALATION_DISABLED" {
            return L10n.escalationConfigReason
        }
        return nil
    }

    func startEscalationFlow() {
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

    func escalateCurrentParse(_ current: ParseLogResponse) async {
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

    var displayedTotals: NutritionTotals {
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

    func buildSaveDraftRequest() -> SaveLogRequest? {
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

    enum SaveIntent {
        case manual
        case retry
        case auto
        case dateChangeBackground
    }

    struct SaveSubmissionResult {
        let didSucceed: Bool
        let savedDay: String?
    }

    struct DateChangeDraftRow {
        let rowID: UUID
        let text: String
        let loggedAt: String
        let inputKind: String
    }

    struct PreservedDateDraftRow {
        var row: HomeLogRow
        var isBackgroundManaged: Bool
    }

    func startSaveFlow() {
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
    func handleQuantityFastPathUpdate(rowID: UUID) {
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
    func schedulePatchUpdate(rowID: UUID, serverLogId: String) {
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
    func performPatchUpdate(rowID: UUID, serverLogId: String) async {
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
    func submitRowPatch(
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

    func handleServerBackedRowCleared(_ row: HomeLogRow) {
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

    func serverBackedDeleteContext(for row: HomeLogRow) -> (serverLogId: String, savedDay: String)? {
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

    func clearTransientWorkForDeletedRow(rowID: UUID) {
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

    func deleteServerBackedRow(
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

    func restoreDeletedRow(_ row: HomeLogRow, at originalIndex: Int) {
        guard !inputRows.contains(where: { $0.id == row.id }) else { return }
        var restored = row
        restored.isDeleting = false
        let insertIndex = min(max(originalIndex, 0), inputRows.count)
        inputRows.insert(restored, at: insertIndex)
    }

    func removeDeletedLogFromVisibleDayLogs(logId: String, dateString: String) {
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

    func refreshDayAfterMutation(
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

    func cancelAutoSaveTask() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
    }

    func scheduleAutoSaveTask(
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

    func retryLastSave() {
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

    func scheduleAutoSave() {
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

    func rescheduleAutoSaveAfterActiveSave() {
        scheduleAutoSaveTask(after: 500_000_000, forceReschedule: true)
    }

    var hasSaveableRowsPending: Bool {
        activeParseSnapshots.contains(where: { isAutoSaveEligibleEntry($0) }) ||
            hasQueuedPendingSaves
    }

    var hasQueuedPendingSaves: Bool {
        pendingSaveQueue.contains { item in
            item.serverLogId == nil && UUID(uuidString: item.idempotencyKey) != nil
        }
    }

    func autoSaveIfNeeded() async {
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
    func flushQueuedPendingSavesIfNeeded() async -> Bool {
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
    func flushPendingAutoSaveIfEligible() async {
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

    func isAutoSaveEligibleEntry(_ entry: ParseSnapshot) -> Bool {
        SaveEligibility.isRowEligible(
            row: inputRows.first(where: { $0.id == entry.rowID }),
            snapshot: entry,
            autoSavedParseIDs: autoSavedParseIDs
        )
    }

    var hasVisibleUnsavedCalorieRows: Bool {
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
    func buildRowSaveRequest(for entry: ParseSnapshot) -> SaveLogRequest? {
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

    func buildDateChangeDraftSaveRequest(
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

    func fallbackSaveItem(
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

    func autoSaveContentFingerprint(_ request: SaveLogRequest) -> String {
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

    func normalizedInputKind(_ rawValue: String?, fallback: String = "text") -> String {
        HomeLoggingRowFactory.normalizedInputKind(rawValue, fallback: fallback)
    }

    func requestWithImageRef(_ request: SaveLogRequest, imageRef: String?) -> SaveLogRequest {
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

    func prepareSaveRequestForNetwork(_ request: SaveLogRequest, idempotencyKey: UUID) async throws -> SaveLogRequest {
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
    func submitSave(
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

    func handleSubmitSaveSuccess(
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

    func handleSubmitSaveFailure(
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

    func shouldDiscardCompletedSave(queueKey: String, rowID: UUID?) -> Bool {
        locallyDeletedPendingSaveKeys.contains(queueKey) ||
            rowID.map { locallyDeletedPendingRowIDs.contains($0) } == true
    }

    func deleteLateArrivingSave(logId: String, savedDay: String, queueKey: String, rowID: UUID?) async {
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

    func promoteSavedRow(for request: SaveLogRequest, idempotencyKey: UUID, logId: String) {
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

    func promoteInputRow(at index: Int, logId: String, loggedAt: String, imageRef: String?) {
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

    func syncSavedLogToAppleHealthIfEnabled(_ request: SaveLogRequest, response: SaveLogResponse) async -> Bool {
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

    func deleteSavedLogFromAppleHealthIfEnabled(row: HomeLogRow, healthSync: HealthSyncResponse?) async {
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

    func hydrateVisibleDayLogsFromDiskIfNeeded() {
        let dateString = summaryDateString
        guard dayLogs == nil, let cached = loadDayLogsFromCache(date: dateString) else { return }
        dayLogs = cached
        dayCacheLogs[dateString] = cached
        syncInputRowsFromDayLogs(cached.logs, for: cached.date)
    }

    func bootstrapAuthenticatedHomeIfNeeded() {
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


}

#Preview {
    MainLoggingShellView()
        .environmentObject(AppStore())
}
