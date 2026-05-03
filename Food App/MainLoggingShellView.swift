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

    var hasSaveableRowsPending: Bool {
        activeParseSnapshots.contains(where: { isAutoSaveEligibleEntry($0) }) ||
            hasQueuedPendingSaves
    }

    var hasQueuedPendingSaves: Bool {
        pendingSaveQueue.contains { item in
            item.serverLogId == nil && UUID(uuidString: item.idempotencyKey) != nil
        }
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
