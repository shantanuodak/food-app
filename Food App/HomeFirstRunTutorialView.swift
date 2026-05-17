import SwiftUI
import UIKit

enum HomeFirstRunTutorialStep: Equatable {
    case composer
    case firstEstimate
    case camera
    case progress
}

enum HomeFirstRunTutorialTarget: Hashable {
    case composer
    case camera
    case progress
}

enum HomeFirstRunTutorialLayout {
    static let coordinateSpaceName = "HomeFirstRunTutorialSpace"
}

private struct HomeFirstRunTutorialTargetFramePreferenceKey: PreferenceKey {
    static var defaultValue: [HomeFirstRunTutorialTarget: CGRect] = [:]

    static func reduce(
        value: inout [HomeFirstRunTutorialTarget: CGRect],
        nextValue: () -> [HomeFirstRunTutorialTarget: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func homeTutorialTarget(_ target: HomeFirstRunTutorialTarget) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HomeFirstRunTutorialTargetFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .named(HomeFirstRunTutorialLayout.coordinateSpaceName))]
                )
            }
        }
    }

    func homeFirstRunTutorialHost(
        isPresented: Binding<Bool>,
        step: Binding<HomeFirstRunTutorialStep>,
        onFocusComposer: @escaping () -> Void,
        onOpenCamera: @escaping () -> Void,
        onOpenProgress: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) -> some View {
        coordinateSpace(name: HomeFirstRunTutorialLayout.coordinateSpaceName)
            .overlayPreferenceValue(HomeFirstRunTutorialTargetFramePreferenceKey.self) { targetFrames in
                if isPresented.wrappedValue {
                    HomeFirstRunTutorialOverlay(
                        isPresented: isPresented,
                        step: step,
                        targetFrames: targetFrames,
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

extension MainLoggingShellView {
    func autoPresentHomeTutorialIfNeeded() {
        guard !hasEvaluatedAutoHomeTutorialPresentation else { return }
        hasEvaluatedAutoHomeTutorialPresentation = true

        guard appStore.isOnboardingComplete else { return }
        guard !defaults.bool(forKey: homeTutorialShownKey) else { return }
        guard !isHomeTutorialPresented else { return }
        guard selectedCameraSource == nil, !isQuickCameraCaptureActive, !isVoiceOverlayPresented else { return }

        defaults.set(true, forKey: homeTutorialShownKey)
        startHomeTutorialDebug()
    }

    var homeTutorialEstimatedFoodSignature: String {
        inputRows
            .filter { !$0.isSaved && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "\($0.id.uuidString):\($0.calories.map(String.init) ?? "-")" }
            .joined(separator: "|")
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
        homeTutorialIgnoredEstimatedRowIDs = Set(
            inputRows
                .filter { !$0.isSaved && $0.calories != nil }
                .map(\.id)
        )
        homeTutorialStep = .composer

        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            isHomeTutorialPresented = true
        }

        inputMode = .text
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NotificationCenter.default.post(name: .focusComposerInputFromBackgroundTap, object: nil)
        }
    }

    func advanceHomeTutorialIfEstimateIsReady() {
        guard isHomeTutorialPresented, homeTutorialStep == .composer else { return }

        let hasNewEstimatedRow = inputRows.contains { row in
            !row.isSaved &&
            !homeTutorialIgnoredEstimatedRowIDs.contains(row.id) &&
            row.calories != nil &&
            !row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard hasNewEstimatedRow else { return }

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            homeTutorialStep = .firstEstimate
        }
    }

    func finishHomeTutorial() {
        withAnimation(.easeOut(duration: 0.22)) {
            isHomeTutorialPresented = false
        }
        homeTutorialStep = .composer
        homeTutorialIgnoredEstimatedRowIDs.removeAll()
    }
}

struct HomeFirstRunTutorialOverlay: View {
    @Binding var isPresented: Bool
    @Binding var step: HomeFirstRunTutorialStep
    let targetFrames: [HomeFirstRunTutorialTarget: CGRect]
    let onFocusComposer: () -> Void
    let onOpenCamera: () -> Void
    let onOpenProgress: () -> Void
    let onFinish: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let frame = targetFrame(in: proxy.size)

            ZStack(alignment: .topLeading) {
                dimLayer(cutoutFrame: frame)

                if let frame {
                    RoundedRectangle(cornerRadius: cornerRadius(for: step), style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius(for: step), style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .shadow(color: Color(red: 0.97, green: 0.48, blue: 0.12).opacity(0.28), radius: 18)
                        .frame(width: frame.width + 14, height: frame.height + 14)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                }

                coachCard
                    .frame(width: min(proxy.size.width - 40, 338))
                    .position(coachPosition(in: proxy.size, targetFrame: frame))
            }
            .ignoresSafeArea()
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func dimLayer(cutoutFrame: CGRect?) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.26))
            .reverseMask {
                if let cutoutFrame {
                    RoundedRectangle(cornerRadius: cornerRadius(for: step), style: .continuous)
                        .frame(width: cutoutFrame.width + 18, height: cutoutFrame.height + 18)
                        .position(x: cutoutFrame.midX, y: cutoutFrame.midY)
                }
            }
            .onTapGesture {
                // Intentionally no-op. The tutorial is explicit so random taps
                // do not accidentally dismiss it during first-run education.
            }
    }

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(stepLabel)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Color(red: 0.73, green: 0.31, blue: 0.08))

                Spacer()

                Button {
                    onFinish()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.045), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close tutorial"))
            }

            Text(title)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .kerning(-0.7)
                .foregroundStyle(Color(red: 0.12, green: 0.09, blue: 0.07))

            Text(message)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineSpacing(2)
                .foregroundStyle(Color(red: 0.44, green: 0.39, blue: 0.35))

            buttons

            stepDots
                .padding(.top, 2)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 28, y: 16)
    }

    @ViewBuilder
    private var buttons: some View {
        switch step {
        case .composer:
            HStack(spacing: 10) {
                tutorialButton("Focus input", style: .primary) {
                    onFocusComposer()
                }

                Text("No save button.")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        case .firstEstimate:
            tutorialButton("Show camera", style: .primary) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                    step = .camera
                }
            }
        case .camera:
            HStack(spacing: 10) {
                tutorialButton("Later", style: .secondary) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                        step = .progress
                    }
                }
                tutorialButton("Open camera", style: .primary) {
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
            ForEach(HomeFirstRunTutorialStep.allDisplaySteps, id: \.self) { candidate in
                Capsule(style: .continuous)
                    .fill(candidate == step ? Color(red: 0.13, green: 0.09, blue: 0.07) : Color.black.opacity(0.12))
                    .frame(width: candidate == step ? 22 : 7, height: 7)
                    .animation(.easeOut(duration: 0.18), value: step)
            }
        }
        .accessibilityHidden(true)
    }

    private func targetFrame(in size: CGSize) -> CGRect? {
        switch step {
        case .composer, .firstEstimate:
            return targetFrames[.composer]
        case .camera:
            return targetFrames[.camera]
        case .progress:
            return targetFrames[.progress]
        }
    }

    private func coachPosition(in size: CGSize, targetFrame: CGRect?) -> CGPoint {
        guard let targetFrame else {
            return CGPoint(x: size.width / 2, y: min(size.height - 190, 410))
        }

        let cardHeight: CGFloat = 210
        let y: CGFloat
        if targetFrame.maxY + cardHeight + 28 < size.height {
            y = targetFrame.maxY + (cardHeight / 2) + 22
        } else {
            y = max(152, targetFrame.minY - (cardHeight / 2) - 22)
        }

        return CGPoint(x: size.width / 2, y: y)
    }

    private func cornerRadius(for step: HomeFirstRunTutorialStep) -> CGFloat {
        switch step {
        case .camera, .progress:
            return 999
        case .composer, .firstEstimate:
            return 22
        }
    }

    private var stepLabel: String {
        switch step {
        case .composer: return "Step 1 of 4"
        case .firstEstimate: return "Step 2 of 4"
        case .camera: return "Step 3 of 4"
        case .progress: return "Step 4 of 4"
        }
    }

    private var title: String {
        switch step {
        case .composer: return "Log your first meal"
        case .firstEstimate: return "That’s the loop"
        case .camera: return "Photos work too"
        case .progress: return "Track the pattern"
        }
    }

    private var message: String {
        switch step {
        case .composer:
            return "Type what you ate. When the app understands it, calories appear on the right automatically."
        case .firstEstimate:
            return "No extra button needed. You type, the app reads it, and the estimate shows up in place."
        case .camera:
            return "Use the camera when typing is slower than snapping a meal. A quick hint can help with tricky photos."
        case .progress:
            return "Progress, streaks, and nutrition cards update as you log meals through the day."
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
                .frame(height: 44)
                .foregroundStyle(style == .primary ? Color.white : Color(red: 0.22, green: 0.18, blue: 0.15))
                .background(style == .primary ? Color(red: 0.12, green: 0.09, blue: 0.07) : Color.black.opacity(0.06), in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private extension HomeFirstRunTutorialStep {
    static let allDisplaySteps: [HomeFirstRunTutorialStep] = [
        .composer,
        .firstEstimate,
        .camera,
        .progress
    ]
}

private extension View {
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay {
                    mask()
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
        }
    }
}
