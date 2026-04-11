import SwiftUI

struct OB05PaceScreen: View {
    @Binding var draft: OnboardingDraft
    @Binding var selectedPace: PaceChoice?
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    private var resolvedPace: PaceChoice {
        selectedPace ?? .balanced
    }

    private var paceDescription: String {
        switch resolvedPace {
        case .conservative: return "Slow and steady — easiest to maintain"
        case .balanced: return "The sweet spot for most people"
        case .aggressive: return "Faster results, requires more discipline"
        }
    }

    private var paceIconName: String {
        switch resolvedPace {
        case .conservative: return "tortoise.fill"
        case .balanced: return "hare.fill"
        case .aggressive: return "flame.fill"
        }
    }

    private var weeklyRate: String {
        switch draft.goal ?? .maintain {
        case .lose:
            switch resolvedPace {
            case .conservative: return "~0.25 lb/week"
            case .balanced: return "~0.5 lb/week"
            case .aggressive: return "~1 lb/week"
            }
        case .maintain:
            return "Maintain weight"
        case .gain:
            switch resolvedPace {
            case .conservative: return "~0.25 lb/week"
            case .balanced: return "~0.5 lb/week"
            case .aggressive: return "~0.75 lb/week"
            }
        }
    }

    var body: some View {
        let style = styleForPace(resolvedPace)

        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                // Headline
                Text("Choose your pace")
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 41))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .padding(.top, 20)

                Text("Consistency beats speed")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.51, green: 0.51, blue: 0.51))
                    .opacity(appeared ? 1 : 0)
                    .padding(.top, 8)

                Spacer()

                // Pace name — hero text (fixed height to prevent layout shift on pace change)
                VStack(spacing: 12) {
                    Image(systemName: paceIconName)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(style.foreground)
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: resolvedPace)
                        .frame(height: 40)

                    Text(resolvedPace.title)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(style.foreground)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: resolvedPace)
                        .frame(height: 50)

                    Text(paceDescription)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .frame(height: 40, alignment: .top)
                        .animation(.easeInOut(duration: 0.2), value: resolvedPace)
                }
                .padding(.horizontal, 32)
                .frame(height: 160)

                // Slider
                paceSlider(style: style)
                    .padding(.top, 40)
                    .padding(.horizontal, 34)

                // Weekly rate pill
                Text(weeklyRate)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(style.foreground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(style.foreground.opacity(0.12))
                    )
                    .padding(.top, 24)
                    .animation(.easeInOut(duration: 0.2), value: resolvedPace)

                Spacer()

                // CTA
                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text("Next")
                            .font(.system(size: 16, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 220, height: 60)
                    .background(Color.black)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            if selectedPace == nil {
                selectedPace = .balanced
            }
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    // MARK: - Top Bar

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

    // MARK: - Slider (native)

    @State private var sliderValue: Double = 1

    private func paceSlider(style: PaceVisualStyle) -> some View {
        VStack(spacing: 12) {
            Slider(value: $sliderValue, in: 0...2, step: 1) {
                Text("Pace")
            } minimumValueLabel: {
                Text("Slow")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OnboardingGlassTheme.textMuted)
            } maximumValueLabel: {
                Text("Fast")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OnboardingGlassTheme.textMuted)
            }
            .tint(style.foreground)
            .onChange(of: sliderValue) { _, newValue in
                let allChoices = PaceChoice.allCases
                let index = min(max(Int(newValue.rounded()), 0), allChoices.count - 1)
                if selectedPace != allChoices[index] {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedPace = allChoices[index]
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .onAppear {
                let allChoices = PaceChoice.allCases
                sliderValue = Double(allChoices.firstIndex(of: resolvedPace) ?? 1)
            }
            .onChange(of: selectedPace) { _, newPace in
                let allChoices = PaceChoice.allCases
                let newIndex = Double(allChoices.firstIndex(of: newPace ?? .balanced) ?? 1)
                if sliderValue != newIndex {
                    sliderValue = newIndex
                }
            }

            // Labels under the slider
            HStack {
                ForEach(PaceChoice.allCases) { choice in
                    Text(choice.title)
                        .font(.system(size: 11, weight: choice == resolvedPace ? .bold : .regular))
                        .foregroundStyle(choice == resolvedPace ? style.foreground : OnboardingGlassTheme.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func styleForPace(_ pace: PaceChoice) -> PaceVisualStyle {
        switch pace {
        case .conservative:
            return PaceVisualStyle(
                foreground: Color(red: 0.05, green: 0.51, blue: 0.98),
                background: Color(red: 0.87, green: 0.96, blue: 1.0)
            )
        case .balanced:
            return PaceVisualStyle(
                foreground: Color(red: 0.39, green: 0.80, blue: 0.04),
                background: Color(red: 0.93, green: 1.0, blue: 0.82)
            )
        case .aggressive:
            return PaceVisualStyle(
                foreground: Color(red: 0.79, green: 0.50, blue: 0.02),
                background: Color(red: 1.0, green: 0.94, blue: 0.81)
            )
        }
    }
}

private struct PaceVisualStyle {
    let foreground: Color
    let background: Color
}
