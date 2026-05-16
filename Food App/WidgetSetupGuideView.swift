import SwiftUI

private enum WidgetGuideMode: String, CaseIterable {
    case home = "Home"
    case lock = "Lock"

    var eyebrow: String {
        switch self {
        case .home: return "Home Screen"
        case .lock: return "Lock Screen"
        }
    }

    var title: String {
        switch self {
        case .home: return "Add the daily widget"
        case .lock: return "Add a quick glance widget"
        }
    }

    var icon: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .lock: return "lock.fill"
        }
    }

    var tint: Color {
        switch self {
        case .home: return WidgetGuideTokens.orange
        case .lock: return WidgetGuideTokens.blue
        }
    }

    var benefit: String {
        switch self {
        case .home: return "Camera and voice logging stay one tap away."
        case .lock: return "Check today without opening the app."
        }
    }

    var steps: [String] {
        switch self {
        case .home:
            return [
                "Press and hold empty space on your Home Screen.",
                "Tap Edit, then Add Widget.",
                "Search Food App and choose the daily widget.",
                "Place it where you log most often."
            ]
        case .lock:
            return [
                "Press and hold your Lock Screen.",
                "Tap Customize, then choose Lock Screen.",
                "Tap the widget area below the time.",
                "Add Food App, then tap Done."
            ]
        }
    }
}

struct WidgetSetupGuideView: View {
    enum PresentationStyle {
        case pushed
        case sheet(onClose: () -> Void)
    }

    let presentationStyle: PresentationStyle
    @State private var selectedMode: WidgetGuideMode = .home
    @State private var activeStep = 0

    init(presentationStyle: PresentationStyle = .pushed) {
        self.presentationStyle = presentationStyle
    }

    var body: some View {
        Group {
            switch presentationStyle {
            case .pushed:
                content
                    .navigationTitle("Widgets")
                    .navigationBarTitleDisplayMode(.inline)
            case .sheet(let onClose):
                VStack(spacing: 0) {
                    AppDrawerHeader(onClose: onClose) {
                        Text("Widgets")
                            .font(OnboardingTypography.instrumentSerif(style: .regular, size: 31))
                            .foregroundStyle(WidgetGuideTokens.brandGradient)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    content
                }
            }
        }
        .background(WidgetGuideTokens.screenBackground.ignoresSafeArea())
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                hero
                modePicker
                WidgetPreviewStrip(mode: selectedMode)
                interactiveStepCard
                tipCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(WidgetGuideTokens.screenBackground)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Widget shortcuts")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WidgetGuideTokens.orangeDeep)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.white.opacity(0.72), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(WidgetGuideTokens.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.06), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 0) {
                Text("Set it once. ")
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 42))
                + Text("Log faster.")
                    .font(OnboardingTypography.instrumentSerif(style: .italic, size: 42))
                    .foregroundStyle(WidgetGuideTokens.orangeDeep)
            }
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(-4)
            .foregroundStyle(WidgetGuideTokens.ink)

            Text("Pick where you want Food App to live, then swipe through the setup.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(WidgetGuideTokens.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(WidgetGuideMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        selectedMode = mode
                        activeStep = 0
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 13, weight: .bold))
                        Text(mode.rawValue)
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(selectedMode == mode ? .white : WidgetGuideTokens.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selectedMode == mode ? mode.tint : .white.opacity(0.62))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(selectedMode == mode ? .white.opacity(0.28) : WidgetGuideTokens.border, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(WidgetGuideTokens.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var interactiveStepCard: some View {
        let steps = selectedMode.steps
        let safeStep = min(activeStep, max(steps.count - 1, 0))

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(selectedMode.tint.opacity(0.14))
                    Image(systemName: selectedMode.icon)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(selectedMode.tint)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedMode.eyebrow.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(WidgetGuideTokens.muted)
                    Text(selectedMode.title)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(WidgetGuideTokens.ink)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                Text("\(safeStep + 1)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(selectedMode.tint, in: Circle())
                    .shadow(color: selectedMode.tint.opacity(0.22), radius: 12, y: 8)

                VStack(alignment: .leading, spacing: 7) {
                    Text(steps[safeStep])
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(WidgetGuideTokens.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(selectedMode.benefit)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WidgetGuideTokens.muted)
                }
            }

            stepProgress

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        activeStep = max(activeStep - 1, 0)
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .foregroundStyle(activeStep == 0 ? WidgetGuideTokens.muted.opacity(0.5) : WidgetGuideTokens.ink)
                .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(activeStep == 0)

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        activeStep = activeStep >= steps.count - 1 ? 0 : activeStep + 1
                    }
                } label: {
                    Label(activeStep >= steps.count - 1 ? "Replay" : "Next", systemImage: activeStep >= steps.count - 1 ? "arrow.counterclockwise" : "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .foregroundStyle(.white)
                .background(selectedMode.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white.opacity(0.74))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(WidgetGuideTokens.border, lineWidth: 1)
                }
                .shadow(color: WidgetGuideTokens.shadow, radius: 28, y: 16)
        )
        .id(selectedMode)
    }

    private var stepProgress: some View {
        HStack(spacing: 7) {
            ForEach(selectedMode.steps.indices, id: \.self) { index in
                Capsule()
                    .fill(index == activeStep ? selectedMode.tint : WidgetGuideTokens.border)
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(WidgetGuideTokens.orangeDeep)
                .frame(width: 34, height: 34)
                .background(WidgetGuideTokens.orange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text("Tiny setup, big payoff")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(WidgetGuideTokens.ink)
                Text("The widget updates from your saved logs. If it looks stale, open Food App once and it will refresh your daily snapshot.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WidgetGuideTokens.muted)
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(WidgetGuideTokens.border, lineWidth: 1)
        }
    }
}

private enum WidgetGuideTokens {
    static let ink = Color(red: 0.141, green: 0.098, blue: 0.078)
    static let muted = Color(red: 0.467, green: 0.416, blue: 0.380)
    static let orange = Color(red: 0.941, green: 0.482, blue: 0.133)
    static let orangeDeep = Color(red: 0.725, green: 0.306, blue: 0.071)
    static let blue = Color(red: 0.333, green: 0.404, blue: 0.969)
    static let border = Color(red: 0.278, green: 0.176, blue: 0.098).opacity(0.11)
    static let shadow = Color(red: 0.376, green: 0.212, blue: 0.078).opacity(0.13)

    static let brandGradient = LinearGradient(
        colors: [Color(red: 1.00, green: 0.62, blue: 0.20), Color(red: 0.90, green: 0.36, blue: 0.10)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let screenBackground = LinearGradient(
        colors: [
            Color(red: 0.965, green: 0.886, blue: 0.792),
            Color(red: 1.000, green: 0.976, blue: 0.941),
            Color(red: 0.941, green: 0.930, blue: 0.992)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct WidgetPreviewStrip: View {
    let mode: WidgetGuideMode

    var body: some View {
        ZStack {
            if mode == .home {
                HStack(spacing: 12) {
                    previewSmallWidget
                    homeActionsCard
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                HStack(spacing: 12) {
                    lockScreenMock
                    previewLockWidget
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.white.opacity(0.62))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(WidgetGuideTokens.border, lineWidth: 1)
                }
                .shadow(color: WidgetGuideTokens.shadow, radius: 26, y: 14)
        )
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: mode)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode == .home ? "Home Screen widget preview with calories, camera, and voice actions." : "Lock Screen widget preview with quick calorie progress.")
    }

    private var previewSmallWidget: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("842")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text("cal")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .foregroundStyle(.white)

            Capsule()
                .fill(.white.opacity(0.18))
                .frame(height: 7)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(WidgetGuideTokens.brandGradient)
                        .frame(width: 72, height: 7)
                }

            HStack(spacing: 8) {
                widgetActionIcon("camera.fill", tint: WidgetGuideTokens.orange)
                widgetActionIcon("mic.fill", tint: WidgetGuideTokens.blue)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(15)
        .frame(maxWidth: .infinity)
        .frame(height: 132)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.060, blue: 0.085),
                    Color(red: 0.090, green: 0.075, blue: 0.125),
                    Color(red: 0.060, green: 0.085, blue: 0.115)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var homeActionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tap once")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WidgetGuideTokens.muted)

            HStack(spacing: 10) {
                widgetActionIcon("camera.fill", tint: WidgetGuideTokens.orange)
                widgetActionIcon("mic.fill", tint: WidgetGuideTokens.blue)
            }

            Text("Open camera or voice without hunting for the app.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WidgetGuideTokens.ink.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 132)
        .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var lockScreenMock: some View {
        VStack(spacing: 10) {
            Text("11:30")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 8) {
                Capsule()
                    .fill(.white.opacity(0.36))
                    .frame(width: 58, height: 26)
                previewLockWidget
                    .frame(width: 104)
                    .scaleEffect(0.78)
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .padding(15)
        .frame(maxWidth: .infinity)
        .frame(height: 132)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.098, green: 0.118, blue: 0.172),
                    Color(red: 0.188, green: 0.149, blue: 0.278)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var previewLockWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.28), in: Circle())
                Text("842")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("cal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .foregroundStyle(.white)

            Capsule()
                .fill(.white.opacity(0.20))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white)
                        .frame(width: 62, height: 5)
                }

            Text("of 1,770 kcal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: 132)
        .background(
            LinearGradient(
                colors: [WidgetGuideTokens.blue, Color(red: 0.349, green: 0.251, blue: 0.780)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private func widgetActionIcon(_ systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(tint.opacity(0.28), in: Circle())
            .overlay {
                Circle().stroke(.white.opacity(0.26), lineWidth: 1)
            }
    }
}

#Preview {
    NavigationStack {
        WidgetSetupGuideView()
    }
}
