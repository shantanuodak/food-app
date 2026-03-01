import SwiftUI

private struct OnboardingDemoItem: Equatable {
    let text: String
    let calories: String?
    let isAmbiguous: Bool
}

private enum OnboardingDemoConstants {
    static let typingDelay: TimeInterval = 0.045
    static let pauseBeforeClear: TimeInterval = 1.35
    static let pauseBeforeType: TimeInterval = 0.35
    static let drawerPause: TimeInterval = 1.5

    static let sequence: [OnboardingDemoItem] = [
        OnboardingDemoItem(text: "2 eggs and toast", calories: "~310 cal", isAmbiguous: false),
        OnboardingDemoItem(text: "black coffee", calories: "2 cal", isAmbiguous: false),
        OnboardingDemoItem(text: "banana", calories: "~105 cal", isAmbiguous: false),
        OnboardingDemoItem(text: "avocado sandwich", calories: nil, isAmbiguous: true)
    ]
}

struct OnboardingTypingDemoView: View {
    @State private var currentIndex = 0
    @State private var typedText = ""
    @State private var showBadge = false
    @State private var showDrawer = false
    @State private var isBlinking = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentItem: OnboardingDemoItem {
        OnboardingDemoConstants.sequence[currentIndex]
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .top) {
                OnboardingConfirmationDrawerView()
                    .offset(y: showDrawer ? 56 : 0)
                    .opacity(showDrawer ? 1 : 0)
                    .scaleEffect(showDrawer ? 1 : 0.95, anchor: .top)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.75),
                        value: showDrawer
                    )
                    .zIndex(0)

                OnboardingTypingRowView(
                    text: typedText,
                    isBlinking: isBlinking,
                    showBadge: showBadge,
                    badgeText: currentItem.calories ?? ""
                )
                .zIndex(1)
            }
            .frame(height: 120, alignment: .top)
        }
        .frame(height: 120, alignment: .top)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.28), value: currentIndex)
        .task {
            await runAnimationLoop()
        }
    }

    private func runAnimationLoop() async {
        withAnimation(.linear(duration: 0.4).repeatForever(autoreverses: true)) {
            isBlinking = true
        }

        while !Task.isCancelled {
            for index in OnboardingDemoConstants.sequence.indices {
                if Task.isCancelled { break }
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) {
                    currentIndex = index
                }
                let item = OnboardingDemoConstants.sequence[index]

                typedText = ""
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.2)) {
                    showBadge = false
                    showDrawer = false
                }

                try? await Task.sleep(for: .seconds(OnboardingDemoConstants.pauseBeforeType))

                for character in item.text {
                    if Task.isCancelled { break }
                    typedText.append(character)
                    try? await Task.sleep(for: .seconds(OnboardingDemoConstants.typingDelay))
                }

                if item.isAmbiguous {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.76)) {
                        showDrawer = true
                    }
                    try? await Task.sleep(for: .seconds(OnboardingDemoConstants.drawerPause))
                } else {
                    withAnimation(reduceMotion ? .none : .easeOut(duration: 0.45)) {
                        showBadge = true
                    }
                    try? await Task.sleep(for: .seconds(OnboardingDemoConstants.pauseBeforeClear))
                }
            }
        }
    }
}

private struct OnboardingTypingRowView: View {
    let text: String
    let isBlinking: Bool
    let showBadge: Bool
    let badgeText: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            HStack(spacing: 2) {
                Text(text)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)

                Rectangle()
                    .fill(OnboardingGlassTheme.accentStart)
                    .frame(width: 2, height: 20)
                    .opacity(isBlinking ? 0 : 1)
            }

            Spacer()

            if showBadge {
                OnboardingCalorieBadge(text: badgeText)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .blurReplace),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            )
                    )
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .onboardingGlassPanel(cornerRadius: 16, fillOpacity: 0.08, strokeOpacity: 0.12)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}

private struct OnboardingCalorieBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OnboardingGlassTheme.accentStart)

            Text(text)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.05))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

private struct OnboardingConfirmationDrawerView: View {
    var body: some View {
        HStack {
            Text("Confirm item?")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .padding(6)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .onboardingGlassPanel(cornerRadius: 12, fillOpacity: 0.08, strokeOpacity: 0.1)
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
    }
}

private struct OnboardingBlurReplaceModifier: ViewModifier {
    let isIdentity: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: isIdentity ? 0 : 8)
            .scaleEffect(isIdentity ? 1 : 0.95)
    }
}

private extension AnyTransition {
    static var blurReplace: AnyTransition {
        .modifier(
            active: OnboardingBlurReplaceModifier(isIdentity: false),
            identity: OnboardingBlurReplaceModifier(isIdentity: true)
        )
    }
}
