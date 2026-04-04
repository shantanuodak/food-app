import SwiftUI

struct OB02GoalScreen: View {
    @Binding var selectedGoal: GoalOption?

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Text("What's your goal?")
                .font(OnboardingTypography.instrumentSerif(style: .regular, size: 38))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)

            VStack(spacing: 14) {
                ForEach(GoalOption.allCases) { option in
                    GoalOptionCard(
                        option: option,
                        isSelected: option == selectedGoal,
                        action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedGoal = option
                            }
                        }
                    )
                }
            }
            .padding(.top, 32)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if selectedGoal == nil {
                selectedGoal = .maintain
            }
        }
    }
}

// MARK: - Goal Option Card

private struct GoalOptionCard: View {
    let option: GoalOption
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GoalTheme {
        switch option {
        case .lose:     return GoalTheme(
            accent: Color(red: 0.94, green: 0.42, blue: 0.33),
            icon:   "arrow.down.circle"
        )
        case .maintain: return GoalTheme(
            accent: Color(red: 0.20, green: 0.65, blue: 0.85),
            icon:   "equal.circle"
        )
        case .gain:     return GoalTheme(
            accent: Color(red: 0.30, green: 0.75, blue: 0.40),
            icon:   "arrow.up.circle"
        )
        }
    }

    private var subtitle: String {
        switch option {
        case .lose:     return "Reduce body fat with a calorie deficit"
        case .maintain: return "Stay where you are with balanced intake"
        case .gain:     return "Build muscle with a calorie surplus"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Dual-tone icon
                Image(systemName: theme.icon)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.accent)
                    .frame(width: 36)

                // Text — always dark, never white
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.goalLabel(option))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(OnboardingGlassTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    // Always white base
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.white)

                    // Color tint wash on selection
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(theme.accent.opacity(0.10))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? theme.accent : (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? theme.accent.opacity(0.15) : Color.black.opacity(0.03),
                radius: isSelected ? 10 : 3,
                y: isSelected ? 3 : 1
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

private struct GoalTheme {
    let accent: Color
    let icon: String
}
