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
    // Per-row parse results accumulated during a multi-row session.
    // Each entry stores the individual row rawText that was sent to the backend so
    // saveLog's rawText always matches the corresponding parse_requests record.
    // `rowItems` is the row-specific subset of `response.items`, captured at the
    // moment the parse response is applied. When multiple rows are typed before
    // the debounced parse fires, the backend receives the joined text and
    // returns items for ALL of them; saving `response.items` blindly would
    // attach every item to every row's food_log and inflate totals. Keeping
    // `rowItems` separate preserves the per-row mapping that applyRowParseResult
    // already computed.
    @State private var completedRowParses: [ParseSnapshot] = []
    // parseRequestIDs that have already been dispatched to auto-save (prevents re-saves).
    @State private var autoSavedParseIDs: Set<String> = []
    private let defaults = UserDefaults.standard
    private let autoSaveDelayNs: UInt64 = 1_500_000_000
    private let saveAttemptTelemetry = SaveAttemptTelemetry.shared
    private var useSaveCoordinator: Bool {
        LoggingFeatureFlags.useSaveCoordinator(defaults: defaults)
    }
    private var useParseCoordinator: Bool {
        LoggingFeatureFlags.useParseCoordinator(defaults: defaults)
    }

    private var activeParseSnapshots: [ParseSnapshot] {
        if useParseCoordinator {
            return parseCoordinator.snapshots.values.sorted { lhs, rhs in
                if lhs.capturedAt != rhs.capturedAt {
                    return lhs.capturedAt < rhs.capturedAt
                }
                return lhs.rowID.uuidString < rhs.rowID.uuidString
            }
        }
        return completedRowParses
    }

    private enum DetailsDrawerMode {
        case compact
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
                VStack(spacing: 16) {
                    HStack {
                        Text("Select Date")
                            .font(.headline)
                        Spacer()
                        Button("Today") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedSummaryDate = Calendar.current.startOfDay(for: Date())
                            }
                            isCalendarPresented = false
                        }
                        .fontWeight(.semibold)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    DatePicker(
                        "",
                        selection: $selectedSummaryDate,
                        in: ...Calendar.current.startOfDay(for: Date()),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal)
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
                    resetActiveParseStateForDateChange()
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
                autoSaveTask?.cancel()
                prefetchTask?.cancel()
                initialHomeBootstrapTask?.cancel()
                unresolvedRetryTask?.cancel()
                // Drop any pending PATCH tasks; inputRows state is cleared
                // on the next load anyway.
                for task in pendingPatchTasks.values { task.cancel() }
                pendingPatchTasks.removeAll()
                for task in pendingDeleteTasks.values { task.cancel() }
                pendingDeleteTasks.removeAll()
                clearParseSchedulerState()
                if useParseCoordinator {
                    parseCoordinator.clearAll()
                }
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
        VStack(spacing: 10) {
            if pendingSyncItemCount > 0 {
                syncStatusPill
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            ZStack {
                HStack(spacing: 0) {
                    HStack(spacing: 12) {
                        bottomDockButton(
                            systemImage: "camera.fill",
                            color: Color(red: 0.380, green: 0.333, blue: 0.961),
                            accessibilityLabel: "Open camera"
                        ) {
                            NotificationCenter.default.post(name: .openCameraFromTabBar, object: nil)
                        }

                        bottomDockButton(
                            systemImage: "mic.fill",
                            color: Color(red: 0.796, green: 0.188, blue: 0.878),
                            accessibilityLabel: "Voice input"
                        ) {
                            NotificationCenter.default.post(name: .openVoiceFromTabBar, object: nil)
                        }
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 12) {
                        streakDockIndicator

                        bottomDockButton(
                            systemImage: "flame.fill",
                            color: .orange,
                            accessibilityLabel: "Open nutrition summary"
                        ) {
                            NotificationCenter.default.post(name: .openNutritionSummaryFromTabBar, object: nil)
                        }
                    }
                }

                if isKeyboardVisible {
                    bottomDockButton(
                        systemImage: "keyboard.chevron.compact.down",
                        color: .secondary,
                        accessibilityLabel: "Dismiss keyboard"
                    ) {
                        NotificationCenter.default.post(name: .dismissKeyboardFromTabBar, object: nil)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var syncStatusPill: some View {
        Button {
            isSyncInfoPresented = true
        } label: {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)

                Text(syncStatusTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .accessibilityLabel(Text(syncStatusTitle))
        .alert("Pending sync", isPresented: $isSyncInfoPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(syncStatusExplanation)
        }
    }

    private var pendingSyncItemCount: Int {
        let unresolvedQueueItems = unresolvedPendingQueueItems
        let unresolvedQueuedRowIDs = Set(unresolvedQueueItems.compactMap(\.rowID))
        let unsavedVisibleRows = saveError == nil ? inputRows.filter { row in
            guard !row.isSaved else { return false }
            guard !unresolvedQueuedRowIDs.contains(row.id) else { return false }
            return row.calories != nil || !row.parsedItems.isEmpty || row.parsedItem != nil
        }.count : 0
        let activeQueueSyncRows = (isSaving || isSubmittingRestoredPendingSaves) ? unresolvedQueueItems.count : 0
        return unsavedVisibleRows + activeQueueSyncRows + pendingPatchTasks.count + pendingDeleteTasks.count
    }

    private var syncStatusTitle: String {
        "\(pendingSyncItemCount) \(pendingSyncItemCount == 1 ? "item" : "items") syncing"
    }

    private var syncStatusExplanation: String {
        if saveError != nil {
            return "These items are visible here and included in your calories. Sync is retrying in the background."
        }

        return "These items are visible here and included in your calories. They are still syncing and will be confirmed automatically."
    }

    private var streakDockIndicator: some View {
        Button {
            isStreakDrawerPresented = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 60, height: 60)

                if isLoadingFoodLogStreak && currentFoodLogStreak == nil {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(8)
                } else {
                    Text("\(currentFoodLogStreak ?? 0)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(.regularMaterial, in: Circle())
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Open \(currentFoodLogStreak ?? 0)-day food streak"))
    }

    private func bottomDockButton(
        systemImage: String,
        color: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 60, height: 60)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var topHeaderStrip: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                isProfilePresented = true
            } label: {
                HomeGreetingChip(firstName: loggedInFirstName)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Open profile"))

            Spacer(minLength: 0)

            Button {
                isCalendarPresented = true
            } label: {
                Text(todayPillTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.96) : Color.primary.opacity(0.80))
            }
            .buttonStyle(LiquidGlassCapsuleButtonStyle())
            .accessibilityLabel(Text("Select date"))
        }
        .padding(.horizontal, 10)
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
        let session = appStore.authSessionStore.session
        let emailLocalPart = session?.email?
            .split(separator: "@", maxSplits: 1)
            .first
            .map(String.init)

        if let firstName = normalizedFirstName(from: session?.firstName) {
            // Ignore low-quality values that are identical to an email username like "shantanuodak".
            if let emailLocalPart,
               firstName.caseInsensitiveCompare(emailLocalPart) == .orderedSame,
               !emailLocalPart.contains(where: { !$0.isLetter }) {
                // Fall through to JWT or better sources.
            } else {
                return firstName
            }
        }

        if let firstName = normalizedFirstName(fromJWT: session?.accessToken) {
            return firstName
        }

        return normalizedFirstName(fromEmail: session?.email)
    }

    private func normalizedFirstName(from rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let firstToken = trimmed.split(whereSeparator: { !$0.isLetter }).first
        guard let firstToken, !firstToken.isEmpty else {
            return nil
        }

        return firstToken.prefix(1).uppercased() + firstToken.dropFirst().lowercased()
    }

    private func normalizedFirstName(fromEmail email: String?) -> String? {
        guard let email else {
            return nil
        }

        guard let localPart = email.split(separator: "@", maxSplits: 1).first.map(String.init) else {
            return nil
        }

        // Only use email fallback when a clear separator exists (e.g. john.doe, john_doe).
        guard localPart.contains(where: { !$0.isLetter }) else {
            return nil
        }

        return normalizedFirstName(from: localPart)
    }

    private func normalizedFirstName(fromJWT token: String?) -> String? {
        guard let token else {
            return nil
        }

        let segments = token.split(separator: ".")
        guard segments.count > 1 else {
            return nil
        }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = payload.count % 4
        if padding > 0 {
            payload += String(repeating: "=", count: 4 - padding)
        }

        guard let data = Data(base64Encoded: payload),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let claims = jsonObject as? [String: Any] else {
            return nil
        }

        if let firstName = extractFirstName(from: claims) {
            return firstName
        }

        if let metadata = claims["user_metadata"] as? [String: Any] {
            return extractFirstName(from: metadata)
        }

        return nil
    }

    private func extractFirstName(from source: [String: Any]) -> String? {
        for key in ["name", "full_name"] {
            if let value = source[key] as? String,
               value.contains(where: { !$0.isLetter }),
               let first = normalizedFirstName(from: value) {
                return first
            }
        }

        if let givenName = source["given_name"] as? String {
            let familyNameCandidate = (source["family_name"] as? String) ?? (source["last_name"] as? String)
            if let familyName = familyNameCandidate {
                let normalizedGiven = givenName.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedFamily = familyName.trimmingCharacters(in: .whitespacesAndNewlines)

                if !normalizedGiven.isEmpty,
                   !normalizedFamily.isEmpty,
                   normalizedGiven.count > normalizedFamily.count,
                   normalizedGiven.lowercased().hasSuffix(normalizedFamily.lowercased()) {
                    let firstOnly = String(normalizedGiven.dropLast(normalizedFamily.count))
                    if let first = normalizedFirstName(from: firstOnly) {
                        return first
                    }
                }
            }
        }

        for key in ["given_name", "first_name"] {
            if let value = source[key] as? String,
               let first = normalizedFirstName(from: value) {
                return first
            }
        }

        return nil
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

            selectedSummaryDate = normalized
            dayTransitionOffset = -slideOut * 0.6
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                dayTransitionOffset = 0
            }
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

    private func clampedSummaryDate(_ date: Date) -> Date {
        HomeLoggingDateUtils.clampedSummaryDate(date)
    }

    private var isEmptyHomeState: Bool {
        trimmedNoteText.isEmpty &&
            parseResult == nil &&
            editableItems.isEmpty
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
        let totals = visibleNutritionTotals
        let macroCalories = max(1.0, totals.protein * 4 + totals.carbs * 4 + totals.fat * 9)

        return NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Daily Calories")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("\(Int(totals.calories.rounded())) kcal")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                VStack(spacing: 12) {
                    nutrientRow(
                        title: "Protein",
                        value: totals.protein,
                        suffix: "g",
                        percent: (totals.protein * 4) / macroCalories,
                        color: .blue
                    )
                    nutrientRow(
                        title: "Carbs",
                        value: totals.carbs,
                        suffix: "g",
                        percent: (totals.carbs * 4) / macroCalories,
                        color: .green
                    )
                    nutrientRow(
                        title: "Fat",
                        value: totals.fat,
                        suffix: "g",
                        percent: (totals.fat * 9) / macroCalories,
                        color: .orange
                    )
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle(summaryDateString == HomeLoggingDateUtils.summaryRequestFormatter.string(from: Date()) ? "Today" : summaryDateString)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var visibleNutritionTotals: NutritionTotals {
        inputRows.reduce(NutritionTotals(calories: 0, protein: 0, carbs: 0, fat: 0)) { totals, row in
            let rowCalories = Double(row.calories ?? 0)
            let rowProtein: Double
            let rowCarbs: Double
            let rowFat: Double

            if !row.parsedItems.isEmpty {
                rowProtein = row.parsedItems.reduce(0) { $0 + $1.protein }
                rowCarbs = row.parsedItems.reduce(0) { $0 + $1.carbs }
                rowFat = row.parsedItems.reduce(0) { $0 + $1.fat }
            } else if let item = row.parsedItem {
                rowProtein = item.protein
                rowCarbs = item.carbs
                rowFat = item.fat
            } else {
                rowProtein = 0
                rowCarbs = 0
                rowFat = 0
            }

            return NutritionTotals(
                calories: totals.calories + rowCalories,
                protein: totals.protein + rowProtein,
                carbs: totals.carbs + rowCarbs,
                fat: totals.fat + rowFat
            )
        }
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

    private func nutrientRow(title: String, value: Double, suffix: String, percent: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(Int(value.rounded()))\(suffix) · \(Int((percent * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(0, min(proxy.size.width, proxy.size.width * percent)))
                }
            }
            .frame(height: 10)
        }
    }

    private var activityCard: some View {
        HStack(spacing: 10) {
            activityPill(
                icon: "figure.walk",
                value: formatSteps(appStore.todaySteps),
                label: "Steps"
            )
            activityPill(
                icon: "flame.fill",
                value: "\(Int(appStore.todayActiveEnergy))",
                label: "Active kcal"
            )
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.08)))
    }

    private func activityPill(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)
                Text(value)
                    .font(.subheadline.weight(.bold))
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
    }

    private func formatSteps(_ steps: Double) -> String {
        if steps >= 1000 {
            let formatted = String(format: "%.1f", steps / 1000)
            let trimmed = formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
            return "\(trimmed)k"
        }
        return "\(Int(steps))"
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
    private func parseSummaryCard(_: ParseLogResponse) -> some View {
        HM03ParseSummarySection(
            totals: displayedTotals,
            hasEditedItems: !editableItems.isEmpty
        )
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
                Text("Sources: \(sources.map(sourceDisplayName).joined(separator: ", "))")
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

    private func sourceDisplayName(_ source: String) -> String {
        switch source.lowercased() {
        case "gemini":
            return "Gemini"
        case "cache":
            return "Cache"
        case "manual":
            return "Manual"
        default:
            return source
        }
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
    private func summaryProgressRow(
        title: String,
        consumed: Double,
        target: Double,
        remaining: Double,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 0) {
                    RollingNumberText(value: consumed, fractionDigits: 1)
                    Text("/")
                    RollingNumberText(value: target, fractionDigits: 1)
                    Text(" \(unit)")
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressFraction(consumed: consumed, target: target))
                .tint(.green)

            Text(L10n.remainingLabel(max(remaining, 0), unit: unit))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.85))
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let loggedAtLabel = drawerLoggedAtLabel(from: parseResult?.loggedAt) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.caption)
                            Text("Logged at \(loggedAtLabel)")
                                .font(.footnote)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                    }

                    if detailsDrawerMode == .manualAdd {
                        manualAddDrawerContent
                    } else if let parseResult {
                        if detailsDrawerMode == .compact {
                            compactDrawerContent(parseResult)
                        } else {
                            fullDrawerContent(parseResult)
                        }
                    } else {
                        Text(L10n.parseFirstHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.parseDetailsTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    drawerCheckmarkButton(accessibilityLabel: L10n.doneButton) {
                        isDetailsDrawerPresented = false
                    }
                }
            }
        }
    }

    private func drawerLoggedAtLabel(from loggedAtISO: String?) -> String? {
        guard let date = drawerLoggedAtDate(from: loggedAtISO) else { return nil }
        return Self.drawerLoggedAtDisplayFormatter.string(from: date)
    }

    private func drawerLoggedAtDate(from loggedAtISO: String?) -> Date? {
        if let raw = loggedAtISO?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            if let parsed = HomeLoggingDateUtils.loggedAtFormatter.date(from: raw) {
                return parsed
            }
            if let parsed = Self.loggedAtNoFractionFormatter.date(from: raw) {
                return parsed
            }
            if let parsed = Self.loggedAtGenericFormatter.date(from: raw) {
                return parsed
            }
        }
        return draftLoggedAt ?? draftTimestampForSelectedDate()
    }

    private static let drawerLoggedAtDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let loggedAtNoFractionFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let loggedAtGenericFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    @ViewBuilder
    private func rowCalorieDetailsSheet(_ details: RowCalorieDetails) -> some View {
        let liveDetails = liveRowCalorieDetails(for: details.id, fallback: details)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let imageData = liveDetails.imagePreviewData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    } else if let imageRef = liveDetails.imageRef,
                              !imageRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Food Photo")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Stored as \(imageRef)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(detailMutedFillColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(detailBorderColor, lineWidth: 1)
                                )
                        )
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(liveDetails.displayName)
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(liveDetails.calories) cal")
                                .font(.title2.weight(.bold))
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 6) {
                            if liveDetails.hasManualOverride {
                                Text("Manual Override")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.orange.opacity(0.15))
                                    )
                            }
                            if !liveDetails.hasManualOverride {
                                Text(liveDetails.itemConfidence == nil ? "Confidence" : "Match Confidence")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(Int((liveDetails.primaryConfidence * 100).rounded()))%")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(liveDetails.primaryConfidence >= 0.7 ? .green : .orange)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Macro Breakdown")
                            .font(.headline)

                        if let protein = liveDetails.protein,
                           let carbs = liveDetails.carbs,
                           let fat = liveDetails.fat {
                            HStack(spacing: 10) {
                                statPill(title: "Calories", value: "\(liveDetails.calories)")
                                statPill(title: "Protein", value: formatOneDecimal(protein) + "g")
                            }
                            HStack(spacing: 10) {
                                statPill(title: "Carbs", value: formatOneDecimal(carbs) + "g")
                                statPill(title: "Fat", value: formatOneDecimal(fat) + "g")
                            }
                        } else {
                            Text("Macro breakdown is not available for this row yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if liveDetails.parsedItems.count > 1 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Items")
                                .font(.headline)
                            ForEach(Array(liveDetails.parsedItems.enumerated()), id: \.offset) { idx, item in
                                if item.isUnresolvedPlaceholder {
                                    unresolvedItemRow(rowID: liveDetails.id, itemIndex: idx, item: item)
                                } else {
                                    HStack(alignment: .center, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .font(.subheadline.weight(.medium))
                                            Text("\(item.quantity.formatted()) \(item.unit)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(Int(item.calories.rounded())) cal")
                                                .font(.subheadline.weight(.semibold))
                                            if let protein = Optional(item.protein),
                                               let carbs = Optional(item.carbs),
                                               let fat = Optional(item.fat) {
                                                Text("P \(formatOneDecimal(protein))g · C \(formatOneDecimal(carbs))g · F \(formatOneDecimal(fat))g")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(detailCardFillColor)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(detailBorderColor, lineWidth: 1)
                                            )
                                    )
                                }
                            }
                        }
                    }

                    if liveDetails.hasManualOverride {
                        manualOverrideSection(liveDetails)
                    }

                    if shouldShowServingSizeSection(liveDetails) {
                        rowServingSizeSection(liveDetails)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Why this match")
                                .font(.headline)
                            Spacer()
                            Text(liveDetails.sourceLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(detailSecondaryTextColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(detailMetadataPillFillColor)
                                )
                        }
                        Text(liveDetails.thoughtProcess)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(detailCardFillColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(detailBorderColor, lineWidth: 1)
                            )
                    )


                }
                .padding()
            }
            .navigationTitle("Item Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Button(role: .destructive) {
                            rowDetailsPendingDeleteID = liveDetails.id
                            isRowDetailsDeleteConfirmationPresented = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .tint(.red)
                        .disabled(isRowDetailsDeleteDisabled(rowID: liveDetails.id))
                        .accessibilityHint(Text("Deletes this food entry and updates your totals."))

                        drawerCheckmarkButton(accessibilityLabel: L10n.doneButton) {
                            selectedRowDetails = nil
                        }
                    }
                }
            }
        }
        .alert("How sure are you that you want to delete this entry?", isPresented: $isRowDetailsDeleteConfirmationPresented) {
            Button("Delete", role: .destructive) {
                if let rowID = rowDetailsPendingDeleteID {
                    confirmRowDetailsDelete(rowID: rowID)
                }
                rowDetailsPendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) {
                rowDetailsPendingDeleteID = nil
            }
        } message: {
            Text("This removes the food from your log, updates your calories, and deletes the database row when it has already synced.")
        }
        .presentationDetents([.fraction(0.62), .large])
        .presentationDragIndicator(.visible)
    }

    private func drawerCheckmarkButton(accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.headline.weight(.semibold))
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
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
        if normalizedLookupValue(parseResult?.route ?? "") == "gemini" {
            return false
        }
        return !servingSizeEntries(for: details).isEmpty
    }

    private func servingSizeEntries(for details: RowCalorieDetails) -> [(offset: Int, item: ParsedFoodItem, options: [ParsedServingOption])] {
        Array(details.parsedItems.enumerated()).compactMap { itemOffset, item in
            if isGeminiParsedItem(item) {
                return nil
            }
            guard let servingOptions = rowServingOptions(rowID: details.id, itemOffset: itemOffset, fallback: item),
                  !servingOptions.isEmpty else {
                return nil
            }
            return (offset: itemOffset, item: item, options: servingOptions)
        }
    }

    private func isGeminiParsedItem(_ item: ParsedFoodItem) -> Bool {
        let source = normalizedLookupValue(item.nutritionSourceId)
        let family = normalizedLookupValue(item.sourceFamily ?? "")
        return source.contains("gemini") || family == "gemini"
    }

    private func shouldShowGeminiSourcesSection(_ details: RowCalorieDetails) -> Bool {
        let route = normalizedLookupValue(parseResult?.route ?? "")
        if route == "gemini" {
            return true
        }
        if details.parsedItems.contains(where: isGeminiParsedItem) {
            return true
        }
        if let sourcesUsed = parseResult?.sourcesUsed {
            return sourcesUsed.contains { normalizedLookupValue($0) == "gemini" }
        }
        return false
    }

    private func sourceChipsForDetails(_ details: RowCalorieDetails) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        if let sourcesUsed = parseResult?.sourcesUsed {
            for source in sourcesUsed {
                let label = sourceDisplayName(source)
                if seen.insert(label).inserted {
                    ordered.append(label)
                }
            }
        }

        let route = parseResult?.route
        for item in details.parsedItems {
            let label = nutritionSourceDisplayName(item.nutritionSourceId, route: route)
            if seen.insert(label).inserted {
                ordered.append(label)
            }
        }

        return ordered
    }

    private func sourceReferencesForDetails(_ details: RowCalorieDetails) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        for item in details.parsedItems {
            let rawID = item.nutritionSourceId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawID.isEmpty else { continue }
            let label = sourceReferenceLabel(for: rawID)
            if seen.insert(label).inserted {
                ordered.append(label)
            }
        }

        if ordered.isEmpty {
            let chips = sourceChipsForDetails(details)
            for chip in chips where seen.insert(chip).inserted {
                ordered.append(chip)
            }
        }

        return ordered
    }

    private func sourceReferenceLabel(for rawSourceID: String) -> String {
        let normalized = normalizedLookupValue(rawSourceID)
        if normalized.contains("gemini") {
            return "Gemini nutrition estimate"
        }
        if normalized.contains("cache") {
            return "Cached nutrition result"
        }
        if normalized.contains("manual") {
            return "Manual nutrition edit"
        }
        return rawSourceID
    }

    @ViewBuilder
    private func rowSourcesSection(_ details: RowCalorieDetails) -> some View {
        let chips = sourceChipsForDetails(details)
        let references = sourceReferencesForDetails(details)

        VStack(alignment: .leading, spacing: 10) {
            Text("Sources")
                .font(.headline)
            Text("Nutrition references used for this estimate.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(detailPrimaryTextColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(detailMutedFillColor)
                                )
                        }
                    }
                }
            }

            if !references.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(references, id: \.self) { reference in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                            Text(reference)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
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
    private var manualAddDrawerContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Manual Add Options")
                .font(.headline)
            Text("Pick a manual path to keep logging when auto-parse is not ideal.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Add custom food item") { }
                .buttonStyle(.bordered)
            Button("Add from recent foods") { }
                .buttonStyle(.bordered)
            Button("Back to text mode") {
                inputMode = .text
                detailsDrawerMode = .full
                isDetailsDrawerPresented = false
            }
            .buttonStyle(.borderedProminent)
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
            autoSaveTask?.cancel()
            autoSaveTask = nil
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
        let sourceLabel = sourceLabelForRowItems(resolvedItems, route: parseResult?.route)
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
            thoughtProcess: thoughtProcessText(for: row, sourceLabel: sourceLabel, items: resolvedItems),
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
            } else if item.manualOverride == true || normalizedLookupValue(item.sourceFamily ?? "") == "manual" {
                editedFieldSet.insert("nutrition")
            }

            let originalSourceID = (item.originalNutritionSourceId ?? item.nutritionSourceId)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !originalSourceID.isEmpty {
                originalSourceSet.insert(sourceReferenceLabel(for: originalSourceID))
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

    private func applyRowServingOption(rowID: UUID, itemOffset: Int, option: ParsedServingOption) {
        guard let rowIndex = inputRows.firstIndex(where: { $0.id == rowID }) else { return }
        guard inputRows[rowIndex].parsedItems.indices.contains(itemOffset) else { return }
        applyRowParsedItemEdit(rowIndex: rowIndex, itemOffset: itemOffset) { editable in
            editable.applyServingOption(option)
        }
    }

    private func isServingOptionSelected(rowID: UUID, itemOffset: Int, option: ParsedServingOption) -> Bool {
        guard let rowIndex = inputRows.firstIndex(where: { $0.id == rowID }),
              inputRows[rowIndex].parsedItems.indices.contains(itemOffset) else {
            return false
        }
        let rowItem = inputRows[rowIndex].parsedItems[itemOffset]
        let rowSource = normalizedLookupValue(rowItem.nutritionSourceId)
        let optionSource = normalizedLookupValue(option.nutritionSourceId)
        if !rowSource.isEmpty, !optionSource.isEmpty, rowSource != optionSource {
            return false
        }

        let rowQuantity = max(rowItem.quantity, 0.0001)
        let optionQuantity = servingOptionUsesServingBasis(option) ? 1.0 : max(option.quantity, 0.0001)
        let rowGramsPerUnit = rowItem.gramsPerUnit ?? (rowItem.grams / rowQuantity)
        let optionGramsPerUnit = servingOptionUsesServingBasis(option)
            ? option.grams
            : (option.grams / optionQuantity)
        let rowCaloriesPerUnit = rowItem.calories / rowQuantity
        let optionCaloriesPerUnit = servingOptionUsesServingBasis(option)
            ? option.calories
            : (option.calories / optionQuantity)
        let rowProteinPerUnit = rowItem.protein / rowQuantity
        let optionProteinPerUnit = servingOptionUsesServingBasis(option)
            ? option.protein
            : (option.protein / optionQuantity)
        let rowCarbsPerUnit = rowItem.carbs / rowQuantity
        let optionCarbsPerUnit = servingOptionUsesServingBasis(option)
            ? option.carbs
            : (option.carbs / optionQuantity)
        let rowFatPerUnit = rowItem.fat / rowQuantity
        let optionFatPerUnit = servingOptionUsesServingBasis(option)
            ? option.fat
            : (option.fat / optionQuantity)

        return nearlyEqual(rowGramsPerUnit, optionGramsPerUnit, tolerance: 0.2) &&
            nearlyEqual(rowCaloriesPerUnit, optionCaloriesPerUnit, tolerance: 0.2) &&
            nearlyEqual(rowProteinPerUnit, optionProteinPerUnit, tolerance: 0.2) &&
            nearlyEqual(rowCarbsPerUnit, optionCarbsPerUnit, tolerance: 0.2) &&
            nearlyEqual(rowFatPerUnit, optionFatPerUnit, tolerance: 0.2)
    }

    private func servingOptionUsesServingBasis(_ option: ParsedServingOption) -> Bool {
        if abs(option.quantity - 1) > 0.0001 {
            return true
        }
        return isWeightOrVolumeServingUnit(option.unit)
    }

    private func isWeightOrVolumeServingUnit(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "g" || normalized == "gram" || normalized == "grams" ||
            normalized == "ml" || normalized == "milliliter" || normalized == "milliliters" ||
            normalized == "oz" || normalized == "ounce" || normalized == "ounces"
    }

    private func selectedServingOptionOffset(rowID: UUID, itemOffset: Int, servingOptions: [ParsedServingOption]) -> Int? {
        servingOptions.firstIndex { option in
            isServingOptionSelected(rowID: rowID, itemOffset: itemOffset, option: option)
        }
    }

    private func nearlyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double) -> Bool {
        abs(lhs - rhs) <= tolerance
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
        let normalizedSource = normalizedLookupValue(rowItem.nutritionSourceId)
        let normalizedName = normalizedLookupValue(rowItem.name)

        if let exact = editableItems.firstIndex(where: { item in
            normalizedLookupValue(item.nutritionSourceId) == normalizedSource &&
                normalizedLookupValue(item.name) == normalizedName
        }) {
            return exact
        }

        if let bySource = editableItems.firstIndex(where: {
            normalizedLookupValue($0.nutritionSourceId) == normalizedSource
        }) {
            return bySource
        }

        if let byName = editableItems.firstIndex(where: {
            normalizedLookupValue($0.name) == normalizedName
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

    private func normalizedLookupValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sourceLabelForRowItems(_ items: [ParsedFoodItem], route: String?) -> String {
        guard !items.isEmpty else {
            return nutritionSourceDisplayName(nil, route: route)
        }

        let labels = Array(Set(items.map { nutritionSourceDisplayName($0.nutritionSourceId, route: route) })).sorted()
        if labels.count == 1, let label = labels.first {
            return label
        }
        return labels.joined(separator: ", ")
    }

    private func nutritionSourceDisplayName(_ nutritionSourceId: String?, route: String?) -> String {
        let upstreamSource = upstreamNutritionSourceDisplayName(nutritionSourceId)

        guard let route else {
            return upstreamSource ?? "Estimate"
        }

        let normalizedRoute = route.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedRoute == "cache" {
            if let upstreamSource {
                return "Cache (\(upstreamSource))"
            }
            return "Cache"
        }

        return upstreamSource ?? L10n.routeDisplayName(route)
    }

    private func upstreamNutritionSourceDisplayName(_ nutritionSourceId: String?) -> String? {
        guard let nutritionSourceId else { return nil }
        let trimmed = nutritionSourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.lowercased()
        if normalized.contains("gemini") {
            return "Gemini"
        }
        if normalized.contains("manual") {
            return "Manual"
        }
        if normalized.contains("cache") {
            return "Cache"
        }
        return nil
    }

    private func thoughtProcessText(for row: HomeLogRow, sourceLabel: String, items: [ParsedFoodItem]) -> String {
        let rowText = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if items.count > 1 {
            let itemNames = items.map(\.name)
            let previewNames: String
            if itemNames.count <= 3 {
                previewNames = itemNames.joined(separator: ", ")
            } else {
                previewNames = itemNames.prefix(3).joined(separator: ", ") + " +\(itemNames.count - 3) more"
            }
            let estimatedCalories = Int(items.reduce(0) { $0 + $1.calories }.rounded())
            var thought = "Interpreted “\(rowText)” as multiple items: \(previewNames). "
            thought += "Used \(sourceLabel) nutrition data to estimate \(estimatedCalories) kcal total."
            if row.isApproximate || (parseResult?.needsClarification == true) {
                thought += " This is marked as approximate because confidence is below the strict threshold."
            }
            return thought
        }

        if let item = items.first {
            if let explanation = item.explanation, !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return explanation
            }
            var thought = "Interpreted “\(rowText)” as “\(item.name)”. "
            thought += "Used \(formatOneDecimal(item.quantity)) \(item.unit) (~\(formatOneDecimal(item.grams)) g) "
            thought += "with \(sourceLabel) nutrition data to estimate \(Int(item.calories.rounded())) kcal and scale macros."
            if row.isApproximate || (parseResult?.needsClarification == true) {
                thought += " This is marked as approximate because confidence is below the strict threshold."
            }
            return thought
        }

        var fallback = "A calorie estimate is available for this row, but no fully matched nutrition item was retained."
        fallback += " Re-parse or open Parse Details to refine mapping and macro breakdown."
        return fallback
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
        let rowText = shortenedFoodLabel(items: items, extractedText: response.extractedText)

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
        isImagePickerPresented = false
        debounceTask?.cancel()
        parseTask?.cancel()
        autoSaveTask?.cancel()
        parseRequestSequence += 1

        guard let prepared = prepareImagePayload(from: image) else {
            parseError = "Unable to process this image. Please try another photo."
            inputMode = .text
            selectedCameraSource = nil
            return
        }

        ensureDraftTimingStarted()

        pendingImageData = prepared.uploadData
        pendingImagePreviewData = prepared.previewData
        pendingImageMimeType = prepared.mimeType
        pendingImageStorageRef = nil
        latestParseInputKind = "image"

        parseInfoMessage = "Analyzing photo…"
        parseError = nil
        saveError = nil
        saveSuccessMessage = nil
        escalationError = nil
        escalationInfoMessage = nil
        escalationBlockedCode = nil
        completedRowParses = []
        if useParseCoordinator {
            parseCoordinator.clearAll()
        }
        autoSavedParseIDs = []
        clearPendingSaveContext()
        appStore.setError(nil)

        parseInFlightCount += 1
        let startedAt = Date()
        defer {
            parseInFlightCount = max(0, parseInFlightCount - 1)
            inputMode = .text
            selectedCameraSource = nil
        }

        do {
            let response = try await appStore.apiClient.parseImageLog(
                imageData: prepared.uploadData,
                mimeType: prepared.mimeType,
                loggedAt: HomeLoggingDateUtils.loggedAtFormatter.string(from: draftLoggedAt ?? draftTimestampForSelectedDate())
            )
            let durationMs = elapsedMs(since: startedAt)

            var rowText = (response.extractedText ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if rowText.isEmpty {
                rowText = response.items.map(\.name).joined(separator: ", ")
            }
            if rowText.isEmpty {
                rowText = "Photo meal"
            }

            var row = HomeLogRow.empty()
            row.text = rowText
            row.imagePreviewData = prepared.previewData
            row.imageRef = pendingImageStorageRef
            suppressDebouncedParseOnce = true

            let savedRows = inputRows.filter { $0.isSaved }
            let unsavedNonEmpty = inputRows.filter {
                !$0.isSaved && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            inputRows = savedRows + unsavedNonEmpty + [row]
            clearParseSchedulerState()

            parseResult = response
            latestParseInputKind = normalizedInputKind(response.inputKind, fallback: "image")
            editableItems = response.items.map(EditableParsedItem.init(apiItem:))
            let imageRowIDs: Set<UUID> = [row.id]
            applyRowParseResult(response, targetRowIDs: imageRowIDs)
            if let idx = inputRows.lastIndex(where: { $0.id == row.id }) {
                inputRows[idx].imagePreviewData = prepared.previewData
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
            scheduleDetailsDrawer(for: response)
            emitParseTelemetrySuccess(response: response, durationMs: durationMs, uiApplied: true)
            scheduleAutoSave()
        } catch {
            let durationMs = elapsedMs(since: startedAt)
            handleAuthFailureIfNeeded(error)
            parseInfoMessage = nil
            parseError = userFriendlyParseError(error)
            appStore.setError(parseError)
            emitParseTelemetryFailure(error: error, durationMs: durationMs, uiApplied: true)
        }
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
            response: response,
            rowItems: rowItemsSnapshot,
            capturedAt: Date()
        )
        if useParseCoordinator {
            parseCoordinator.commit(snapshot: rowEntry)
            return
        }
        if let idx = completedRowParses.firstIndex(where: { $0.rowID == rowID }) {
            completedRowParses[idx] = rowEntry
        } else {
            completedRowParses.append(rowEntry)
        }
    }

    private func prepareImagePayload(from image: UIImage) -> PreparedImagePayload? {
        let resized = resizeImageIfNeeded(image, maxDimension: 1600)
        let qualityAttempts: [CGFloat] = [0.86, 0.78, 0.70, 0.62, 0.55]
        let maxBytes = 5_800_000

        for quality in qualityAttempts {
            guard let data = resized.jpegData(compressionQuality: quality) else {
                continue
            }
            if data.count <= maxBytes {
                return PreparedImagePayload(uploadData: data, previewData: data, mimeType: "image/jpeg")
            }
        }

        guard let fallbackData = resized.jpegData(compressionQuality: 0.5) else {
            return nil
        }
        return PreparedImagePayload(uploadData: fallbackData, previewData: fallbackData, mimeType: "image/jpeg")
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

    @ViewBuilder
    private func compactDrawerContent(_ parseResult: ParseLogResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Confirmation")
                .font(.headline)
            HStack(spacing: 0) {
                Text("Confidence: ")
                RollingNumberText(value: parseResult.confidence, fractionDigits: 3)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            HM03ParseSummarySection(
                totals: displayedTotals,
                hasEditedItems: !editableItems.isEmpty
            )

            HStack(spacing: 12) {
                Button(L10n.saveLogButton) {
                    startSaveFlow()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isSaving || buildSaveDraftRequest() == nil)

                Button("Open Full Details") {
                    detailsDrawerMode = .full
                }
                .buttonStyle(.bordered)
            }

        }
    }

    @ViewBuilder
    private func fullDrawerContent(_ parseResult: ParseLogResponse) -> some View {
        HM03ParseSummarySection(
            totals: displayedTotals,
            hasEditedItems: !editableItems.isEmpty
        )

        parseMetaCard(parseResult)

        if !isParsing && appStore.isNetworkReachable {
            Button(L10n.retryParseButton) {
                isDetailsDrawerPresented = false
                triggerParseNow()
            }
            .font(.system(size: 14, weight: .semibold))
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        parseActionSection

        if let parseError {
            Text(parseError)
                .font(.footnote)
                .foregroundStyle(.red)
        }

        daySummarySection

        Group {
            Text(L10n.parseMetadataTitle)
                .font(.headline)
            Text(L10n.routeLabel(parseResult.route))
                .font(.footnote)
            Text(L10n.parseRequestIDLabel(parseResult.parseRequestId))
                .font(.footnote)
            Text(L10n.parseVersionLabel(parseResult.parseVersion))
                .font(.footnote)
            HStack(spacing: 0) {
                Text("\(L10n.confidenceLabel): ")
                RollingNumberText(value: parseResult.confidence, fractionDigits: 3)
            }
            .font(.footnote)
        }
        .foregroundStyle(.secondary)

        if parseResult.needsClarification {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.clarificationQuestionsTitle)
                    .font(.headline)
                ForEach(Array(parseResult.clarificationQuestions.enumerated()), id: \.offset) { _, question in
                    Text("• \(question)")
                        .font(.footnote)
                }
            }
        }

        clarificationEscalationSection(parseResult)

        if parseResult.items.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Items")
                    .font(.headline)
                ForEach(Array(parseResult.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(item.quantity.formatted()) \(item.unit)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(item.calories.rounded())) cal")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.08))
                    )
                }
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.editableItemsTitle)
                .font(.headline)
            ForEach($editableItems) { $item in
                VStack(alignment: .leading, spacing: 8) {
                    TextField(L10n.itemNamePlaceholder, text: $item.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Stepper(
                        value: Binding(
                            get: { item.quantity },
                            set: { item.updateQuantity($0) }
                        ),
                        in: 0 ... 20,
                        step: 0.5
                    ) {
                        Text(L10n.quantityLabel(item.quantity))
                            .font(.footnote)
                    }

                    TextField(L10n.unitPlaceholder, text: $item.unit)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack(spacing: 2) {
                        RollingNumberText(value: Double(Int(item.calories.rounded())), suffix: " kcal")
                        Text("• P ")
                        RollingNumberText(value: item.protein, fractionDigits: 1, suffix: "g")
                        Text(" • C ")
                        RollingNumberText(value: item.carbs, fractionDigits: 1, suffix: "g")
                        Text(" • F ")
                        RollingNumberText(value: item.fat, fractionDigits: 1, suffix: "g")
                    }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.08))
                )
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.saveActionsTitle)
                .font(.headline)

            HStack(spacing: 12) {
                Button(L10n.saveLogButton) {
                    startSaveFlow()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isSaving || buildSaveDraftRequest() == nil)

                Button(L10n.retryLastSaveButton) {
                    retryLastSave()
                }
                .buttonStyle(.bordered)
                .disabled(isSaving || pendingSaveRequest == nil || pendingSaveIdempotencyKey == nil)
            }

            if let saveSuccessMessage {
                Text(saveSuccessMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }

            if let saveError {
                Text(saveError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let pendingSaveIdempotencyKey {
                Text(L10n.idempotencyKey(pendingSaveIdempotencyKey.uuidString.lowercased()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.saveContractPreviewTitle)
                .font(.headline)
            Text(saveDraftPreviewJSON())
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.05))
                )
        }
    }

    @MainActor
    private func scheduleDebouncedParse(for newValue: String) {
        debounceTask?.cancel()
        autoSaveTask?.cancel()
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
            completedRowParses = []
            autoSavedParseIDs = []
            if useParseCoordinator {
                parseCoordinator.clearAll()
            }
            clearParseSchedulerState()
            let clearedRowIDs = Set(inputRows.filter { !$0.isSaved }.map(\.id))
            if !clearedRowIDs.isEmpty {
                let previousQueueCount = pendingSaveQueue.count
                pendingSaveQueue.removeAll { item in
                    guard item.serverLogId == nil, let rowID = item.rowID else {
                        return false
                    }
                    return clearedRowIDs.contains(rowID)
                }
                if pendingSaveQueue.count != previousQueueCount {
                    persistPendingSaveQueue()
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

        let request = ParseLogRequest(
            text: text,
            loggedAt: HomeLoggingDateUtils.loggedAtFormatter.string(from: draftLoggedAt ?? draftTimestampForSelectedDate())
        )

        do {
            let response = try await appStore.apiClient.parseLog(request)
            let durationMs = elapsedMs(since: startedAt)

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
                let normalizedSent = normalizedRowText(snapshot.text)
                let normalizedCurrent = normalizedRowText(currentRow.text)
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
            // will use completedRowParses[n].rawText instead of trimmedNoteText.
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
            if useParseCoordinator {
                parseCoordinator.markFailed(rowID: snapshot.activeRowID)
            }
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
        return response.route == "unresolved" || response.route == "gemini"
    }

    private func scheduleUnresolvedRetryIfNeeded(
        _ response: ParseLogResponse,
        requestText: String,
        requestSequence: Int
    ) {
        let reasonCodes = response.reasonCodes ?? []
        guard reasonCodes.contains("gemini_circuit_open") else { return }
        guard unresolvedRetryCount < 2 else { return }

        let retryAfterSeconds = max(1, response.retryAfterSeconds ?? 4)
        unresolvedRetryTask?.cancel()
        unresolvedRetryTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(retryAfterSeconds) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard requestText == trimmedNoteText else { return }
            guard requestSequence == parseRequestSequence else { return }

            await MainActor.run {
                unresolvedRetryCount += 1
                triggerParseNow()
            }
        }
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
        inFlightParseSnapshot = InFlightParseSnapshot(
            text: text,
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
        if useParseCoordinator {
            parseCoordinator.markInFlight(rowID: activeRowID)
        }
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
        if useParseCoordinator, let activeParseRowID {
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
        autoSaveTask?.cancel()
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
        if !completedRowParses.isEmpty { completedRowParses = [] }
        if !autoSavedParseIDs.isEmpty { autoSavedParseIDs = [] }
        if useParseCoordinator {
            parseCoordinator.clearAll()
        }
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
        let normalizedCurrentText = normalizedRowText(row.text)
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
            let normalized = normalizedRowText(row.text)
            guard !normalized.isEmpty else { return false }
            if row.normalizedTextAtParse == nil { return true }
            if row.normalizedTextAtParse != normalized { return true }
            return row.calories == nil || (row.parsedItem == nil && row.parsedItems.isEmpty)
        })

        let lockedRowIndices: Set<Int> = Set(candidateRowIndices.filter { rowIndex in
            guard let existingCalories = inputRows[rowIndex].calories, existingCalories > 0 else {
                return false
            }
            let normalized = normalizedRowText(inputRows[rowIndex].text)
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
                let score = rowItemMatchScore(rowText: rowText, itemName: item.name)
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
                inputRows[rowIndex].normalizedTextAtParse = normalizedRowText(inputRows[rowIndex].text)
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
                inputRows[onlyRowIndex].normalizedTextAtParse = normalizedRowText(inputRows[onlyRowIndex].text)
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

    private func rowItemMatchScore(rowText: String, itemName: String) -> Double {
        let rowTokens = Set(normalizedMatchTokens(from: rowText))
        let itemTokens = Set(normalizedMatchTokens(from: itemName))
        guard !rowTokens.isEmpty, !itemTokens.isEmpty else { return 0.0 }

        let exactIntersection = rowTokens.intersection(itemTokens).count
        var weightedIntersection = Double(exactIntersection)

        // Typo-tolerant fuzzy token match (e.g. "cofeee" ~= "coffee") while keeping one-to-one alignment.
        var unmatchedItemTokens = itemTokens.subtracting(rowTokens)
        for rowToken in rowTokens.subtracting(itemTokens) {
            var bestItemToken: String?
            var bestSimilarity = 0.0
            for itemToken in unmatchedItemTokens {
                let similarity = fuzzyTokenSimilarity(rowToken, itemToken)
                if similarity > bestSimilarity {
                    bestSimilarity = similarity
                    bestItemToken = itemToken
                }
            }
            if let bestItemToken, bestSimilarity >= 0.80 {
                weightedIntersection += 0.75
                unmatchedItemTokens.remove(bestItemToken)
            }
        }

        let union = Double(rowTokens.count + itemTokens.count) - weightedIntersection
        guard union > 0 else { return 0.0 }

        let jaccard = weightedIntersection / union
        let rowCoverage = weightedIntersection / Double(rowTokens.count)
        let itemCoverage = weightedIntersection / Double(itemTokens.count)

        var score = max(jaccard, max(rowCoverage * 0.72, itemCoverage * 0.88))

        if itemCoverage == 1.0 || rowCoverage == 1.0 {
            score += 0.15
        }

        let normalizedRow = rowTokens.sorted().joined(separator: " ")
        let normalizedItem = itemTokens.sorted().joined(separator: " ")
        if normalizedRow.contains(normalizedItem) || normalizedItem.contains(normalizedRow) {
            score += 0.10
        }

        return min(score, 1.0)
    }

    private func fuzzyTokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs {
            return 1.0
        }
        if lhs.count < 3 || rhs.count < 3 {
            return 0.0
        }

        if lhs.contains(rhs) || rhs.contains(lhs) {
            return Double(min(lhs.count, rhs.count)) / Double(max(lhs.count, rhs.count))
        }

        let distance = levenshteinDistance(lhs, rhs)
        let maxLength = max(lhs.count, rhs.count)
        guard maxLength > 0 else { return 0.0 }
        return max(0, 1.0 - Double(distance) / Double(maxLength))
    }

    private func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        if lhs == rhs {
            return 0
        }

        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        if lhsChars.isEmpty {
            return rhsChars.count
        }
        if rhsChars.isEmpty {
            return lhsChars.count
        }

        var previous = Array(0 ... rhsChars.count)
        for (lhsIndex, lhsChar) in lhsChars.enumerated() {
            var current = Array(repeating: 0, count: rhsChars.count + 1)
            current[0] = lhsIndex + 1

            for (rhsIndex, rhsChar) in rhsChars.enumerated() {
                let insertion = current[rhsIndex] + 1
                let deletion = previous[rhsIndex + 1] + 1
                let substitution = previous[rhsIndex] + (lhsChar == rhsChar ? 0 : 1)
                current[rhsIndex + 1] = min(insertion, min(deletion, substitution))
            }
            previous = current
        }

        return previous[rhsChars.count]
    }

    private func normalizedMatchTokens(from text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }

    private func normalizedRowText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
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
            let normalized = normalizedRowText(inputRows[rowIndex].text)
            return "#\(rowIndex){action=\(action),lock=\(lockState),mapped=\(mapped),text=\(normalized)}"
        }.joined(separator: " | ")
        print("[parse_row_map] route=\(response.route) confidence=\(String(format: "%.3f", response.confidence)) rows=\(rowSummary)")
#endif
    }

    private func scheduleDetailsDrawer(for response: ParseLogResponse) {
        if response.needsClarification || response.confidence < 0.60 {
            detailsDrawerMode = .full
            return
        }

        if response.confidence < 0.85 {
            detailsDrawerMode = .compact
            return
        }

        detailsDrawerMode = .full
    }

    private func presentDetailsFromDock() {
        guard let parseResult else {
            detailsDrawerMode = .full
            isDetailsDrawerPresented = true
            return
        }
        scheduleDetailsDrawer(for: parseResult)
        isDetailsDrawerPresented = true
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
            calories: roundOneDecimal(calories),
            protein: roundOneDecimal(protein),
            carbs: roundOneDecimal(carbs),
            fat: roundOneDecimal(fat)
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
        // For image parses (completedRowParses is empty), fall back to trimmedNoteText.
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
            let savedDay = String((row.serverLoggedAt ?? summaryDateString).prefix(10))
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
            let savedDay = String((originalDay ?? saveRequest.parsedLog.loggedAt).prefix(10))
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
            return (serverLogId, String((row.serverLoggedAt ?? summaryDateString).prefix(10)))
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
            if useParseCoordinator {
                parseCoordinator.cancelInFlight(rowID: rowID)
            }
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
            completedRowParses.removeAll { $0.rowID == rowID }
        }
        if useParseCoordinator {
            parseCoordinator.removeSnapshot(rowID: rowID)
        }
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
        autoSaveTask?.cancel()
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
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: autoSaveDelayNs)
            guard !Task.isCancelled else { return }
            await autoSaveIfNeeded()
        }
    }

    private var hasSaveableRowsPending: Bool {
        activeParseSnapshots.contains(where: { isAutoSaveEligibleEntry($0) })
    }

    private func autoSaveIfNeeded() async {
        guard appStore.isNetworkReachable else { return }
        guard !isSaving else { return }

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
            if let row = inputRows.first(where: { $0.id == entry.rowID }),
               let serverLogId = row.serverLogId {
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

        // Legacy path for image parses, which set parseResult directly and bypass
        // completedRowParses. Fall back to the old single-request path when no
        // completedRowParses entries exist (e.g. image-mode logging).
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

        guard hasCompletedRow || hasLegacyParse else { return }

        // Cancel the debounced auto-save task and run immediately
        autoSaveTask?.cancel()
        autoSaveTask = nil
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
        let effectiveLoggedAt = HomeLoggingDateUtils.loggedAtFormatter.string(from: draftLoggedAt ?? draftTimestampForSelectedDate())
        let items: [SaveParsedFoodItem]
        if sourceItems.isEmpty {
            let hasDisplayedCalories = currentRow?.calories != nil || response.totals.calories > 0
            guard hasDisplayedCalories else { return nil }
            items = [
                fallbackSaveItem(
                    rawText: entry.rawText,
                    totals: response.totals,
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
            calories: roundOneDecimal(items.reduce(0) { $0 + $1.calories }),
            protein: roundOneDecimal(items.reduce(0) { $0 + $1.protein }),
            carbs: roundOneDecimal(items.reduce(0) { $0 + $1.carbs }),
            fat: roundOneDecimal(items.reduce(0) { $0 + $1.fat })
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

        let calories = roundOneDecimal(max(0, totals.calories))
        let protein = roundOneDecimal(max(0, totals.protein))
        let carbs = roundOneDecimal(max(0, totals.carbs))
        let fat = roundOneDecimal(max(0, totals.fat))
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
        let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch normalized {
        case "text", "image", "voice", "manual":
            return normalized
        default:
            return fallback
        }
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
    private func submitSave(request: SaveLogRequest, idempotencyKey: UUID, isRetry: Bool, intent: SaveIntent) async -> Bool {
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

        let executionResult: SaveExecutionResult
        if useSaveCoordinator {
            executionResult = await saveCoordinator.executeSaveResult(
                request: request,
                idempotencyKey: idempotencyKey,
                prepareForNetwork: { request, key in
                    try await prepareSaveRequestForNetwork(request, idempotencyKey: key)
                }
            )
        } else {
            do {
                let effectiveRequest = try await prepareSaveRequestForNetwork(request, idempotencyKey: idempotencyKey)
                let response = try await appStore.apiClient.saveLog(effectiveRequest, idempotencyKey: idempotencyKey)
                executionResult = .success(
                    SaveExecutionSuccess(
                        preparedRequest: effectiveRequest,
                        response: response
                    )
                )
            } catch {
                executionResult = .failure(
                    SaveExecutionFailure(
                        effectiveRequest: request,
                        error: error
                    )
                )
            }
        }

        switch executionResult {
        case .success(let success):
            await handleSubmitSaveSuccess(
                success,
                queueKey: queueKey,
                submittedRowID: submittedRowID,
                telemetryRowID: telemetryRowID,
                idempotencyKey: idempotencyKey,
                intent: intent,
                isRetry: isRetry,
                startedAt: startedAt
            )
            return true
        case .failure(let failure):
            await handleSubmitSaveFailure(
                failure,
                telemetryRowID: telemetryRowID,
                idempotencyKey: idempotencyKey,
                intent: intent,
                isRetry: isRetry,
                startedAt: startedAt
            )
            return false
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
        startedAt: Date
    ) async {
        let effectiveRequest = success.preparedRequest
        let response = success.response
        let savedDay = String(effectiveRequest.parsedLog.loggedAt.prefix(10))
        if shouldDiscardCompletedSave(queueKey: queueKey, rowID: submittedRowID) {
            await deleteLateArrivingSave(logId: response.logId, savedDay: savedDay, queueKey: queueKey, rowID: submittedRowID)
            return
        }

        let prefix = isRetry ? L10n.retrySucceededPrefix : L10n.savedSuccessfullyPrefix
        let timeToLogMs = flowStartedAt.map { elapsedMs(since: $0) }
        if intent == .auto {
            saveSuccessMessage = nil
            lastAutoSavedContentFingerprint = autoSaveContentFingerprint(effectiveRequest)
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
        clearPendingSaveContext()
        if intent != .auto {
            flowStartedAt = nil
            draftLoggedAt = nil
        }
        if let parsedDate = HomeLoggingDateUtils.summaryRequestFormatter.date(from: savedDay) {
            selectedSummaryDate = parsedDate
        }
        promoteSavedRow(
            for: effectiveRequest,
            idempotencyKey: idempotencyKey,
            logId: response.logId
        )
        // Cancel prefetch to prevent it from re-populating cache with stale data
        prefetchTask?.cancel()
        await refreshDayAfterMutation(savedDay)
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
            if useSaveCoordinator {
                try await saveCoordinator.deleteLog(id: logId)
            } else {
                _ = try await appStore.apiClient.deleteLog(id: logId)
            }
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
        if useSaveCoordinator {
            saveCoordinator.scheduleDeferredImageUploadRetry(
                logId: logId,
                imageData: imageData,
                normalizedInputKind: kind,
                userIDHint: userIDHint
            )
            return
        }
        guard kind == "image" else { return }

        let storage = appStore.imageStorageService
        let api = appStore.apiClient
        let store = appStore.deferredImageUploadStore

        Task.detached(priority: .background) {
            await store?.enqueue(logId: logId, imageData: imageData)
            do {
                let imageRef = try await storage.uploadJPEG(imageData, userIdentifierHint: userIDHint)
                _ = try await api.updateLogImageRef(id: logId, imageRef: imageRef)
                await store?.remove(logId: logId)
                NSLog("[MainLogging] Deferred image upload succeeded for log \(logId)")
            } catch {
                NSLog("[MainLogging] Deferred image upload retry failed for log \(logId); persisted for next launch: \(error)")
            }
        }
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
            let requestText = normalizedRowText(request.parsedLog.rawText)
            let isImageSave = normalizedInputKind(request.parsedLog.inputKind, fallback: latestParseInputKind) == "image"
            if let index = inputRows.firstIndex(where: { row in
                guard !row.isSaved else { return false }
                if isImageSave, row.imagePreviewData != nil || row.imageRef != nil {
                    return true
                }
                return !requestText.isEmpty && normalizedRowText(row.text) == requestText
            }) {
                promoteInputRow(at: index, logId: logId, loggedAt: savedLoggedAt, imageRef: request.parsedLog.imageRef)
                promotedRowID = inputRows[index].id
            }
        }

        if promotedRowID == nil, let queuedItem {
            let optimisticRow = makePendingSaveRow(from: queuedItem)
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
        case .auto:
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
                item.dateString == dateString && item.serverLogId.map { !serverLogIds.contains($0) } ?? true
            }
            .sorted { $0.createdAt < $1.createdAt }
            .map(makePendingSaveRow)
    }

    private func makePendingSaveRow(from item: PendingSaveQueueItem) -> HomeLogRow {
        let body = item.request.parsedLog
        let parsedItems = body.items.map(parsedFoodItem(from:))
        let displayText: String
        if normalizedInputKind(body.inputKind, fallback: "text") == "image" &&
            body.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            displayText = "Photo meal"
        } else {
            displayText = body.rawText
        }
        let stableID = item.rowID ?? UUID(uuid: stableUUID(from: item.idempotencyKey))
        return HomeLogRow(
            id: stableID,
            text: displayText,
            calories: Int(body.totals.calories.rounded()),
            calorieRangeText: nil,
            isApproximate: false,
            parsePhase: .idle,
            parsedItem: parsedItems.first,
            parsedItems: parsedItems,
            editableItemIndices: [],
            normalizedTextAtParse: normalizedRowText(displayText),
            imagePreviewData: item.imagePreviewData,
            imageRef: body.imageRef,
            isSaved: true,
            savedAt: nil,
            serverLogId: item.serverLogId,
            serverLoggedAt: body.loggedAt
        )
    }

    private func parsedFoodItem(from item: SaveParsedFoodItem) -> ParsedFoodItem {
        ParsedFoodItem(
            name: item.name,
            quantity: item.amount ?? item.quantity,
            unit: item.unit,
            grams: item.grams,
            calories: item.calories,
            protein: item.protein,
            carbs: item.carbs,
            fat: item.fat,
            nutritionSourceId: item.nutritionSourceId,
            originalNutritionSourceId: item.originalNutritionSourceId,
            sourceFamily: item.sourceFamily,
            matchConfidence: item.matchConfidence,
            amount: item.amount,
            unitNormalized: item.unitNormalized,
            gramsPerUnit: item.gramsPerUnit,
            needsClarification: item.needsClarification,
            manualOverride: item.manualOverride?.enabled
        )
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
            .map { entry in
            let items: [ParsedFoodItem] = entry.items.map { item in
                ParsedFoodItem(
                    name: item.foodName,
                    quantity: item.quantity,
                    unit: item.unit,
                    grams: item.grams,
                    calories: item.calories,
                    protein: item.protein,
                    carbs: item.carbs,
                    fat: item.fat,
                    nutritionSourceId: item.nutritionSourceId,
                    sourceFamily: item.sourceFamily,
                    matchConfidence: item.matchConfidence,
                    unitNormalized: item.unitNormalized
                )
            }
            let stableID = UUID(uuidString: entry.id) ?? UUID(uuid: stableUUID(from: entry.id))
            let displayText: String
            if entry.inputKind == "image" && entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                displayText = "Photo meal"
            } else {
                displayText = entry.rawText
            }
            return HomeLogRow(
                id: stableID,
                text: displayText,
                calories: Int(entry.totals.calories.rounded()),
                calorieRangeText: nil,
                isApproximate: false,
                parsePhase: .idle,
                parsedItem: items.first,
                parsedItems: items,
                editableItemIndices: [],
                // Stamp with the server's rawText so subsequent edits compare
                // against the text that was actually parsed. Without this,
                // `rowNeedsFreshParse` would see nil and treat any quantity
                // edit as a brand-new parse, bypassing the client-side fast
                // path.
                normalizedTextAtParse: normalizedRowText(displayText),
                imagePreviewData: nil,
                imageRef: entry.imageRef,
                isSaved: true,
                savedAt: nil,
                serverLogId: entry.id,
                serverLoggedAt: entry.loggedAt
            )
        }
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

        // Full replace: remove ALL old saved rows and replace with the requested
        // day's entries. Keep active drafts only when their draft timestamp belongs
        // to the same day; otherwise a today draft visually leaks into yesterday.
        let pendingRows = pendingRowsForDate(dateString, excluding: entries)
        let pendingRowIDs = Set(pendingRows.map(\.id))
        let activeRows: [HomeLogRow]
        if shouldKeepActiveRows {
            activeRows = currentActiveRows.filter { !pendingRowIDs.contains($0.id) }
        } else {
            activeRows = []
        }
        inputRows = orderedSavedRows + pendingRows + activeRows

        // Ensure there's always at least one empty active row for input
        if inputRows.allSatisfy({ $0.isSaved }) {
            inputRows.append(.empty())
        }
    }

    private func stableUUID(from string: String) -> uuid_t {
        var hash: UInt64 = 5381
        for byte in string.utf8 { hash = ((hash &<< 5) &+ hash) &+ UInt64(byte) }
        let h1 = hash
        var hash2: UInt64 = 0x517cc1b727220a95
        for byte in string.utf8 { hash2 = hash2 &* 0x100000001b3; hash2 ^= UInt64(byte) }
        let h2 = hash2
        return (
            UInt8(truncatingIfNeeded: h1), UInt8(truncatingIfNeeded: h1 >> 8),
            UInt8(truncatingIfNeeded: h1 >> 16), UInt8(truncatingIfNeeded: h1 >> 24),
            UInt8(truncatingIfNeeded: h1 >> 32), UInt8(truncatingIfNeeded: h1 >> 40),
            UInt8(truncatingIfNeeded: h1 >> 48), UInt8(truncatingIfNeeded: h1 >> 56),
            UInt8(truncatingIfNeeded: h2), UInt8(truncatingIfNeeded: h2 >> 8),
            UInt8(truncatingIfNeeded: h2 >> 16), UInt8(truncatingIfNeeded: h2 >> 24),
            UInt8(truncatingIfNeeded: h2 >> 32), UInt8(truncatingIfNeeded: h2 >> 40),
            UInt8(truncatingIfNeeded: h2 >> 48), UInt8(truncatingIfNeeded: h2 >> 56)
        )
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
        guard let apiError = error as? APIClientError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        if isAuthTokenError(apiError) {
            return L10n.authSessionExpired
        }

        switch apiError {
        case let .server(_, payload):
            switch payload.code {
            case "PROFILE_NOT_FOUND":
                return L10n.daySummaryProfileNotFound
            case "INVALID_INPUT":
                return L10n.daySummaryInvalidInput
            default:
                return payload.message
            }
        case .networkFailure(_):
            return L10n.daySummaryNetworkFailure
        default:
            return apiError.errorDescription ?? L10n.daySummaryFailure
        }
    }

    private func progressFraction(consumed: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(max(consumed / target, 0), 1)
    }

    private func isSummaryEmpty(_ summary: DaySummaryResponse) -> Bool {
        summary.totals.calories <= 0.05 &&
            summary.totals.protein <= 0.05 &&
            summary.totals.carbs <= 0.05 &&
            summary.totals.fat <= 0.05
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

    private func legacyPendingSubmissionCandidates() -> [PendingSubmissionCandidate] {
        pendingSaveQueue.compactMap { item -> PendingSubmissionCandidate? in
            guard item.serverLogId == nil, let key = UUID(uuidString: item.idempotencyKey) else {
                return nil
            }
            return PendingSubmissionCandidate(item: item, idempotencyKey: key)
        }
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
        if useSaveCoordinator {
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
            return
        }

        let key = idempotencyKey.uuidString.lowercased()
        let dateString = String(request.parsedLog.loggedAt.prefix(10))
        let existingIndex = pendingSaveQueue.firstIndex { item in
            item.idempotencyKey == key || (rowID != nil && item.rowID == rowID && item.serverLogId == nil)
        }
        let existing = existingIndex.map { pendingSaveQueue[$0] }
        let item = PendingSaveQueueItem(
            id: existing?.id ?? UUID(),
            rowID: rowID ?? existing?.rowID,
            request: request,
            fingerprint: fingerprint,
            idempotencyKey: key,
            dateString: dateString,
            createdAt: existing?.createdAt ?? Date(),
            imageUploadData: imageUploadData ?? existing?.imageUploadData,
            imagePreviewData: imagePreviewData ?? existing?.imagePreviewData,
            imageMimeType: imageMimeType ?? existing?.imageMimeType,
            serverLogId: serverLogId ?? existing?.serverLogId
        )

        if let existingIndex {
            pendingSaveQueue[existingIndex] = item
        } else {
            pendingSaveQueue.append(item)
        }
        persistPendingSaveQueue()
        refreshRetryStateFromPendingQueue()
    }

    private func persistPendingSaveQueue() {
        if useSaveCoordinator {
            saveCoordinator.persistQueue(pendingSaveQueue)
            syncPendingQueueFromCoordinator()
            return
        }
        HomePendingSaveStore.saveQueue(pendingSaveQueue, defaults: defaults)
    }

    private func refreshRetryStateFromPendingQueue() {
        if useSaveCoordinator, let context = saveCoordinator.retryContext() {
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
        if useSaveCoordinator {
            saveCoordinator.markAttemptStarted(idempotencyKey: idempotencyKey)
            syncPendingQueueFromCoordinator()
            return
        }

        let key = idempotencyKey.uuidString.lowercased()
        guard let index = pendingSaveQueue.firstIndex(where: { $0.idempotencyKey == key }) else {
            return
        }

        pendingSaveQueue[index].attemptCount = (pendingSaveQueue[index].attemptCount ?? 0) + 1
        pendingSaveQueue[index].lastAttemptAt = Date()
        pendingSaveQueue[index].lastErrorMessage = nil
        persistPendingSaveQueue()
    }

    private func markPendingSaveFailed(idempotencyKey: UUID, message: String) {
        if useSaveCoordinator {
            saveCoordinator.markFailed(idempotencyKey: idempotencyKey, message: message)
            syncPendingQueueFromCoordinator(refreshRetryState: true)
            return
        }

        let key = idempotencyKey.uuidString.lowercased()
        guard let index = pendingSaveQueue.firstIndex(where: { $0.idempotencyKey == key }) else {
            refreshRetryStateFromPendingQueue()
            return
        }

        pendingSaveQueue[index].lastAttemptAt = Date()
        pendingSaveQueue[index].lastErrorMessage = message
        persistPendingSaveQueue()
        refreshRetryStateFromPendingQueue()
    }

    private func handlePendingSaveFailure(
        idempotencyKey: UUID,
        request: SaveLogRequest,
        error: Error,
        message: String
    ) async {
        let nonRetryable: Bool
        if useSaveCoordinator {
            nonRetryable = saveCoordinator.handleFailure(
                idempotencyKey: idempotencyKey,
                message: message,
                error: error
            )
            syncPendingQueueFromCoordinator(refreshRetryState: true)
        } else {
            nonRetryable = SaveErrorPolicy.isNonRetryable(error)
        }

        if !useSaveCoordinator, nonRetryable {
            removePendingSave(idempotencyKey: idempotencyKey.uuidString.lowercased())
            let failedDay = String(request.parsedLog.loggedAt.prefix(10))
            await refreshDayAfterMutation(failedDay, postNutritionNotification: false)
            return
        } else if !useSaveCoordinator {
            markPendingSaveFailed(idempotencyKey: idempotencyKey, message: message)
        }

        if nonRetryable {
            let failedDay = String(request.parsedLog.loggedAt.prefix(10))
            await refreshDayAfterMutation(failedDay, postNutritionNotification: false)
        }
    }

    private func markPendingSaveSucceeded(idempotencyKey: UUID, logId: String, preparedRequest: SaveLogRequest) {
        if useSaveCoordinator {
            saveCoordinator.markSucceeded(
                idempotencyKey: idempotencyKey,
                logId: logId,
                preparedRequest: preparedRequest,
                fingerprint: saveRequestFingerprint(preparedRequest)
            )
            syncPendingQueueFromCoordinator(refreshRetryState: true)
            return
        }

        let key = idempotencyKey.uuidString.lowercased()
        guard let index = pendingSaveQueue.firstIndex(where: { $0.idempotencyKey == key }) else {
            refreshRetryStateFromPendingQueue()
            return
        }
        pendingSaveQueue[index].request = preparedRequest
        pendingSaveQueue[index].fingerprint = saveRequestFingerprint(preparedRequest)
        pendingSaveQueue[index].serverLogId = logId
        pendingSaveQueue[index].lastErrorMessage = nil
        persistPendingSaveQueue()
        refreshRetryStateFromPendingQueue()
    }

    private func removePendingSave(idempotencyKey: String) {
        if useSaveCoordinator {
            saveCoordinator.removePendingSave(idempotencyKey: idempotencyKey)
            syncPendingQueueFromCoordinator(refreshRetryState: true)
            return
        }
        pendingSaveQueue.removeAll { $0.idempotencyKey == idempotencyKey }
        persistPendingSaveQueue()
        refreshRetryStateFromPendingQueue()
    }

    @discardableResult
    private func removePendingSaveQueueItems(forRowID rowID: UUID) -> Set<String> {
        if useSaveCoordinator {
            let removed = saveCoordinator.removePendingItems(forRowID: rowID)
            syncPendingQueueFromCoordinator(refreshRetryState: true)
            return removed
        }

        let removedKeys = Set(
            pendingSaveQueue
                .filter { $0.rowID == rowID }
                .map(\.idempotencyKey)
        )
        guard !removedKeys.isEmpty else { return [] }

        pendingSaveQueue.removeAll { $0.rowID == rowID }
        persistPendingSaveQueue()
        refreshRetryStateFromPendingQueue()
        return removedKeys
    }

    private func reconcilePendingSaveQueue(with logs: [DayLogEntry], for dateString: String) {
        if useSaveCoordinator {
            saveCoordinator.reconcilePendingQueue(with: logs, for: dateString)
            syncPendingQueueFromCoordinator(refreshRetryState: true)
            return
        }
        let serverLogIds = Set(logs.map(\.id))
        let beforeCount = pendingSaveQueue.count
        pendingSaveQueue.removeAll { item in
            item.dateString == dateString && item.serverLogId.map { serverLogIds.contains($0) } == true
        }
        if pendingSaveQueue.count != beforeCount {
            persistPendingSaveQueue()
            refreshRetryStateFromPendingQueue()
        }
    }

    private func saveRequestFingerprint(_ request: SaveLogRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(request) else {
            return UUID().uuidString
        }
        return data.base64EncodedString()
    }

    private func userFriendlySaveError(_ error: Error) -> String {
        guard let apiError = error as? APIClientError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        if isAuthTokenError(apiError) {
            return L10n.authSessionExpired
        }

        switch apiError {
        case let .server(_, payload):
            switch payload.code {
            case "IDEMPOTENCY_CONFLICT":
                return L10n.saveIdempotencyConflict
            case "INVALID_PARSE_REFERENCE":
                return L10n.saveInvalidParseReference
            case "MISSING_IDEMPOTENCY_KEY":
                return L10n.saveMissingIdempotency
            default:
                return payload.message
            }
        case .networkFailure(_):
            return L10n.saveNetworkFailure
        default:
            return apiError.errorDescription ?? L10n.saveFailure
        }
    }

    /// Produces a short, readable label from parsed food items for the home screen row.
    /// Example: "Chobani Complete 20g Protein Zero Added Sugar Mixed Berry..." → "Chobani Protein Drink"
    /// Full detail lives in the parsedItems and is shown in the details drawer.
    private func shortenedFoodLabel(items: [ParsedFoodItem], extractedText: String?) -> String {
        if items.isEmpty {
            let fallback = (extractedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? "Photo meal" : truncateLabel(fallback, maxWords: 4)
        }

        if items.count == 1 {
            return truncateLabel(items[0].name, maxWords: 4)
        }

        // Multiple items — take the first 3 words of each, join with ", "
        let shortened = items.prefix(3).map { truncateLabel($0.name, maxWords: 3) }
        let label = shortened.joined(separator: ", ")
        if items.count > 3 {
            return "\(label) + \(items.count - 3) more"
        }
        return label
    }

    /// Keeps only the first N words of a string. Strips noise words like "g", "oz", "added", "zero".
    private func truncateLabel(_ text: String, maxWords: Int) -> String {
        let noise: Set<String> = ["g", "oz", "ml", "mg", "added", "zero", "sugar", "free", "with", "no", "of"]
        let words = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)

        // Keep meaningful words only, up to maxWords
        var kept: [String] = []
        for word in words {
            // Skip pure numbers with units like "20g", "0g", "12oz"
            let lowered = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if lowered.isEmpty { continue }
            let isNumericUnit = lowered.allSatisfy({ $0.isNumber || $0 == "." }) || noise.contains(lowered)
            if isNumericUnit && !kept.isEmpty { continue } // allow first word even if numeric (e.g. "2% Milk")

            kept.append(word)
            if kept.count >= maxWords { break }
        }

        return kept.isEmpty ? text.prefix(30).trimmingCharacters(in: .whitespacesAndNewlines) : kept.joined(separator: " ")
    }

    private func userFriendlyParseError(_ error: Error) -> String {
        guard let apiError = error as? APIClientError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        if isAuthTokenError(apiError) {
            return L10n.authSessionExpired
        }

        switch apiError {
        case .networkFailure(_):
            return L10n.parseNetworkFailure
        case let .server(statusCode, _) where statusCode == 429:
            return L10n.parseRateLimited
        default:
            return apiError.errorDescription ?? L10n.parseFailure
        }
    }

    private func userFriendlyEscalationError(_ error: Error) -> (message: String, blockCode: String?) {
        guard let apiError = error as? APIClientError else {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return (message, nil)
        }

        if isAuthTokenError(apiError) {
            return (L10n.authSessionExpired, nil)
        }

        switch apiError {
        case let .server(_, payload):
            switch payload.code {
            case "ESCALATION_DISABLED":
                return (L10n.escalationDisabledNow, "ESCALATION_DISABLED")
            case "BUDGET_EXCEEDED":
                return (L10n.escalationBudgetExceeded, "BUDGET_EXCEEDED")
            case "ESCALATION_NOT_REQUIRED":
                return (L10n.escalationNoLongerNeeded, nil)
            case "INVALID_PARSE_REFERENCE":
                return (L10n.escalationInvalidParseReference, nil)
            default:
                return (payload.message, nil)
            }
        case .networkFailure(_):
            return (L10n.escalationNetworkFailure, nil)
        default:
            return (apiError.errorDescription ?? L10n.escalationFailure, nil)
        }
    }

    private func isAuthTokenError(_ apiError: APIClientError) -> Bool {
        switch apiError {
        case .missingAuthToken:
            return true
        case let .server(statusCode, payload):
            if statusCode == 401 || statusCode == 403 {
                return true
            }

            let code = payload.code.uppercased()
            if code == "UNAUTHORIZED" || code.contains("TOKEN") || code.contains("AUTH") {
                return true
            }

            let message = payload.message.lowercased()
            if message.contains("invalid token") ||
                message.contains("missing bearer token") ||
                message.contains("jwt") ||
                message.contains("unauthorized") {
                return true
            }
            return false
        default:
            return false
        }
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
        if useSaveCoordinator {
            let restored = saveCoordinator.loadRecoverableQueue(
                isRecoverable: isRecoverablePendingSaveItem
            )
            pendingSaveQueue = restored.queue
        } else {
            let loadedQueue = HomePendingSaveStore.loadQueue(defaults: defaults)
            pendingSaveQueue = loadedQueue.filter(isRecoverablePendingSaveItem)
            if pendingSaveQueue.count != loadedQueue.count {
                persistPendingSaveQueue()
            }
        }
        refreshRetryStateFromPendingQueue()
    }

    private func submitRestoredPendingSaveIfPossible() {
        guard appStore.isNetworkReachable, !isSaving, !isSubmittingRestoredPendingSaves else { return }

        Task { @MainActor in
            isSubmittingRestoredPendingSaves = true
            defer { isSubmittingRestoredPendingSaves = false }

            if useSaveCoordinator {
                let report = await saveCoordinator.flushAll(reason: .startup) { candidate in
                    await submitSave(
                        request: candidate.item.request,
                        idempotencyKey: candidate.idempotencyKey,
                        isRetry: true,
                        intent: .auto
                    )
                }
                syncPendingQueueFromCoordinator()
                guard report.attempted > 0 else { return }
                return
            }

            let validCandidates = legacyPendingSubmissionCandidates()
            guard !validCandidates.isEmpty else { return }
            for candidate in validCandidates {
                _ = await submitSave(
                    request: candidate.item.request,
                    idempotencyKey: candidate.idempotencyKey,
                    isRetry: true,
                    intent: .auto
                )
            }
        }
    }

    private func isRecoverablePendingSaveItem(_ item: PendingSaveQueueItem) -> Bool {
        if item.serverLogId != nil {
            return true
        }

        guard UUID(uuidString: item.idempotencyKey) != nil else {
            return false
        }

        let body = item.request.parsedLog
        let rawText = body.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawText.isEmpty {
            return true
        }

        let inputKind = normalizedInputKind(body.inputKind, fallback: "text")
        let imageRef = body.imageRef?.trimmingCharacters(in: .whitespacesAndNewlines)
        return inputKind == "image" &&
            ((imageRef?.isEmpty == false) || item.imageUploadData != nil || item.imagePreviewData != nil)
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

    private func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func roundOneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

}

#Preview {
    MainLoggingShellView()
        .environmentObject(AppStore())
}
