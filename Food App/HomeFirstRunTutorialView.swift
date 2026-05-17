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
    let onFocusComposer: () -> Void
    let onOpenCamera: () -> Void
    let onOpenProgress: () -> Void
    let onFinish: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                HomeCoachCardTutorialOverlay(
                    isPresented: $isPresented,
                    step: $step,
                    onFocusComposer: onFocusComposer,
                    onOpenCamera: onOpenCamera,
                    onOpenProgress: onOpenProgress,
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
        onFocusComposer: @escaping () -> Void,
        onOpenCamera: @escaping () -> Void,
        onOpenProgress: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) -> some View {
        modifier(
            HomeCoachCardTutorialHostModifier(
                isPresented: isPresented,
                step: step,
                onFocusComposer: onFocusComposer,
                onOpenCamera: onOpenCamera,
                onOpenProgress: onOpenProgress,
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
        withAnimation(.easeOut(duration: 0.22)) {
            isHomeTutorialPresented = false
        }
        homeTutorialStep = .composer
    }
}

struct HomeCoachCardTutorialOverlay: View {
    @Binding var isPresented: Bool
    @Binding var step: HomeCoachCardTutorialStep
    let onFocusComposer: () -> Void
    let onOpenCamera: () -> Void
    let onOpenProgress: () -> Void
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
        switch step {
        case .composer:
            HStack(spacing: 10) {
                tutorialButton("Not now", style: .secondary) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.90)) {
                        step = .camera
                    }
                }

                tutorialButton("Try typing", style: .primary) {
                    onFocusComposer()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.90)) {
                        step = .camera
                    }
                }
            }
        case .camera:
            HStack(spacing: 10) {
                tutorialButton("Skip", style: .secondary) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.90)) {
                        step = .progress
                    }
                }

                tutorialButton("Try camera", style: .primary) {
                    onOpenCamera()
                    onFinish()
                }
            }
        case .progress:
            HStack(spacing: 10) {
                tutorialButton("Finish", style: .secondary) {
                    onFinish()
                }

                tutorialButton("Open progress", style: .primary) {
                    onOpenProgress()
                    onFinish()
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
