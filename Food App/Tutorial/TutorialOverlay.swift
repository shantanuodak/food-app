import SwiftUI

/// First-launch tutorial — a swipeable, paginated 5-tip sheet shown
/// the first time a user reaches the home screen after onboarding.
///
/// Each page is a single tip: SF Symbol + short title + body + Next/Done
/// button. The user can either tap Next (or Done on the last page),
/// swipe between pages with the page-style TabView, or tap Skip to
/// dismiss the whole sequence early.
///
/// Persistence is handled by `TutorialController`. Once finished or
/// skipped, the tutorial does not re-fire on subsequent launches.
struct TutorialOverlay: View {
    @ObservedObject var controller: TutorialController
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0

    private let steps: [TutorialStep] = TutorialStep.allCases

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $currentIndex) {
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                    TutorialStepView(step: step)
                        .tag(idx)
                        .padding(.horizontal, 24)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            footer
        }
        .padding(.vertical, 16)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .onDisappear {
            // Whenever the sheet closes — Skip, Done, or interactive
            // drag-to-dismiss — mark the tutorial finished so it doesn't
            // re-fire on the next launch.
            controller.finish()
        }
    }

    // MARK: - Header (Skip)

    private var header: some View {
        HStack {
            Spacer()
            Button {
                controller.finish()
            } label: {
                Text("Skip")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Skip tutorial"))
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Footer (Next / Done)

    private var footer: some View {
        let isLast = currentIndex >= steps.count - 1
        return Button {
            if isLast {
                controller.finish()
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentIndex += 1
                }
            }
        } label: {
            Text(isLast ? "Got it" : "Next")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.62, blue: 0.20),
                            Color(red: 0.90, green: 0.36, blue: 0.10)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}

// MARK: - Step model

enum TutorialStep: Int, CaseIterable, Identifiable {
    case photo
    case voice
    case swipeDays
    case streak
    case calories

    var id: Int { rawValue }

    var systemImage: String {
        switch self {
        case .photo: return "camera.fill"
        case .voice: return "mic.fill"
        case .swipeDays: return "arrow.left.and.right"
        case .streak: return "flame.fill"
        case .calories: return "chart.bar.fill"
        }
    }

    /// Accent color per step. Matches the on-screen element each tip
    /// points at (camera button is indigo, mic is magenta, etc.) so the
    /// user can intuit the connection.
    var accent: Color {
        switch self {
        case .photo:     return Color(red: 0.380, green: 0.333, blue: 0.961)
        case .voice:     return Color(red: 0.796, green: 0.188, blue: 0.878)
        case .swipeDays: return Color(red: 0.95, green: 0.55, blue: 0.20)
        case .streak:    return .orange
        case .calories:  return .green
        }
    }

    var title: String {
        switch self {
        case .photo:     return "Log a meal with a photo"
        case .voice:     return "Or just say it"
        case .swipeDays: return "Swipe to change days"
        case .streak:    return "Track your streak"
        case .calories:  return "See your daily totals"
        }
    }

    var body: String {
        switch self {
        case .photo:
            return "Tap the camera button on the bottom dock. We'll estimate calories and macros from your photo."
        case .voice:
            return "Tap the mic and speak naturally — \"two eggs and toast.\" We'll parse the rest."
        case .swipeDays:
            return "Swipe left or right anywhere on the home screen to jump between days."
        case .streak:
            return "The number next to the calendar shows your current logging streak. Tap it to see your full history."
        case .calories:
            return "Tap the flame icon to see today's calories and macros at a glance."
        }
    }
}

// MARK: - Single-step view

private struct TutorialStepView: View {
    let step: TutorialStep

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)
            ZStack {
                Circle()
                    .fill(step.accent.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: step.systemImage)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(step.accent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(step.title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(step.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 8)
        }
    }
}

#Preview {
    TutorialOverlay(controller: TutorialController())
}
