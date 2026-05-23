import SwiftUI
import UIKit

enum HomeCoachCardTutorialStep: Equatable {
    case composer
    case camera
    case progress
}

private struct HomeCoachCardTutorialHostModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var step: HomeCoachCardTutorialStep
    let onFinish: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                HomeCoachCardTutorialOverlay(
                    isPresented: $isPresented,
                    step: $step,
                    onFinish: onFinish
                )
                .zIndex(200)
            }
        }
    }
}

extension View {
    func homeCoachCardTutorialHost(
        isPresented: Binding<Bool>,
        step: Binding<HomeCoachCardTutorialStep>,
        onFinish: @escaping () -> Void
    ) -> some View {
        modifier(
            HomeCoachCardTutorialHostModifier(
                isPresented: isPresented,
                step: step,
                onFinish: onFinish
            )
        )
    }
}

extension MainLoggingShellView {
    func autoPresentHomeTutorialIfNeeded() {
        guard !hasEvaluatedAutoHomeTutorialPresentation else { return }
        hasEvaluatedAutoHomeTutorialPresentation = true

        guard appStore.isOnboardingComplete else { return }
        guard !UserDefaults.standard.bool(forKey: homeTutorialShownKey) else { return }
        guard !isHomeTutorialPresented else { return }
        guard selectedCameraSource == nil, !isQuickCameraCaptureActive, !isVoiceOverlayPresented else { return }

        UserDefaults.standard.set(true, forKey: homeTutorialShownKey)
        startHomeTutorialDebug()
    }

    @ViewBuilder
    var homeTutorialDebugButton: some View {
        if !isHomeTutorialPresented {
            Button {
                startHomeTutorialDebug()
            } label: {
                Label("Tutorial", systemImage: "wand.and.sparkles")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.74, green: 0.32, blue: 0.08))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color(red: 0.93, green: 0.50, blue: 0.16).opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: Color(red: 0.72, green: 0.40, blue: 0.14).opacity(0.12), radius: 14, y: 7)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.trailing, 18)
            .accessibilityLabel(Text("Replay home tutorial"))
        }
    }

    func startHomeTutorialDebug() {
        homeTutorialStep = .composer

        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            isHomeTutorialPresented = true
        }
    }

    func finishHomeTutorial() {
        // We only chain into the day-swipe tutorial when the user is on
        // the FINAL step (.progress) tapping Done. Skip / X paths set the
        // step elsewhere or close mid-flow — those shouldn't summon the
        // day-swipe overlay. Admin replay also lands here, but the
        // day-swipe flag in UserDefaults is permanent so it won't fire.
        let reachedDone = homeTutorialStep == .progress

        withAnimation(.easeOut(duration: 0.22)) {
            isHomeTutorialPresented = false
        }
        homeTutorialStep = .composer

        guard reachedDone else { return }
        guard !UserDefaults.standard.bool(forKey: daySwipeTutorialShownKey) else { return }

        // Tiny delay so the tutorial card finishes fading before the
        // day-swipe overlay's backdrop fades in. Both transitions are
        // ~220ms ease, so a 240ms wait gives a clean handoff.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.easeOut(duration: 0.22)) {
                isDaySwipeTutorialPresented = true
            }
        }
    }

    func finishDaySwipeTutorial() {
        UserDefaults.standard.set(true, forKey: daySwipeTutorialShownKey)
        withAnimation(.easeOut(duration: 0.32)) {
            isDaySwipeTutorialPresented = false
        }
        // Item 2 (2026-05-22): after the user finishes the day-swipe
        // tutorial, surface the full logging-tips sheet exactly once — this
        // is what teaches them how to phrase entries (portion, brand,
        // count, etc.) so the first real logs land accurate. Gated by a
        // separate UserDefaults flag so we never repeat.
        guard !UserDefaults.standard.bool(forKey: postTutorialLoggingTipsShownKey) else { return }
        UserDefaults.standard.set(true, forKey: postTutorialLoggingTipsShownKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isLoggingTipsPresented = true
        }
    }
}

let postTutorialLoggingTipsShownKey = "food-app.postTutorialLoggingTips.shown.v1"

let daySwipeTutorialShownKey = "food-app.daySwipeTutorial.shown.v1"

struct HomeCoachCardTutorialOverlay: View {
    @Binding var isPresented: Bool
    @Binding var step: HomeCoachCardTutorialStep
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.20)
                .ignoresSafeArea()

            VStack {
                Spacer()

                coachCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 26)
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(stepLabel)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Color(red: 0.83, green: 0.40, blue: 0.11))

                    Text(title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.15, green: 0.12, blue: 0.10))
                }

                Spacer(minLength: 8)

                Button {
                    onFinish()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.43, green: 0.38, blue: 0.33))
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close tutorial"))
            }

            Text(message)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .lineSpacing(3)
                .foregroundStyle(Color(red: 0.42, green: 0.37, blue: 0.33))

            featurePreview

            buttons

            stepDots
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.995, green: 0.989, blue: 0.980))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color(red: 0.95, green: 0.90, blue: 0.83), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 20, y: 10)
    }

    private var featurePreview: some View {
        HStack(spacing: 14) {
            previewBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(previewTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.18, green: 0.14, blue: 0.12))

                Text(previewMessage)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.53, green: 0.47, blue: 0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(previewBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(previewBorderColor, lineWidth: 1)
        )
    }

    private var previewBadge: some View {
        ZStack {
            Circle()
                .fill(previewBadgeBackground)
                .frame(width: 48, height: 48)

            Image(systemName: previewSystemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(previewIconColor)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        // Tutorial v2 (Item 1, 2026-05-22): the tutorial is now a passive
        // read-through. Each card has one primary CTA — Next / Next / Done —
        // that just advances. The previous build wired the primary into
        // real-app actions (focus composer, open camera, open progress),
        // which made the tutorial feel like setup work the user had to do.
        // The Skip link in the top-right (alongside the X) lets users bail
        // out at any point without entering the day-swipe overlay.
        let isFinalStep = step == .progress
        tutorialButton(isFinalStep ? "Done" : "Next", style: .primary) {
            if isFinalStep {
                onFinish()
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.90)) {
                    step = step == .composer ? .camera : .progress
                }
            }
        }
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(HomeCoachCardTutorialStep.allDisplaySteps, id: \.self) { candidate in
                Capsule(style: .continuous)
                    .fill(candidate == step ? Color(red: 0.18, green: 0.14, blue: 0.12) : Color.black.opacity(0.10))
                    .frame(width: candidate == step ? 22 : 7, height: 7)
                    .animation(.easeOut(duration: 0.18), value: step)
            }
        }
        .accessibilityHidden(true)
    }

    private var stepLabel: String {
        switch step {
        case .composer: return "Step 1 of 3"
        case .camera: return "Step 2 of 3"
        case .progress: return "Step 3 of 3"
        }
    }

    private var title: String {
        switch step {
        case .composer: return "Start with typing"
        case .camera: return "Use the camera fast"
        case .progress: return "Check how the day looks"
        }
    }

    private var message: String {
        switch step {
        case .composer:
            return "Type what you ate and keep moving. The home composer is the fastest way to log most meals."
        case .camera:
            return "If a meal is easier to snap than describe, the camera can turn a quick photo into a log."
        case .progress:
            return "Your calories, macros, and streaks build up through the day, so progress is where the bigger picture lives."
        }
    }

    private var previewTitle: String {
        switch step {
        case .composer: return "Quick text logging"
        case .camera: return "Photo-first logging"
        case .progress: return "Daily progress"
        }
    }

    private var previewMessage: String {
        switch step {
        case .composer: return "Tap into the input, write naturally, and log without navigating away."
        case .camera: return "Open the camera when typing feels slower than snapping the meal."
        case .progress: return "Open charts and insights after a few logs to spot trends and stay consistent."
        }
    }

    private var previewSystemImage: String {
        switch step {
        case .composer: return "square.and.pencil"
        case .camera: return "camera.fill"
        case .progress: return "chart.bar.fill"
        }
    }

    private var previewBackground: LinearGradient {
        switch step {
        case .composer:
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.963, blue: 0.918),
                    Color(red: 0.996, green: 0.985, blue: 0.962)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .camera:
            return LinearGradient(
                colors: [
                    Color(red: 0.963, green: 0.969, blue: 1.0),
                    Color(red: 0.986, green: 0.989, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .progress:
            return LinearGradient(
                colors: [
                    Color(red: 0.962, green: 0.985, blue: 0.955),
                    Color(red: 0.989, green: 0.996, blue: 0.985)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var previewBadgeBackground: Color {
        switch step {
        case .composer: return Color(red: 0.996, green: 0.864, blue: 0.694)
        case .camera: return Color(red: 0.835, green: 0.878, blue: 1.0)
        case .progress: return Color(red: 0.812, green: 0.930, blue: 0.815)
        }
    }

    private var previewIconColor: Color {
        switch step {
        case .composer: return Color(red: 0.86, green: 0.42, blue: 0.12)
        case .camera: return Color(red: 0.25, green: 0.37, blue: 0.86)
        case .progress: return Color(red: 0.18, green: 0.54, blue: 0.28)
        }
    }

    private var previewBorderColor: Color {
        switch step {
        case .composer: return Color(red: 0.964, green: 0.844, blue: 0.713)
        case .camera: return Color(red: 0.833, green: 0.879, blue: 0.993)
        case .progress: return Color(red: 0.818, green: 0.921, blue: 0.821)
        }
    }

    private enum TutorialButtonStyle {
        case primary
        case secondary
    }

    private func tutorialButton(
        _ title: String,
        style: TutorialButtonStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .foregroundStyle(style == .primary ? Color.white : Color(red: 0.22, green: 0.18, blue: 0.15))
                .background(
                    style == .primary
                    ? AnyShapeStyle(Color(red: 0.93, green: 0.46, blue: 0.12))
                    : AnyShapeStyle(Color.black.opacity(0.06)),
                    in: Capsule(style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

private extension HomeCoachCardTutorialStep {
    static let allDisplaySteps: [HomeCoachCardTutorialStep] = [
        .composer,
        .camera,
        .progress
    ]
}

// MARK: - Day-swipe interactive overlay (Items 2 & 14, 2026-05-22)
//
// Shown one time after the user finishes the home tutorial via Done.
// Teaches the left/right day-swipe gesture by asking the user to perform
// it themselves: dim backdrop + animated chevron + headline. Swipe left
// → flips to "swipe right". Swipe right → dismiss + persist shown flag.
// Skip link in the bottom corner ends the overlay early.

enum DaySwipeTutorialPhase {
    /// Prompt user to swipe right (translation.width > 0) — goes BACK a day.
    /// This works from any starting day, including a brand new user on
    /// today: the app loads the empty day view for yesterday.
    case promptRight
    /// Prompt user to swipe left (translation.width < 0) — returns FORWARD
    /// toward today (clamped at today, so this always lands them home).
    case promptLeft
}

private struct DaySwipeTutorialOverlay: View {
    @Binding var isPresented: Bool
    let onDismiss: () -> Void

    @State private var phase: DaySwipeTutorialPhase = .promptRight
    @State private var arrowOffset: CGFloat = 0
    @State private var arrowPulse: Double = 0.7
    @State private var dragTranslation: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.36)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 18) {
                Spacer()

                Image(systemName: arrowSystemImage)
                    .font(.system(size: 64, weight: .black))
                    .foregroundStyle(.white)
                    .opacity(arrowPulse)
                    .offset(x: arrowOffset)
                    .accessibilityHidden(true)

                Text(headline)
                    .font(.custom("InstrumentSerif-Italic", size: 32))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtext)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button(action: dismissNow) {
                    Text("Skip")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .underline()
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 36)
                .accessibilityLabel(Text("Skip day-swipe tutorial"))
            }
        }
        .transition(.opacity)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .local)
                .onChanged { value in
                    dragTranslation = value.translation.width
                }
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = abs(value.translation.height)
                    dragTranslation = 0
                    // Treat as a horizontal swipe only when the move is
                    // dominantly horizontal — vertical drags shouldn't
                    // count.
                    guard abs(dx) > 40, abs(dx) > dy else {
                        AppHaptics.lightImpact()
                        return
                    }
                    handleSwipe(dx: dx)
                }
        )
        .onAppear { startArrowAnimation() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Day swipe tutorial. \(headline). \(subtext)"))
        .accessibilityAddTraits(.isModal)
    }

    private var arrowSystemImage: String {
        phase == .promptRight ? "chevron.compact.right" : "chevron.compact.left"
    }

    private var headline: String {
        phase == .promptRight ? "Swipe right to see other days" : "Swipe left to come back"
    }

    private var subtext: String {
        phase == .promptRight
            ? "Days slide sideways. You can scrub through your history."
            : "One more swipe and you're done."
    }

    private func handleSwipe(dx: CGFloat) {
        let swipedRight = dx > 0
        switch phase {
        case .promptRight:
            guard swipedRight else {
                AppHaptics.lightImpact()
                return
            }
            // Forward the gesture to the underlying day list via
            // notification so the user actually sees the day change while
            // still inside the tutorial overlay.
            AppHaptics.lightImpact()
            NotificationCenter.default.post(name: .daySwipeTutorialDidAcknowledge, object: ["direction": "right"])
            withAnimation(.easeOut(duration: 0.22)) {
                phase = .promptLeft
                arrowOffset = 0
            }
            startArrowAnimation()
        case .promptLeft:
            guard !swipedRight else {
                AppHaptics.lightImpact()
                return
            }
            AppHaptics.lightImpact()
            NotificationCenter.default.post(name: .daySwipeTutorialDidAcknowledge, object: ["direction": "left"])
            dismissNow()
        }
    }

    private func dismissNow() {
        onDismiss()
    }

    private func startArrowAnimation() {
        guard !reduceMotion else {
            arrowPulse = 1.0
            return
        }
        // promptRight → arrow points right and nudges right (+8).
        // promptLeft  → arrow points left and nudges left (-8).
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            arrowOffset = phase == .promptRight ? 8 : -8
            arrowPulse = 1.0
        }
    }
}

private struct DaySwipeTutorialHostModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                DaySwipeTutorialOverlay(
                    isPresented: $isPresented,
                    onDismiss: onDismiss
                )
                .zIndex(220)
            }
        }
    }
}

extension View {
    func daySwipeTutorialHost(
        isPresented: Binding<Bool>,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(DaySwipeTutorialHostModifier(isPresented: isPresented, onDismiss: onDismiss))
    }
}

extension Notification.Name {
    /// Posted when the user acknowledges the day-swipe tutorial. Listeners
    /// (MainLoggingShellBody) can react by performing the actual day
    /// transition so the user sees the swipe land while still inside the
    /// overlay.
    static let daySwipeTutorialDidAcknowledge = Notification.Name("food-app.daySwipeTutorial.acknowledge")
}
