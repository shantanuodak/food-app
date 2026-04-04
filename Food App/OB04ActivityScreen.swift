import SwiftUI

struct OB04ActivityScreen: View {
    @Binding var selectedActivity: ActivityChoice?
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let canContinue = selectedActivity != nil

        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                Spacer()

                Text("How active are you\nmost days?")
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 38))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Text("Choose your typical day, not your best day.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)

                VStack(spacing: 12) {
                    ForEach(ActivityChoice.allCases) { choice in
                        ActivityOptionCard(
                            choice: choice,
                            isSelected: choice == selectedActivity,
                            action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    selectedActivity = choice
                                }
                            }
                        )
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
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            if selectedActivity == nil {
                selectedActivity = .moderatelyActive
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

// MARK: - Activity Option Card

private struct ActivityOptionCard: View {
    let choice: ActivityChoice
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: (icon: String, accent: Color, subtitle: String) {
        switch choice {
        case .mostlySitting:
            return ("chair.fill", Color(red: 0.55, green: 0.55, blue: 0.62), "Desk job, minimal movement")
        case .lightlyActive:
            return ("figure.walk", Color(red: 0.30, green: 0.70, blue: 0.50), "Some walking, light tasks")
        case .moderatelyActive:
            return ("figure.run", Color(red: 0.20, green: 0.60, blue: 0.85), "Regular exercise 3–5x/week")
        case .veryActive:
            return ("figure.highintensity.intervaltraining", Color(red: 0.90, green: 0.50, blue: 0.25), "Intense daily training")
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                activityIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(choice.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Text(theme.subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(OnboardingGlassTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.accent)
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

    private var activityIcon: some View {
        Image(systemName: theme.icon)
            .font(.system(size: 24))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(theme.accent)
            .frame(width: 36)
    }
}

