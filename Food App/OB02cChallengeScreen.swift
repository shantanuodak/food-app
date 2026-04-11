import SwiftUI

extension ChallengeChoice {
    var accentColor: Color {
        switch self {
        case .portionControl:    return Color(red: 0.94, green: 0.55, blue: 0.20)
        case .snacking:          return Color(red: 0.55, green: 0.40, blue: 0.85)
        case .eatingOut:         return Color(red: 0.90, green: 0.35, blue: 0.35)
        case .inconsistentMeals: return Color(red: 0.20, green: 0.65, blue: 0.85)
        case .emotionalEating:   return Color(red: 0.85, green: 0.40, blue: 0.60)
        }
    }
}

struct OB02cChallengeScreen: View {
    @Binding var selectedChallenge: ChallengeChoice?
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        let canContinue = selectedChallenge != nil

        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                Spacer()

                Text("What's your biggest\nchallenge?")
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 38))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                VStack(spacing: 12) {
                    ForEach(Array(ChallengeChoice.allCases.enumerated()), id: \.element.id) { idx, choice in
                        ChallengeOptionCard(
                            choice: choice,
                            isSelected: choice == selectedChallenge,
                            action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    selectedChallenge = choice
                                }
                            }
                        )
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                        .animation(.easeOut(duration: 0.45).delay(0.12 + Double(idx) * 0.07), value: appeared)
                    }
                }
                .padding(.top, 28)
                .padding(.horizontal, 20)

                Spacer()

                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text("Next")
                            .font(.system(size: 16, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 220, height: 60)
                    .background(Color.black.opacity(canContinue ? 1 : 0.2))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canContinue)
                .animation(.easeInOut(duration: 0.25), value: canContinue)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.45), value: appeared)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            if selectedChallenge == nil {
                selectedChallenge = .portionControl
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

// MARK: - Challenge Option Card

private struct ChallengeOptionCard: View {
    let choice: ChallengeChoice
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Dual-tone icon on the left
                Image(systemName: choice.icon)
                    .font(.system(size: 26))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(choice.accentColor)
                    .frame(width: 36)

                // Title + subtitle
                VStack(alignment: .leading, spacing: 3) {
                    Text(choice.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Text(choice.subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(OnboardingGlassTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                // Checkmark on selection
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(choice.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.white)

                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(choice.accentColor.opacity(0.10))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? choice.accentColor : (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? choice.accentColor.opacity(0.15) : Color.black.opacity(0.03),
                radius: isSelected ? 10 : 3,
                y: isSelected ? 3 : 1
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
