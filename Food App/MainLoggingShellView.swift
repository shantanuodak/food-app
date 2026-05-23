import SwiftUI
import Foundation
import PhotosUI
import UIKit

struct SaveMealDraftPresentation: Identifiable {
    let id = UUID()
    let request: SaveLogRequest
}

struct MainLoggingShellView: View {
    @EnvironmentObject var appStore: AppStore
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase

    @StateObject var speechService = SpeechRecognitionService()
    @StateObject var saveCoordinator = SaveCoordinator()
    @StateObject var parseCoordinator = ParseCoordinator()
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
    @State var activeCelebration: FoodAppCelebration?
    @State var celebrationDismissTask: Task<Void, Never>?
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
    @State var pendingMindfulPauseAction: MindfulPauseAction?
    /// In-memory cache for adjacent days — keyed by "yyyy-MM-dd" date string.
    @State var dayCacheSummary: [String: DaySummaryResponse] = [:]
    @State var dayCacheLogs: [String: DayLogsResponse] = [:]
    @State var prefetchTask: Task<Void, Never>?
    @State var initialHomeBootstrapTask: Task<Void, Never>?
    @State var secondaryHomePreloadTask: Task<Void, Never>?
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
    @State var saveMealDraft: SaveMealDraftPresentation?
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
    @State var isProgressChartsPresented = false
    @State var isSavedMealsPresented = false
    @State var isLoggingTipsPresented = false
    /// Bottom sheet popup that nudges the user toward Logging Tips when a
    /// fresh entry parses with low confidence. Fires at most once per
    /// session per vague row; honors a 24-hour Skip cooldown.
    @State var isLoggingTipsPromptPresented = false
    /// Per-session set of row IDs we've already prompted, so re-parses
    /// don't re-trigger the popup for the same row.
    @State var promptedTipsRowIDs: Set<UUID> = []
    @State var isHomeTutorialPresented = false
    @State var hasEvaluatedAutoHomeTutorialPresentation = false
    @State var homeTutorialStep: HomeCoachCardTutorialStep = .composer
    /// Day-swipe interactive overlay (Items 2 & 14). Shown one time only,
    /// after the home tutorial finishes naturally (via Done — not Skip).
    /// Teaches the left/right day-swipe gesture by asking the user to
    /// perform it themselves.
    @State var isDaySwipeTutorialPresented = false
    @State var currentFoodLogStreak: Int?
    @State var isLoadingFoodLogStreak = false
    @State var isStreakDrawerPresented = false
    @State var isBadgesTrophyCasePresented = false
    @State var badgesTrophyCaseStreakDays = 0
    @State var triggeredBadgeAchievement: EarnedBadge?
    @State var badgeCelebrationCheckTask: Task<Void, Never>?
    @State var lastBadgeCelebrationCheckAt: Date?
    @State var isKeyboardVisible = false
    @State var isSyncInfoPresented = false
    /// Slide direction for day transitions: negative = slide left (going forward), positive = slide right (going back)
    @State var dayTransitionOffset: CGFloat = 0
    /// Locks the swipe direction once determined — prevents fighting with ScrollView vertical scroll
    @State var swipeAxis: SwipeAxis = .undecided
    @State var isCustomCameraPresented = false
    @State var isQuickCameraCaptureActive = false
    @State var quickCameraPrompt: QuickCameraPendingLog?
    @State var cameraDrawerState: CameraDrawerState = .idle
    @State var cameraDrawerImage: UIImage?
    @State var cameraDrawerContextNote: String = ""
    @State var isCameraAnalysisSheetPresented = false
    /// V3.1 hotfix v2 (2026-05-20): separate flag for the camera-capture
    /// path, which presents the analysis drawer as a sheet NESTED inside
    /// the camera fullScreenCover (so it can slide up without waiting for
    /// the cover to dismiss). The photo-library path still uses
    /// `isCameraAnalysisSheetPresented` (sibling sheet on the home view)
    /// because there's no cover in play there. Keeping them separate keeps
    /// the two sheet modifiers from racing each other.
    @State var isCameraAnalysisSheetPresentedOverCover = false

    @State var autoSavedParseIDs: Set<String> = []
    let homeTutorialShownKey = "home.first_run_tutorial.shown.v1"
    let autoSaveDelayNs: UInt64 = 1_500_000_000
    let saveAttemptTelemetry = SaveAttemptTelemetry.shared

    var defaults: UserDefaults { .standard }

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

enum FoodAppCelebrationStyle {
    case saved
    case logged
    case synced

    var icon: String {
        switch self {
        case .saved:
            return "checkmark"
        case .logged:
            return "fork.knife"
        case .synced:
            return "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .saved:
            return Color(red: 0.902, green: 0.361, blue: 0.102)
        case .logged:
            return Color(red: 0.845, green: 0.318, blue: 0.082)
        case .synced:
            return Color(red: 0.165, green: 0.557, blue: 0.384)
        }
    }
}

struct FoodAppCelebration: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let style: FoodAppCelebrationStyle
}

struct FoodAppCelebrationOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let celebration: FoodAppCelebration

    @State private var messageVisible = false
    @State private var confettiDropped = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                confettiLayer
            }

            messageCard
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.18)) {
                    messageVisible = true
                }
            } else {
                withAnimation(.spring(response: 0.44, dampingFraction: 0.72)) {
                    messageVisible = true
                }
                confettiDropped = true
            }
        }
    }

    private var messageCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                celebration.style.tint.opacity(0.30),
                                Color(red: 1.0, green: 0.73, blue: 0.32).opacity(0.15),
                                .clear
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 72
                        )
                    )
                    .frame(width: 150, height: 150)
                    .blur(radius: 4)

                Circle()
                    .fill(.white.opacity(0.94))
                    .frame(width: 76, height: 76)
                    .shadow(color: celebration.style.tint.opacity(0.24), radius: 22, y: 10)

                Circle()
                    .fill(celebration.style.tint)
                    .frame(width: 54, height: 54)

                Image(systemName: celebration.style.icon)
                    .font(.system(size: 23, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(height: 112)

            Text(celebration.title)
                .font(OnboardingTypography.instrumentSerif(style: .regular, size: 72))
                .foregroundStyle(Color(red: 0.129, green: 0.145, blue: 0.161))
                .minimumScaleFactor(0.82)
                .shadow(color: .white.opacity(0.95), radius: 12, y: 2)
                .shadow(color: celebration.style.tint.opacity(0.18), radius: 18, y: 10)

            if let subtitle = celebration.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 0.525, green: 0.557, blue: 0.588))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.72), in: Capsule())
                    .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
            }
        }
        .frame(maxWidth: 340)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RadialGradient(
                colors: [
                    Color.white.opacity(0.78),
                    Color.white.opacity(0.32),
                    .clear
                ],
                center: .center,
                startRadius: 30,
                endRadius: 210
            )
            .blur(radius: 2)
        )
        .scaleEffect(messageVisible ? 1 : 0.88)
        .opacity(messageVisible ? 1 : 0)
    }

    private var confettiLayer: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ForEach(0..<54, id: \.self) { index in
                    confettiPiece(index)
                        .frame(width: confettiWidth(index), height: confettiHeight(index))
                        .rotationEffect(.degrees(confettiDropped ? Double((index * 41) % 220 - 110) : Double((index * 13) % 44)))
                        .offset(
                            x: confettiX(index, width: proxy.size.width),
                            y: confettiDropped ? confettiY(index) : -140
                        )
                        .opacity(confettiDropped ? 1 : 0)
                        .animation(
                            .interpolatingSpring(stiffness: 58, damping: 8)
                                .delay(Double(index % 12) * 0.024),
                            value: confettiDropped
                        )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .ignoresSafeArea()
    }

    private var accessibilityLabel: Text {
        if let subtitle = celebration.subtitle, !subtitle.isEmpty {
            return Text("\(celebration.title). \(subtitle)")
        }
        return Text(celebration.title)
    }

    private func confettiX(_ index: Int, width: CGFloat) -> CGFloat {
        let usableWidth = max(width + 96, 1)
        let raw = CGFloat((index * 53 + 29) % Int(usableWidth))
        return raw - width / 2 - 48
    }

    private func confettiY(_ index: Int) -> CGFloat {
        CGFloat(120 + (index * 47) % 620)
    }

    private func confettiColor(_ index: Int) -> Color {
        let palette: [Color] = [
            celebration.style.tint,
            Color(red: 1.0, green: 0.645, blue: 0.196),
            Color(red: 0.984, green: 0.251, blue: 0.431),
            Color(red: 0.439, green: 0.392, blue: 0.941),
            Color(red: 0.114, green: 0.722, blue: 0.533),
            Color(red: 0.192, green: 0.600, blue: 0.980),
            Color(red: 0.976, green: 0.800, blue: 0.376)
        ]
        return palette[index % palette.count]
    }

    private func confettiWidth(_ index: Int) -> CGFloat {
        CGFloat(5 + (index % 4) * 3)
    }

    private func confettiHeight(_ index: Int) -> CGFloat {
        index % 5 == 0 ? confettiWidth(index) : CGFloat(10 + (index % 4) * 5)
    }

    @ViewBuilder
    private func confettiPiece(_ index: Int) -> some View {
        if index % 5 == 0 {
            Circle()
                .fill(confettiColor(index))
        } else if index % 7 == 0 {
            Capsule(style: .continuous)
                .fill(confettiColor(index))
        } else {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(confettiColor(index))
        }
    }
}

extension MainLoggingShellView {
    @MainActor
    func presentCelebration(title: String, subtitle: String? = nil, style: FoodAppCelebrationStyle = .saved) {
        celebrationDismissTask?.cancel()
        let trimmedSubtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let celebration = FoodAppCelebration(
            title: title,
            subtitle: trimmedSubtitle?.isEmpty == true ? nil : trimmedSubtitle,
            style: style
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            activeCelebration = celebration
        }

        celebrationDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_850_000_000)
            guard !Task.isCancelled, activeCelebration?.id == celebration.id else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                activeCelebration = nil
            }
        }
    }

    func celebrationSubtitle(from rawText: String) -> String? {
        let trimmed = rawText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 34 {
            return trimmed
        }
        let prefix = trimmed.prefix(31)
        return "\(prefix)…"
    }
}

#Preview {
    MainLoggingShellView()
        .environmentObject(AppStore())
}
