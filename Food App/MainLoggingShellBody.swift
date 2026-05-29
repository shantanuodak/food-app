import SwiftUI
import Foundation
import PhotosUI
import UIKit

extension MainLoggingShellView {
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
                VStack(spacing: 0) {
                    // Floating glass card surfacing the most recent flagged meal.
                    RecentFlaggedMealCard(
                        logs: dayLogs?.logs ?? [],
                        contextKey: summaryDateString,
                        dismissedLogIds: $dismissedInsightLogIds
                    )
                    .padding(.horizontal, 16)

                    Color.clear
                        .frame(height: bottomDockScrollClearance)
                        .allowsHitTesting(false)
                }
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
                handleComposerBackgroundTap()
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
            .sheet(isPresented: $isSavedMealsPresented) {
                SavedMealsScreen(presentationStyle: .sheet(onClose: {
                    isSavedMealsPresented = false
                }))
                .environmentObject(appStore)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isFoodStoryPresented) {
                HomeFoodStoryDrawerView(
                    anchorDate: selectedSummaryDate,
                    currentDayLogs: dayLogs,
                    cachedDayLogs: $dayCacheLogs,
                    imageStorageService: appStore.imageStorageService
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
                .onAppear {
                    prefetchAdjacentDays(around: selectedSummaryDate, count: 6)
                }
            }
            .sheet(isPresented: $isProgressChartsPresented) {
                HomeProgressScreen()
                    .environmentObject(appStore)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(24)
            }
            .modifier(
                MainLoggingTipsPromptModifier(
                    isLoggingTipsPresented: $isLoggingTipsPresented,
                    isLoggingTipsPromptPresented: $isLoggingTipsPromptPresented
                )
            )
            .modifier(
                MainLoggingRecipeImportPresentationModifier(
                    isPresented: $isRecipesPresented,
                    appStore: appStore
                )
            )
            .sheet(isPresented: $isStreakDrawerPresented) {
                HomeStreakDrawerView()
                    .environmentObject(appStore)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(24)
            }
            .sheet(isPresented: $isBadgesTrophyCasePresented) {
                BadgesTrophyCaseView(currentStreakDays: badgesTrophyCaseStreakDays)
                    .environmentObject(appStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(24)
            }
            .fullScreenCover(item: $triggeredBadgeAchievement) { badge in
                StreakAchievementPopup(badge: badge) {
                    triggeredBadgeAchievement = nil
                }
                .presentationBackground(.clear)
            }
            .padding()
            // 2026-05-24: subtle top→bottom darkening so the home shell
            // doesn't read as a flat OLED void in dark mode. Light mode
            // resolves to solid systemBackground (no visible gradient).
            // Must come AFTER `.padding()` so the gradient extends to
            // the screen edges instead of sitting inside the 16pt margin.
            .background(AppColor.shellBackground.ignoresSafeArea())
            .overlay(alignment: .top) {
                if let activeCelebration {
                    FoodAppCelebrationOverlay(celebration: activeCelebration)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(60)
                }
            }
            .onChange(of: rowTextSignature) { _, _ in
                if suppressDebouncedParseOnce {
                    suppressDebouncedParseOnce = false
                    return
                }
                if latestParseInputKind.hasPrefix("image") {
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
                scheduleSecondaryHomePreloads()
                syncHealthActivityForBadgesIfNeeded()
                if QuickCameraLaunchStore.consumeLaunchRequest() {
                    guard !presentMindfulPauseIfNeeded(for: .camera(.takePicture, isQuickCapture: true)) else { return }
                    isQuickCameraCaptureActive = true
                    handleCameraSourceSelection(.takePicture)
                }
                if QuickCameraLaunchStore.consumeCameraLaunchRequest() {
                    guard !presentMindfulPauseIfNeeded(for: .camera(.takePicture, isQuickCapture: false)) else { return }
                    handleCameraSourceSelection(.takePicture)
                }
                if QuickCameraLaunchStore.consumeVoiceLaunchRequest() {
                    guard !presentMindfulPauseIfNeeded(for: .voice) else { return }
                    handleVoiceModeTapped()
                }
                autoPresentHomeTutorialIfNeeded()
                evaluateHydrationGoalPromptIfNeeded()
            }
            .onChange(of: appStore.isSessionRestored) { _, ready in
                guard ready else { return }
                hydrateVisibleDayLogsFromDiskIfNeeded()
                bootstrapAuthenticatedHomeIfNeeded()
                scheduleSecondaryHomePreloads()
                syncHealthActivityForBadgesIfNeeded(force: true)
                autoPresentHomeTutorialIfNeeded()
                evaluateHydrationGoalPromptIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    restorePendingSaveContextIfNeeded()
                    submitRestoredPendingSaveIfPossible()
                    refreshVisibleDayOnForeground()
                    syncHealthActivityForBadgesIfNeeded()
                case .inactive:
                    flushPendingAutoSaveForSceneTransition()
                case .background:
                    flushPendingAutoSaveForSceneTransition()
                    FoodBackgroundRefreshService.shared.scheduleAppRefresh()
                default:
                    break
                }
            }
            .onChange(of: appStore.isHealthSyncEnabled) { _, enabled in
                guard enabled else { return }
                syncHealthActivityForBadgesIfNeeded(force: true)
            }
            .onChange(of: appStore.healthAuthorizationState) { _, state in
                guard state == .authorized else { return }
                syncHealthActivityForBadgesIfNeeded(force: true)
            }
            .onDisappear {
                debounceTask?.cancel()
                parseTask?.cancel()
                cancelAutoSaveTask()
                prefetchTask?.cancel()
                initialHomeBootstrapTask?.cancel()
                secondaryHomePreloadTask?.cancel()
                unresolvedRetryTask?.cancel()
                // Drop any pending PATCH tasks; inputRows state is cleared
                // on the next load anyway.
                for task in pendingPatchTasks.values { task.cancel() }
                pendingPatchTasks.removeAll()
                for task in pendingDeleteTasks.values { task.cancel() }
                pendingDeleteTasks.removeAll()
                for task in dateChangeDraftTasks.values { task.cancel() }
                dateChangeDraftTasks.removeAll()
                voiceHandoffTask?.cancel()
                voiceRevealTask?.cancel()
                celebrationDismissTask?.cancel()
                activeCelebration = nil
                clearParseSchedulerState()
                parseCoordinator.clearAll()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCameraFromTabBar)) { _ in
                // Tap on the dock camera button → straight to the custom camera
                // (no action sheet). The camera's bottom-left album icon
                // handles "from photo library" once the user is inside it.
                guard !presentMindfulPauseIfNeeded(for: .camera(.takePicture, isQuickCapture: false)) else { return }
                handleCameraSourceSelection(.takePicture)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openQuickCameraFromSystem)) { _ in
                guard !presentMindfulPauseIfNeeded(for: .camera(.takePicture, isQuickCapture: true)) else { return }
                isQuickCameraCaptureActive = true
                handleCameraSourceSelection(.takePicture)
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickCameraStatusChanged)) { notification in
                handleQuickCameraStatusNotification(notification)
            }
            .modifier(
                MainLoggingNotificationRoutingModifier(
                    inputMode: $inputMode,
                    isStreakDrawerPresented: $isStreakDrawerPresented,
                    isProfilePresented: $isProfilePresented,
                    onVoiceLoggingRequested: {
                        guard !presentMindfulPauseIfNeeded(for: .voice) else { return }
                        handleVoiceModeTapped()
                    },
                    onTextLoggingRequested: {
                        guard !presentMindfulPauseIfNeeded(for: .text) else { return }
                        inputMode = .text
                        NotificationCenter.default.post(name: .focusComposerInputFromBackgroundTap, object: nil)
                    }
                )
            )
            .onReceive(NotificationCenter.default.publisher(for: .openNutritionSummaryFromTabBar)) { _ in
                refreshNutritionStateForVisibleDay()
                isNutritionSummaryPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutritionProgressDidChange)) { notification in
                refreshNutritionStateAfterProgressChange(notification)
                refreshCurrentStreak(shouldDetectBadgeUnlock: true)
                appStore.preloadProfileDashboard(force: true)
                appStore.preloadProgressCharts(force: true, includeHealthSamples: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .savedMealDidLog)) { notification in
                handleSavedMealDidLog(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openBadgesFromStreakDrawer)) { notification in
                let days = notification.userInfo?["currentStreakDays"] as? Int
                badgesTrophyCaseStreakDays = days ?? currentFoodLogStreak ?? 0
                isStreakDrawerPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isBadgesTrophyCasePresented = true
                }
            }
            .sheet(isPresented: $isDetailsDrawerPresented) {
                detailsDrawer
            }
            .sheet(item: $saveMealDraft) { presentation in
                SaveMealSheet(draft: presentation.request) { meal in
                    if let sourceRowID = presentation.sourceRowID {
                        markRowAsSavedMeal(rowID: sourceRowID, meal: meal)
                    }
                    saveSuccessMessage = nil
                    presentCelebration(title: "Saved", subtitle: meal.name, style: .saved)
                }
                .environmentObject(appStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $hydrationAmountPrompt) { prompt in
                HydrationAmountPromptSheet(
                    prompt: prompt,
                    onSelect: { option in
                        confirmHydrationAmount(prompt: prompt, option: option)
                    },
                    onCancel: {
                        hydrationAmountPrompt = nil
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppDrawerSurface.gradient)
            }
            .sheet(isPresented: $isHydrationGoalPromptPresented) {
                HydrationGoalPromptSheet(
                    isSaving: isSavingHydrationGoal,
                    onSelect: { goalMl in
                        saveHydrationGoal(goalMl)
                    },
                    onSkip: {
                        defaults.set(true, forKey: hydrationGoalPromptDismissedKey)
                        isHydrationGoalPromptPresented = false
                        scheduleBadgeCelebrationCheckAfterHydrationSave(delayNanoseconds: 500_000_000)
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppDrawerSurface.gradient)
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
                        if let action = pendingMindfulPauseAction {
                            pendingMindfulPauseAction = nil
                            performMindfulPauseAction(action)
                        }
                    },
                    onSkipForToday: {
                        MindfulPauseGate.markShown()
                        pendingMindfulPauseAction = nil
                        isMindfulPausePresented = false
                    }
                )
            }
            .fullScreenCover(isPresented: $isCustomCameraPresented, onDismiss: {
                isQuickCameraCaptureActive = false
                // Always reset drawer state on cover dismissal — the
                // overlay below lives inside the cover, so when the cover
                // goes away the drawer state needs to follow.
                cameraDrawerState = .idle
                cameraDrawerImage = nil
                cameraDrawerContextNote = ""
                isCameraAnalysisSheetPresentedOverCover = false
            }) {
                // V3.1 hotfix v6 (2026-05-20): the analysis drawer is now
                // an inline ZStack overlay inside the camera fullScreenCover
                // — NOT a .sheet anymore. Real-device runs of v2-v5 surfaced
                // this console warning on every "Use Photo" tap:
                //
                //   "Attempt to present <PresentationHostingController> on
                //   <PresentationHostingController> whose view is not in
                //   the window hierarchy."
                //
                // iOS refuses to present a sheet from a hosting controller
                // whose view it doesn't yet consider in the window
                // hierarchy. The cover content is in that state briefly
                // after the binding flips, and iOS queues the sheet for a
                // retry that lands seconds later — which is exactly the
                // perceived lag. The simulator's hierarchy check is
                // looser, so the bug only manifested on device. Inline
                // ZStack overlay has no hosting controller and no window
                // hierarchy check; it animates in via a SwiftUI transition
                // with no modal machinery in the way.
                ZStack {
                    CameraView(
                        onImageCaptured: { image, prefetchedBarcode in
                            inputMode = .text
                            selectedCameraSource = nil
                            if isQuickCameraCaptureActive {
                                isQuickCameraCaptureActive = false
                            }
                            cameraDrawerImage = image
                            // Pass nil image so the drawer renders with a
                            // gray placeholder while a thumbnail is being
                            // prepared off the main thread (12-48MP HEIC
                            // decode would otherwise block this render
                            // pass for hundreds of ms on real devices).
                            //
                            // P0 fix (2026-05-20): if the live viewfinder
                            // already detected a barcode, set the lane
                            // hint immediately so the drawer copy says
                            // "Scanning barcode…" from frame zero instead
                            // of waiting for ImageVisionPipeline to
                            // re-detect (which often timed out → showed
                            // generic "Analyzing your meal" instead).
                            let immediateHint: AnalysisLaneHint? = prefetchedBarcode != nil ? .barcode : nil
                            cameraDrawerState = .analyzing(nil, immediateHint)
                            // Flip the overlay flag — triggers the ZStack
                            // transition below.
                            withAnimation(.easeOut(duration: 0.28)) {
                                isCameraAnalysisSheetPresentedOverCover = true
                            }
                            // Heavy work scheduled AFTER the overlay flag.
                            // Hand the snapshotted live barcode through so
                            // parseAndUpdateDrawer can skip the Vision
                            // re-detection step entirely if present.
                            Task { await parseAndUpdateDrawer(image, prefetchedBarcode: prefetchedBarcode) }
                            Task.detached(priority: .userInitiated) {
                                let thumbnail = await image.byPreparingThumbnail(ofSize: CGSize(width: 1024, height: 1024))
                                await MainActor.run {
                                    if case .analyzing(_, let hint) = cameraDrawerState {
                                        cameraDrawerState = .analyzing(thumbnail ?? image, hint)
                                    }
                                }
                            }
                        },
                        onOpenPhotoLibrary: {
                            // After camera dismisses, open photo library
                            isCustomCameraPresented = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                handleCameraSourceSelection(.photo)
                            }
                        }
                    )
                    .ignoresSafeArea()

                    if isCameraAnalysisSheetPresentedOverCover {
                        cameraAnalysisOverlayContent
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(10)
                    }
                }
            }
            .modifier(QuickCameraPromptDialogModifier(
                prompt: $quickCameraPrompt,
                onLog: { pendingLog in
                    Task {
                        await QuickCameraNotificationActionHandler.logPendingEntry(id: pendingLog.id)
                        refreshDaySummary()
                        refreshDayLogs()
                    }
                },
                onRetake: { pendingLog in
                    QuickCameraPendingLogStore.remove(id: pendingLog.id)
                    QuickCameraLaunchStore.requestLaunch()
                },
                onDiscard: { pendingLog in
                    QuickCameraPendingLogStore.remove(id: pendingLog.id)
                }
            ))
            .sheet(item: $selectedRowDetails) { details in
                rowCalorieDetailsSheet(details)
            }
            // V3.1 hotfix v2 (2026-05-20): this sibling sheet is now ONLY
            // used by the photo-library path (handlePickedImage). The camera
            // capture path uses a separate sheet nested inside the camera
            // fullScreenCover (see above) — that avoids the cover→sheet
            // serialization lag the user reported (4-5s of frozen camera
            // review before the drawer slid up). Two state flags keep them
            // from firing each other.
            .sheet(isPresented: $isCameraAnalysisSheetPresented, onDismiss: {
                cameraDrawerState = .idle
                cameraDrawerImage = nil
                cameraDrawerContextNote = ""
            }) {
                cameraAnalysisSheetContent
            }
            .overlay(alignment: .bottom) {
                voiceRecordingOverlayContent
            }
            .overlay(alignment: .bottom) {
                if !isVoiceOverlayPresented {
                    bottomActionDock
                        // Lift the dock above the recipes sheet peek
                        // (.height(88)) so the icons aren't covered.
                        // Skip the lift while the keyboard is up — the
                        // sheet auto-dismisses then and the dock can sit
                        // right above the keyboard.
                        .padding(.bottom, isKeyboardVisible ? 0 : 56)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .modifier(
                HomeRecipesDrawerSheetModifier(
                    isKeyboardVisible: isKeyboardVisible,
                    isVoiceOverlayPresented: isVoiceOverlayPresented,
                    isOtherModalPresented: isRecipesDrawerSuppressed,
                    appStore: appStore
                )
            )
            .modifier(
                MainLoggingTutorialModifier(
                    isHomeTutorialPresented: $isHomeTutorialPresented,
                    homeTutorialStep: $homeTutorialStep,
                    isDaySwipeTutorialPresented: $isDaySwipeTutorialPresented,
                    onFinishHomeTutorial: { finishHomeTutorial() },
                    onFinishDaySwipeTutorial: { finishDaySwipeTutorial() },
                    onDaySwipeShift: { days in shiftSelectedSummaryDate(byDays: days) }
                )
            )
            .animation(.easeInOut(duration: 0.25), value: isVoiceOverlayPresented)
            .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .replayHomeTutorialFromAdmin)) { _ in
                isProfilePresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    startHomeTutorialDebug()
                }
            }
            .onChange(of: speechService.isListening) { wasListening, isNowListening in
                guard wasListening && !isNowListening && isVoiceOverlayPresented else { return }
                guard !voiceCaptureCancelRequested else {
                    voiceCaptureCancelRequested = false
                    return
                }
                completeVoiceCapture(with: speechService.transcribedText)
            }
            .onChange(of: speechService.audioLevel) { _, newLevel in
                guard isVoiceOverlayPresented else { return }
                handleVoiceHaptic(level: newLevel)
            }
            .onChange(of: speechService.error) { _, newError in
                guard let newError else { return }
                parseError = newError
                cancelVoiceCapture()
            }
        }
    }

    /// Sheet-flavored content used by the photo-library path. Has presentation
    /// modifiers so iOS gives it sheet chrome (drag indicator, detents,
    /// rounded corners).
    private var cameraAnalysisSheetContent: some View {
        cameraAnalysisDrawerView
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
    }

    /// V3.1 hotfix v6 (2026-05-20): inline-overlay-flavored content used by
    /// the camera-capture path inside the fullScreenCover. No presentation
    /// modifiers (would do nothing in a ZStack) — we paint the sheet-like
    /// chrome manually: background fill, rounded top corners, drag-handle
    /// strip, top safe-area inset so the user still sees a sliver of the
    /// camera review above the drawer. Visually matches the .sheet styling
    /// the user was getting before, but without iOS modal presentation.
    ///
    /// v6.1 fix (2026-05-20): drawer card now claims full remaining height
    /// (maxHeight: .infinity) so it reaches the bottom of the screen and
    /// the inner ScrollView gets the room it needs. Previous version sized
    /// to fit the content, which made the drawer look "half open".
    @ViewBuilder
    private var cameraAnalysisOverlayContent: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top + 8, 56)
            VStack(spacing: 0) {
                // Top inset — the camera review behind this strip stays
                // visible, matching how .presentationDetents([.large])
                // used to look. Tappable to dismiss? Not yet — keep it
                // simple, the X button inside the drawer handles dismiss.
                Spacer().frame(height: topInset)

                // The drawer card itself. Fills all remaining vertical
                // space down to the screen bottom (we ignore the bottom
                // safe area so the card extends edge-to-edge).
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 36, height: 5)
                        .padding(.top, 6)
                        .padding(.bottom, 4)

                    cameraAnalysisDrawerView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 24,
                        style: .continuous
                    )
                    .fill(AppDrawerSurface.gradient)
                    .ignoresSafeArea(edges: .bottom)
                )
            }
        }
    }

    func flushPendingAutoSaveForSceneTransition() {
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "FoodLogAutosaveFlush") {}
        Task { @MainActor in
            defer {
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }
            await flushPendingAutoSaveIfEligible()
        }
    }

    /// Voice recording overlay — extracted into its own computed property so
    /// the type-checker on the main body doesn't time out. Driven entirely
    /// by `isVoiceOverlayPresented` and the speech service.
    @ViewBuilder
    var voiceRecordingOverlayContent: some View {
        if isVoiceOverlayPresented {
            VoiceRecordingOverlay(
                transcribedText: speechService.transcribedText,
                isListening: speechService.isListening,
                audioLevel: speechService.audioLevel,
                phase: voiceOverlayPhase,
                onCancel: {
                    cancelVoiceCapture()
                },
                onStop: {
                    // stopListening() ends the audio capture but lets the
                    // recognition task finalize so we get the final
                    // transcript. The .onChange listener on
                    // speechService.isListening picks up the transition and
                    // calls completeVoiceCapture automatically — same code
                    // path as the natural silence-timeout commit.
                    speechService.stopListening()
                },
                onSilenceTimeout: {
                    cancelVoiceCapture()
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
            .padding(.horizontal, -16)
            .padding(.bottom, -24)
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    /// Shared body for both presentation styles. Kept identical so the
    /// .sheet path and the inline-overlay path render the same UI.
    private var cameraAnalysisDrawerView: some View {
        CameraResultDrawerView(
            state: cameraDrawerState,
            parseResult: parseResult,
            loggedAt: draftLoggedAt ??
                HomeLoggingDateUtils.date(fromLoggedAt: parseResult?.loggedAt) ??
                draftTimestampForSelectedDate(),
            mealTag: draftMealTag,
            contextNote: $cameraDrawerContextNote,
            onLogIt: { editedItems, editedTotals in
                handleDrawerLogIt(editedItems: editedItems, editedTotals: editedTotals)
            },
            onDiscard: {
                // Two possible presenters depending on entry point — set
                // whichever is currently true to false. Setting both is
                // safe; the inactive one is a no-op.
                //   - Camera capture: inline overlay inside the cover.
                //     Dismissing isCustomCameraPresented tears down both
                //     the cover and the overlay (the cover's onDismiss
                //     resets the overlay flag).
                //   - Photo library: sibling sheet on home view.
                isCustomCameraPresented = false
                isCameraAnalysisSheetPresented = false
            },
            onRetry: {
                if let image = cameraDrawerImage {
                    cameraDrawerState = .analyzing(image, nil)
                    Task { await parseAndUpdateDrawer(image, contextNote: cameraDrawerContextNote) }
                }
            },
            onMealTagChange: { tag in
                draftMealTag = tag
            },
            onLoggedAtChange: { date in
                draftLoggedAt = min(date, Date())
            }
        )
    }
}

private struct MainLoggingRecipeImportPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let appStore: AppStore

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    RecipesScreen()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    AppHaptics.lightImpact()
                                    isPresented = false
                                }
                            }
                        }
                }
                .environmentObject(appStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
            .onReceive(NotificationCenter.default.publisher(for: .recipeImportPendingURLDidChange)) { _ in
                guard appStore.isOnboardingComplete else { return }
                isPresented = true
            }
    }
}

private struct MainLoggingNotificationRoutingModifier: ViewModifier {
    @Binding var inputMode: HomeInputMode
    @Binding var isStreakDrawerPresented: Bool
    @Binding var isProfilePresented: Bool
    let onVoiceLoggingRequested: () -> Void
    let onTextLoggingRequested: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openVoiceFromTabBar)) { _ in
                onVoiceLoggingRequested()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openTextLoggerFromNotification)) { _ in
                onTextLoggingRequested()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openStreaksFromNotification)) { _ in
                isStreakDrawerPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openRemindersFromNotification)) { _ in
                isProfilePresented = true
            }
    }
}

/// Hosts the home tutorial and the day-swipe tutorial overlays, plus the
/// notification listener that drives the actual day shift when the user
/// performs the swipe inside the day-swipe overlay (Items 1, 2, 14).
/// Extracted from the shell body for the same SwiftUI type-checker reason
/// as `MainLoggingTipsPromptModifier`.
private struct MainLoggingTutorialModifier: ViewModifier {
    @Binding var isHomeTutorialPresented: Bool
    @Binding var homeTutorialStep: HomeCoachCardTutorialStep
    @Binding var isDaySwipeTutorialPresented: Bool
    let onFinishHomeTutorial: () -> Void
    let onFinishDaySwipeTutorial: () -> Void
    let onDaySwipeShift: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .homeCoachCardTutorialHost(
                isPresented: $isHomeTutorialPresented,
                step: $homeTutorialStep,
                onFinish: onFinishHomeTutorial
            )
            .daySwipeTutorialHost(
                isPresented: $isDaySwipeTutorialPresented,
                onDismiss: onFinishDaySwipeTutorial
            )
            .onReceive(NotificationCenter.default.publisher(for: .daySwipeTutorialDidAcknowledge)) { notification in
                let direction = (notification.object as? [String: String])?["direction"] ?? ""
                if direction == "right" {
                    onDaySwipeShift(-1)
                } else if direction == "left" {
                    onDaySwipeShift(1)
                }
            }
    }
}

/// Hosts both the full logging-tips sheet and the new compact prompt
/// (Item 4, 2026-05-22). Extracted from the main shell body so SwiftUI's
/// type checker doesn't choke on the deep modifier chain.
private struct MainLoggingTipsPromptModifier: ViewModifier {
    @Binding var isLoggingTipsPresented: Bool
    @Binding var isLoggingTipsPromptPresented: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isLoggingTipsPresented) {
                FoodLoggingTipsView(
                    presentationStyle: .sheet(onClose: {
                        isLoggingTipsPresented = false
                    })
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(24)
            }
            .sheet(isPresented: $isLoggingTipsPromptPresented) {
                LoggingTipsPromptSheet(
                    onShowTips: {
                        isLoggingTipsPromptPresented = false
                        // Defer slightly so the dismiss completes before the
                        // next sheet presents — iOS doesn't enjoy stacked
                        // sheet flips in the same runloop turn.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            isLoggingTipsPresented = true
                        }
                    },
                    onSkip: {
                        LoggingTipsPromptSheet.skipForCooldown()
                        isLoggingTipsPromptPresented = false
                    }
                )
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
                .presentationBackground(AppDrawerSurface.gradient)
            }
    }
}
