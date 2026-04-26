import SwiftUI

/// Mid-flow goal-validation preview. Calm, single-card layout — the user
/// can still adjust their plan from here, so this screen avoids the
/// celebratory framing reserved for `OB10ReadyScreen`.
///
/// Visual vocabulary matches the rest of the redesigned onboarding flow
/// (`OB02bSocialProofScreen`, `OB02eHowItWorksScreen`,
/// `OB06PreferencesOptionalScreen`): chevron-only back bar, Instrument
/// Serif headline, frosted-glass panels, singular warm-gold → mint accent.
struct OB05bGoalValidationScreen: View {
    let draft: OnboardingDraft
    let metrics: OnboardingMetrics
    let onBack: () -> Void
    let onContinue: () -> Void
    var onAdjustPlan: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var cardVisible = false
    @State private var kcalAnimatedValue: Double = 0
    @State private var macrosVisible = false

    // MARK: - Derived display values

    private var paceWeeks: Int {
        switch draft.pace ?? .balanced {
        case .conservative: return 16
        case .balanced: return 12
        case .aggressive: return 8
        }
    }

    private var weightUnit: String {
        (draft.units ?? .imperial) == .metric ? "kg" : "lbs"
    }

    private var currentWeight: String {
        "\(Int(draft.weightValue)) \(weightUnit)"
    }

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [OnboardingGlassTheme.accentStart, OnboardingGlassTheme.accentEnd],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        heroBlock
                            .padding(.top, 28)
                            .padding(.horizontal, 24)

                        planCard
                            .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 24)
                }

                actionButtons
                    .padding(.bottom, 24)
            }
        }
        .onAppear { runEntranceAnimation() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(height: 44)
    }

    // MARK: - Hero block

    private var heroBlock: some View {
        VStack(spacing: 8) {
            Text("Here's your starting plan")
                .font(OnboardingTypography.instrumentSerif(style: .regular, size: 41))
                .foregroundStyle(OnboardingGlassTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text("You can adjust before you start logging.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    // MARK: - Consolidated plan card

    private var planCard: some View {
        VStack(spacing: 0) {
            timelineStrip
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()
                .background(OnboardingGlassTheme.panelStroke)
                .padding(.horizontal, 20)

            kcalHero
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 18)

            macroPillsRow
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .onboardingGlassPanel(cornerRadius: 22, fillOpacity: 0.07, strokeOpacity: 0.14)
        .opacity(cardVisible ? 1 : 0)
        .offset(y: cardVisible ? 0 : 16)
    }

    // MARK: - Timeline strip (compact, single row)

    private var timelineStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(OnboardingGlassTheme.textMuted)
                    Text(currentWeight)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(OnboardingGlassTheme.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("GOAL")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(OnboardingGlassTheme.textMuted)
                    Text("\(paceWeeks) weeks")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(OnboardingGlassTheme.textPrimary)
                }
            }

            // Single accent track — no dots, no "Start/Midpoint/Target"
            Capsule()
                .fill(accentGradient)
                .frame(height: 4)

            if !metrics.projectedGoalDate.isEmpty {
                Text("Projected: \(metrics.projectedGoalDate)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(OnboardingGlassTheme.textMuted)
            }
        }
    }

    // MARK: - Kcal hero

    private var kcalHero: some View {
        VStack(spacing: 6) {
            Text("DAILY TARGET")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(OnboardingGlassTheme.textMuted)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Subtle flame — same orange gradient used by the camera-drawer hero
                // so the calorie pattern reads consistently across the app.
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, Color(red: 1, green: 0.45, blue: 0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(.bottom, 2)

                RollingNumberText(value: kcalAnimatedValue, fractionDigits: 0)
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 48))
                    .foregroundStyle(.primary)

                Text("kcal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
                    .offset(y: -4)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Daily target \(metrics.targetKcal) kilocalories"))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Macro cards (camera-drawer parity)

    private var macroPillsRow: some View {
        HStack(spacing: 10) {
            macroCard(
                icon: "bolt.fill",
                value: metrics.proteinTarget,
                label: "Protein",
                color: Color(red: 0.380, green: 0.333, blue: 0.961),
                index: 0
            )
            macroCard(
                icon: "leaf.fill",
                value: metrics.carbTarget,
                label: "Carbs",
                color: .green,
                index: 1
            )
            macroCard(
                icon: "drop.fill",
                value: metrics.fatTarget,
                label: "Fat",
                color: .blue,
                index: 2
            )
        }
    }

    /// Mirrors the `macroCard(...)` shape used by `CameraResultDrawerView`
    /// so the macro vocabulary (icon glyph + color + value + label layout)
    /// is identical between the camera-drawer summary and the onboarding
    /// preview.
    private func macroCard(icon: String, value: Int, label: String, color: Color, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)

            Text("\(value)g")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(OnboardingGlassTheme.textPrimary)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .onboardingGlassPanel(cornerRadius: 14, fillOpacity: 0.10, strokeOpacity: 0.14)
        .opacity(macrosVisible ? 1 : 0)
        .offset(y: macrosVisible ? 0 : 6)
        .animation(
            reduceMotion ? .none : .easeOut(duration: 0.4).delay(Double(index) * 0.08),
            value: macrosVisible
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label): \(value) grams"))
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button(action: onContinue) {
                HStack(spacing: 8) {
                    Text("Next")
                        .font(.system(size: 16, weight: .bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(OnboardingGlassTheme.ctaForeground)
                .frame(width: 220, height: 60)
                .background(OnboardingGlassTheme.ctaBackground)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            if let onAdjustPlan {
                Button(action: onAdjustPlan) {
                    Text("Adjust plan")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OnboardingGlassTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Entrance animation

    private func runEntranceAnimation() {
        if reduceMotion {
            appeared = true
            cardVisible = true
            kcalAnimatedValue = Double(metrics.targetKcal)
            macrosVisible = true
            return
        }

        withAnimation(.easeOut(duration: 0.4)) {
            appeared = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
            cardVisible = true
        }
        // Kcal rolls in from 0 — RollingNumberText handles the inner animation.
        withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.4)) {
            kcalAnimatedValue = Double(metrics.targetKcal)
        }
        // Macro pills cascade with a small stagger (handled per-pill).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            macrosVisible = true
        }
    }
}
