import SwiftUI

#if DEBUG
enum VisualQAMode {
    static let stateArgument = "--visual-qa-state"

    static var requestedStateID: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: stateArgument),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    static var isEnabled: Bool {
        requestedStateID != nil
    }
}

struct VisualQARootView: View {
    @EnvironmentObject private var appStore: AppStore
    let stateID: String

    var body: some View {
        Group {
            if let onboardingRoute {
                VisualQAOnboardingRouteView(route: onboardingRoute)
                    .environmentObject(appStore)
            } else {
                nonOnboardingView
            }
        }
        .preferredColorScheme(.light)
    }

    private var onboardingRoute: OnboardingRoute? {
        guard stateID.hasPrefix("onboarding/") else { return nil }
        let routeID = stateID
            .replacingOccurrences(of: "onboarding/", with: "")
            .split(separator: "/")
            .first
            .map(String.init)

        switch routeID {
        case "welcome": return .welcome
        case "goal": return .goal
        case "social-proof": return .socialProof
        case "experience": return .experience
        case "how-it-works": return .howItWorks
        case "challenge": return .challenge
        case "challenge-insight": return .challengeInsight
        case "age": return .age
        case "baseline": return .baseline
        case "activity": return .activity
        case "pace": return .pace
        case "preferences": return .preferencesOptional
        case "goal-validation": return .goalValidation
        case "account": return .account
        case "apple-health": return .permissions
        case "notifications": return .notificationsPermission
        case "ready": return .ready
        default: return nil
        }
    }

    @ViewBuilder
    private var nonOnboardingView: some View {
        switch stateID {
        case "home/default":
            MainLoggingShellView()
                .environmentObject(appStore)
        case "home/profile-bento/default":
            HomeProfileBentoScreen()
                .environmentObject(appStore)
        case "home/badges/default":
            BadgesTrophyCaseView(currentStreakDays: 15, autoLoadsRemoteProgress: false)
                .environmentObject(appStore)
        case "home/streak-drawer/default":
            HomeStreakDrawerView()
                .environmentObject(appStore)
        case "home/progress/default":
            HomeProgressScreen()
                .environmentObject(appStore)
        case "home/logging-tips/default":
            FoodLoggingTipsView(presentationStyle: .sheet(onClose: {}))
        case "home/mindful-pause/default":
            MindfulPauseSheet(
                onContinueLogging: {},
                onSkipForToday: {}
            )
        case "home/composer/empty":
            VisualQAHomeComposerStateView(kind: .empty)
        case "home/composer/text-typed":
            VisualQAHomeComposerStateView(kind: .textTyped)
        case "home/composer/parse-loading":
            VisualQAHomeComposerStateView(kind: .parseLoading)
        case "home/composer/parse-success-single":
            VisualQAHomeComposerStateView(kind: .parseSuccessSingle)
        case "home/composer/parse-success-multiple":
            VisualQAHomeComposerStateView(kind: .parseSuccessMultiple)
        case "home/composer/parse-error":
            VisualQAHomeComposerStateView(kind: .parseError)
        case "home/composer/save-loading":
            VisualQAHomeComposerStateView(kind: .saveLoading)
        case "home/composer/save-success":
            VisualQAHomeComposerStateView(kind: .saveSuccess)
        case "home/composer/save-error":
            VisualQAHomeComposerStateView(kind: .saveError)
        case "home/composer/offline":
            VisualQAHomeComposerStateView(kind: .offline)
        case "home/insight-card/default":
            VisualQAInsightCardStateView()
        case "home/voice/listening":
            VisualQABaseHomeBackdrop {
                VoiceRecordingOverlay(
                    transcribedText: "",
                    isListening: true,
                    audioLevel: 0.62,
                    phase: .listening,
                    onCancel: {},
                    onStop: {}
                )
            }
        case "home/voice/processing":
            VisualQABaseHomeBackdrop {
                VoiceRecordingOverlay(
                    transcribedText: "Greek yogurt with berries",
                    isListening: false,
                    audioLevel: 0.18,
                    phase: .handoff,
                    onCancel: {},
                    onStop: {}
                )
            }
        case "home/camera/permission-denied":
            CameraPermissionDeniedView(onDismiss: {})
        case "home/camera/review":
            CameraReviewOverlay(image: VisualQAFixtures.foodImage, onRetake: {}, onUsePhoto: {})
        case "home/camera-analysis/loading":
            VisualQADrawerShell {
                CameraResultDrawerView(
                    state: .analyzing(VisualQAFixtures.foodImage, nil),
                    contextNote: .constant(""),
                    onLogIt: { _, _ in },
                    onDiscard: {},
                    onRetry: {}
                )
            }
        case "home/camera-analysis/success":
            VisualQADrawerShell {
                CameraResultDrawerView(
                    state: .parsed(VisualQAFixtures.foodImage, VisualQAFixtures.foodItems, VisualQAFixtures.totals),
                    contextNote: .constant(""),
                    onLogIt: { _, _ in },
                    onDiscard: {},
                    onRetry: {}
                )
            }
        case "home/camera-analysis/error":
            VisualQADrawerShell {
                CameraResultDrawerView(
                    state: .error("We couldn't read enough from this photo. Try brighter light or move closer.", VisualQAFixtures.foodImage),
                    contextNote: .constant(""),
                    onLogIt: { _, _ in },
                    onDiscard: {},
                    onRetry: {}
                )
            }
        case "home/details-drawer/default":
            VisualQADrawerShell {
                MainLoggingRowCalorieDetailsSheet(
                    details: VisualQAFixtures.rowDetails,
                    isDeleteDisabled: false,
                    isDeleteConfirmationPresented: .constant(false),
                    isSaveMealEnabled: true,
                    onSaveMeal: {},
                    onDeleteTapped: {},
                    onConfirmDelete: {},
                    onCancelDelete: {},
                    onDone: {},
                    onItemQuantityChange: { _, _ in }
                )
            }
        case "home/details-drawer/delete-confirmation":
            VisualQADrawerShell {
                MainLoggingRowCalorieDetailsSheet(
                    details: VisualQAFixtures.rowDetails,
                    isDeleteDisabled: false,
                    isDeleteConfirmationPresented: .constant(true),
                    isSaveMealEnabled: true,
                    onSaveMeal: {},
                    onDeleteTapped: {},
                    onConfirmDelete: {},
                    onCancelDelete: {},
                    onDone: {},
                    onItemQuantityChange: { _, _ in }
                )
            }
        case "home/nutrition-summary/default":
            MainLoggingNutritionSummarySheet(totals: VisualQAFixtures.dayTotals, navigationTitle: "Today's Nutrition")
        case "home/calendar/default":
            VisualQACalendarStateView()
        case "home/badge-unlock/first-spark":
            StreakAchievementPopup(badge: VisualQAFixtures.badge(id: "first_spark"), onDismiss: {})
        case "home/badge-unlock/momentum-maker":
            StreakAchievementPopup(badge: VisualQAFixtures.badge(id: "momentum_maker"), onDismiss: {})
        case "home/badges/share-sheet":
            VisualQABadgesShareStateView()
                .environmentObject(appStore)
        case "profile/diet-editor/default":
            NavigationStack { DietEditorScreen() }
                .environmentObject(appStore)
                .environmentObject(ProfileDraftStore())
        case "profile/body-editor/default":
            NavigationStack { BodyEditorScreen() }
                .environmentObject(appStore)
                .environmentObject(ProfileDraftStore())
        case "profile/targets-editor/default":
            NavigationStack { TargetsEditorScreen() }
                .environmentObject(appStore)
                .environmentObject(ProfileDraftStore())
        case "profile/sign-out-confirmation":
            VisualQAConfirmationStateView(
                title: "Sign out?",
                message: "You can sign back in at any time. Unsaved changes on this device may be lost.",
                destructiveTitle: "Sign Out"
            )
        case "feedback/empty-validation":
            VisualQAFeedbackStateView(kind: .emptyValidation)
                .environmentObject(appStore)
        case "feedback/submitting":
            VisualQAFeedbackStateView(kind: .submitting)
                .environmentObject(appStore)
        case "feedback/success":
            VisualQAFeedbackStateView(kind: .success)
                .environmentObject(appStore)
        case "profile/legacy/default":
            HomeProfileScreen()
                .environmentObject(appStore)
        case "feedback/default":
            FeedbackView()
                .environmentObject(appStore)
        case "widget-guide/default":
            WidgetSetupGuideView(presentationStyle: .sheet(onClose: {}))
        default:
            VisualQAUnsupportedStateView(stateID: stateID)
        }
    }
}

private struct VisualQADrawerShell<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
    }
}

private struct VisualQABaseHomeBackdrop<Overlay: View>: View {
    @ViewBuilder let overlay: () -> Overlay

    var body: some View {
        ZStack {
            MainLoggingShellView()
            overlay()
        }
    }
}

private struct VisualQAHomeComposerStateView: View {
    enum Kind {
        case empty
        case textTyped
        case parseLoading
        case parseSuccessSingle
        case parseSuccessMultiple
        case parseError
        case saveLoading
        case saveSuccess
        case saveError
        case offline
    }

    let kind: Kind

    var body: some View {
        VStack(spacing: 0) {
            MainLoggingShellView()
                .allowsHitTesting(false)
                .overlay(alignment: .bottom) {
                    stateCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 28)
                }
        }
    }

    private var stateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(iconColor)
                    .frame(width: 34, height: 34)
                    .background(iconColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if showsSpinner {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if let sampleText {
                Text(sampleText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 24, y: 12)
    }

    private var title: String {
        switch kind {
        case .empty: return "Ready to log"
        case .textTyped: return "Text entered"
        case .parseLoading: return "Parsing meal"
        case .parseSuccessSingle: return "1 item detected"
        case .parseSuccessMultiple: return "3 items detected"
        case .parseError: return "Could not parse"
        case .saveLoading: return "Saving log"
        case .saveSuccess: return "Saved to today"
        case .saveError: return "Save failed"
        case .offline: return "You're offline"
        }
    }

    private var message: String {
        switch kind {
        case .empty: return "The composer is idle with no entered food."
        case .textTyped: return "User has typed a realistic meal and can parse it."
        case .parseLoading: return "Food database and AI route are still resolving nutrition."
        case .parseSuccessSingle: return "Nutrition is ready for review before saving."
        case .parseSuccessMultiple: return "Multiple detected foods are grouped into one meal."
        case .parseError: return "The app should offer retry and better input guidance."
        case .saveLoading: return "The row is locked while the save request is in flight."
        case .saveSuccess: return "Success feedback should stay visible long enough to read."
        case .saveError: return "The user needs a retry path without losing the parsed meal."
        case .offline: return "Network failure should be clear and recoverable."
        }
    }

    private var sampleText: String? {
        switch kind {
        case .empty: return nil
        case .textTyped, .parseLoading: return "Greek yogurt, blueberries, granola, honey"
        case .parseSuccessSingle: return "Greek yogurt bowl · 410 cal · P 28g · C 52g · F 9g"
        case .parseSuccessMultiple: return "Chicken rice bowl · avocado · side salad · 780 cal"
        case .parseError: return "A little bit of that thing from yesterday"
        case .saveLoading, .saveSuccess, .saveError: return "Turkey sandwich and apple · 640 cal"
        case .offline: return "Saved draft is preserved locally until the connection returns."
        }
    }

    private var icon: String {
        switch kind {
        case .empty, .textTyped: return "character.cursor.ibeam"
        case .parseLoading, .saveLoading: return "hourglass"
        case .parseSuccessSingle, .parseSuccessMultiple, .saveSuccess: return "checkmark.circle.fill"
        case .parseError, .saveError, .offline: return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .parseError, .saveError, .offline: return .red
        case .parseSuccessSingle, .parseSuccessMultiple, .saveSuccess: return .green
        default: return .orange
        }
    }

    private var showsSpinner: Bool {
        kind == .parseLoading || kind == .saveLoading
    }
}

private struct VisualQAInsightCardStateView: View {
    @State private var dismissed: Set<String> = []

    var body: some View {
        VisualQABaseHomeBackdrop {
            VStack {
                Spacer()
                RecentFlaggedMealCard(
                    logs: [VisualQAFixtures.flaggedLog],
                    contextKey: "visual-qa",
                    dismissedLogIds: $dismissed
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 88)
            }
        }
    }
}

private struct VisualQACalendarStateView: View {
    @State private var selectedDate = Date()

    var body: some View {
        MainLoggingCalendarSheet(selectedDate: $selectedDate, onToday: {})
    }
}

private struct VisualQABadgesShareStateView: View {
    @State private var showSheet = false

    var body: some View {
        BadgesTrophyCaseView(currentStreakDays: 15, autoLoadsRemoteProgress: false)
            .sheet(isPresented: $showSheet) {
                SharePreviewSheet()
            }
            .onAppear {
                showSheet = true
            }
    }
}

private struct SharePreviewSheet: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Share Badge")
                    .font(.system(size: 24, weight: .bold))
                Text("Momentum Maker: Earn 15/20")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                Button("Messages") {}
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

private struct VisualQAConfirmationStateView: View {
    let title: String
    let message: String
    let destructiveTitle: String

    var body: some View {
        HomeProfileScreen()
            .overlay {
                Color.black.opacity(0.24).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                    Text(message)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Button("Cancel") {}
                            .buttonStyle(.bordered)
                        Button(destructiveTitle, role: .destructive) {}
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .frame(maxWidth: 340)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 30, y: 16)
            }
    }
}

private struct VisualQAFeedbackStateView: View {
    enum Kind {
        case emptyValidation
        case submitting
        case success
    }

    let kind: Kind

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Feedback type", selection: .constant("bug")) {
                        Text("General").tag("general")
                        Text("Bug").tag("bug")
                        Text("Feature").tag("feature")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("What are you sending?")
                }

                Section {
                    TextEditor(text: .constant(kind == .emptyValidation ? "" : "The badge share sheet closes if I background the app mid-share."))
                        .frame(minHeight: 160)
                } header: {
                    Text("Your feedback")
                } footer: {
                    if kind == .emptyValidation {
                        Text("Message is required before sending.")
                            .foregroundStyle(.red)
                    } else {
                        Text("88 / 4000")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                    } label: {
                        HStack {
                            if kind == .submitting {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                            }
                            Text(kind == .submitting ? "Sending..." : "Send feedback")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(kind == .emptyValidation || kind == .submitting)
                } footer: {
                    if kind == .success {
                        Text("Thanks for the feedback. We've received your message.")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Thanks for the feedback", isPresented: .constant(kind == .success)) {
                Button("OK") {}
            } message: {
                Text("We've received your message. If something looks broken, we'll dig into it.")
            }
        }
    }
}

private enum VisualQAFixtures {
    static let totals = NutritionTotals(calories: 780, protein: 52, carbs: 82, fat: 24)
    static let dayTotals = NutritionTotals(calories: 1840, protein: 126, carbs: 201, fat: 58)

    static let foodItems: [ParsedFoodItem] = [
        ParsedFoodItem(
            name: "Grilled chicken",
            quantity: 1,
            unit: "serving",
            grams: 160,
            calories: 265,
            protein: 43,
            carbs: 0,
            fat: 7,
            nutritionSourceId: "visual-chicken",
            sourceFamily: "visual",
            matchConfidence: 0.94,
            amount: 1,
            unitNormalized: "serving",
            gramsPerUnit: 160
        ),
        ParsedFoodItem(
            name: "Rice bowl",
            quantity: 1.5,
            unit: "cups",
            grams: 240,
            calories: 310,
            protein: 7,
            carbs: 68,
            fat: 1,
            nutritionSourceId: "visual-rice",
            sourceFamily: "visual",
            matchConfidence: 0.91,
            amount: 1.5,
            unitNormalized: "cup",
            gramsPerUnit: 160
        ),
        ParsedFoodItem(
            name: "Avocado",
            quantity: 0.5,
            unit: "each",
            grams: 75,
            calories: 120,
            protein: 2,
            carbs: 6,
            fat: 11,
            nutritionSourceId: "visual-avocado",
            sourceFamily: "visual",
            matchConfidence: 0.88,
            amount: 0.5,
            unitNormalized: "each",
            gramsPerUnit: 150
        )
    ]

    static let rowDetails = RowCalorieDetails(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
        rowText: "Chicken rice bowl with avocado",
        displayName: "Chicken rice bowl",
        calories: 780,
        protein: 52,
        carbs: 82,
        fat: 24,
        parseConfidence: 0.92,
        itemConfidence: 0.91,
        primaryConfidence: 0.92,
        hasManualOverride: false,
        sourceLabel: "Food database",
        thoughtProcess: "Matched chicken, rice, and avocado separately, then combined portions into one meal total.",
        parsedItems: foodItems,
        manualEditedFields: [],
        manualOriginalSources: [],
        imagePreviewData: foodImage.pngData(),
        imageRef: nil,
        loggedAt: "2026-05-15T18:00:00Z",
        inputKind: "text"
    )

    static let flaggedLog = DayLogEntry(
        id: "visual-flagged-log",
        loggedAt: "2026-05-15T18:00:00Z",
        rawText: "Peanut sauce noodles",
        inputKind: "text",
        imageRef: nil,
        confidence: 0.91,
        totals: NutritionTotals(calories: 640, protein: 18, carbs: 88, fat: 22),
        items: [],
        dietaryFlags: [
            DietaryFlag(itemName: "Peanut sauce noodles", rule: "allergy", ruleKey: "peanuts", matchedToken: "peanut", severity: "critical")
        ]
    )

    static let foodImage: UIImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 900))
        return renderer.image { context in
            UIColor(red: 0.98, green: 0.90, blue: 0.76, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 900))
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 120, y: 120, width: 660, height: 660))
            UIColor(red: 0.86, green: 0.43, blue: 0.17, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 280, y: 250, width: 190, height: 160))
            UIColor(red: 0.18, green: 0.62, blue: 0.28, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 470, y: 300, width: 140, height: 110))
            UIColor(red: 0.95, green: 0.82, blue: 0.52, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 300, y: 450, width: 330, height: 180))
        }
    }()

    static func badge(id: String) -> EarnedBadge {
        let definition = BadgeCatalog.definitions.first { $0.id.contains(id) } ?? BadgeCatalog.definitions[0]
        return EarnedBadge(definition: definition)
    }
}

private struct VisualQAOnboardingRouteView: View {
    @StateObject private var flow = AppFlowCoordinator()
    let route: OnboardingRoute

    var body: some View {
        OnboardingView(flow: flow)
            .onAppear {
                flow.moveToOnboarding(route)
            }
    }
}

private struct VisualQAUnsupportedStateView: View {
    let stateID: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.orange)
            Text("Visual QA state not implemented")
                .font(.system(size: 20, weight: .bold))
            Text(stateID)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
#endif
