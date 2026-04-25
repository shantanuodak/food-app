import SwiftUI

private extension ExperienceChoice {
    var accentColor: Color {
        switch self {
        case .newToIt:           return Color(red: 0.94, green: 0.45, blue: 0.28)
        case .triedButQuit:      return Color(red: 0.40, green: 0.72, blue: 0.40)
        case .currentlyCounting: return Color(red: 0.20, green: 0.60, blue: 0.80)
        }
    }
}

struct OB02dExperienceScreen: View {
    @Binding var selectedExperience: ExperienceChoice?
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        let canContinue = selectedExperience != nil

        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                Spacer()

                Text("Have you tried calorie\ncounting before?")
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 38))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                VStack(spacing: 12) {
                    ForEach(Array(ExperienceChoice.allCases.enumerated()), id: \.element.id) { idx, choice in
                        ExperienceOptionCard(
                            choice: choice,
                            isSelected: choice == selectedExperience,
                            action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    selectedExperience = choice
                                }
                            }
                        )
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                        .animation(.easeOut(duration: 0.45).delay(0.12 + Double(idx) * 0.08), value: appeared)
                    }
                }
                .padding(.top, 32)
                .padding(.horizontal, 20)

                Spacer()

                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text("Next")
                            .font(.system(size: 16, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(OnboardingGlassTheme.ctaForeground)
                    .frame(width: 220, height: 60)
                    .background(OnboardingGlassTheme.ctaBackground.opacity(canContinue ? 1 : 0.2))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canContinue)
                .animation(.easeInOut(duration: 0.25), value: canContinue)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.4), value: appeared)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            if selectedExperience == nil {
                selectedExperience = .newToIt
            }
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    private var topBar: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white)
                                .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
                        )
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .frame(height: 44)
    }
}

// MARK: - Experience Option Card

private struct ExperienceOptionCard: View {
    let choice: ExperienceChoice
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Dual-tone icon on the left
                Image(systemName: choice.icon)
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(choice.accentColor)
                    .frame(width: 36)

                // Title only — no subtitle for this screen
                Text(choice.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.white)

                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(choice.accentColor.opacity(0.08))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? choice.accentColor : (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? choice.accentColor.opacity(0.12) : Color.black.opacity(0.02),
                radius: isSelected ? 8 : 2,
                y: isSelected ? 2 : 1
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
