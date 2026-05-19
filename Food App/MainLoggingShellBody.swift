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
                // Floating glass card surfacing the most recent flagged meal.
                // Bottom padding clears the mic/camera dock that lives in the
                // outer `HomeTabShellView` ZStack (60pt buttons + 16pt dock
                // padding ≈ 92pt of room).
                RecentFlaggedMealCard(
                    logs: dayLogs?.logs ?? [],
                    contextKey: summaryDateString,
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
                guard !presentMindfulPauseIfNeeded(for: .text) else { return }
                if isKeyboardVisible {
                    dismissComposerKeyboard()
                } else {
                    focusComposerInputFromBackgroundTap()
                }
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
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isProgressChartsPresented) {
                HomeProgressScreen()
                    .environmentObject(appStore)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(24)
            }
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
                scheduleSecondaryHomePreloads()
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
            }
            .onChange(of: appStore.isSessionRestored) { _, ready in
                guard ready else { return }
                hydrateVisibleDayLogsFromDiskIfNeeded()
                bootstrapAuthenticatedHomeIfNeeded()
                scheduleSecondaryHomePreloads()
                autoPresentHomeTutorialIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    refreshVisibleDayOnForeground()
                case .background:
                    FoodBackgroundRefreshService.shared.scheduleAppRefresh()
                default:
                    break
                }
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
                    saveSuccessMessage = nil
                    presentCelebration(title: "Saved", subtitle: meal.name, style: .saved)
                }
                .environmentObject(appStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
            }) {
                CameraView(
                    onImageCaptured: { image in
                        isCustomCameraPresented = false
                        inputMode = .text
                        selectedCameraSource = nil
                        if isQuickCameraCaptureActive {
                            isQuickCameraCaptureActive = false
                        }
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
            .sheet(isPresented: $isCameraAnalysisSheetPresented, onDismiss: {
                cameraDrawerState = .idle
                cameraDrawerImage = nil
                cameraDrawerContextNote = ""
            }) {
                cameraAnalysisSheetContent
            }
            .overlay(alignment: .bottom) {
                if isVoiceOverlayPresented {
                    VoiceRecordingOverlay(
                        transcribedText: speechService.transcribedText,
                        isListening: speechService.isListening,
                        audioLevel: speechService.audioLevel,
                        phase: voiceOverlayPhase,
                        onCancel: {
                            cancelVoiceCapture()
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
            .overlay(alignment: .bottom) {
                if !isVoiceOverlayPresented {
                    bottomActionDock
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .homeCoachCardTutorialHost(
                isPresented: $isHomeTutorialPresented,
                step: $homeTutorialStep,
                onFocusComposer: {
                    focusComposerInputFromBackgroundTap()
                },
                onOpenCamera: {
                    NotificationCenter.default.post(name: .openCameraFromTabBar, object: nil)
                },
                onOpenProgress: {
                    isProgressChartsPresented = true
                },
                onFinish: {
                    finishHomeTutorial()
                }
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

    private var cameraAnalysisSheetContent: some View {
        CameraResultDrawerView(
            state: cameraDrawerState,
            parseResult: parseResult,
            contextNote: $cameraDrawerContextNote,
            onLogIt: { editedItems, editedTotals in
                handleDrawerLogIt(editedItems: editedItems, editedTotals: editedTotals)
            },
            onDiscard: {
                isCameraAnalysisSheetPresented = false
            },
            onRetry: {
                if let image = cameraDrawerImage {
                    cameraDrawerState = .analyzing(image)
                    Task { await parseAndUpdateDrawer(image, contextNote: cameraDrawerContextNote) }
                }
            }
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
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
