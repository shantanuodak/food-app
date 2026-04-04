import SwiftUI

struct OB02cChallengeInsightScreen: View {
    let challenge: ChallengeChoice
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var helpVisible = false
    @State private var shimmerPhase: CGFloat = -1

    private let teal = Color(red: 0.18, green: 0.56, blue: 0.42)

    private var content: (headline: String, insight: String, help: String) {
        switch challenge {
        case .portionControl:
            return (
                headline: "Portions are tricky.\nWe make them obvious.",
                insight: "Studies show people underestimate calories by up to 50% — even nutritionists get it wrong.",
                help: "Type what you ate, and we instantly show the real calorie count. No measuring cups. No guessing. Just type \"a bowl of pasta\" and see the truth in seconds."
            )
        case .snacking:
            return (
                headline: "Night cravings?\nWe'll be your wingman.",
                insight: "Late-night snacking accounts for 25% of excess daily calories for most people.",
                help: "We learn your patterns and send a smart nudge right before your danger zone. You'll see exactly how much your day is on track — making it easier to say \"I'm good.\""
            )
        case .eatingOut:
            return (
                headline: "Eat out freely.\nWe'll do the math.",
                insight: "A single restaurant meal can pack 1,200+ calories — and the menu won't tell you.",
                help: "Snap a photo of your plate or just type \"chicken teriyaki from takeout.\" Our AI breaks it down instantly — no barcode scanning, no searching databases."
            )
        case .inconsistentMeals:
            return (
                headline: "Skipped meals?\nWe'll keep you on track.",
                insight: "Irregular eating throws off hunger hormones, leading to 40% more overeating at your next meal.",
                help: "We spot gaps in your logging and send gentle reminders. Over time, you'll see your meal timing patterns — and watch them get more consistent, effortlessly."
            )
        case .emotionalEating:
            return (
                headline: "It's not about willpower.\nIt's about awareness.",
                insight: "Research shows that a 60-second pause before eating reduces emotional binges by over 50%.",
                help: "Just open the app and type what you're about to eat. That simple act creates a mindful pause — breaking the automatic stress → eat cycle. No judgment, just a moment of clarity."
            )
        }
    }

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                Spacer()

                // Headline
                Text(content.headline)
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 41))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .padding(.horizontal, 24)

                // Insight — simple muted text
                Text(content.insight)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 16)
                    .padding(.horizontal, 32)
                    .opacity(appeared ? 1 : 0)

                Spacer()

                // Help card — full width, prominent
                helpCard
                    .padding(.horizontal, 16)
                    .opacity(helpVisible ? 1 : 0)
                    .offset(y: helpVisible ? 0 : 24)

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
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.5)) {
                helpVisible = true
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 1
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

    // MARK: - Help Card

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with shimmer
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(teal)

                Text("This is how we help")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(teal)
                    .textCase(.uppercase)
                    .tracking(1)
            }
            .overlay(helpShimmer)
            .compositingGroup()

            Text(content.help)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(teal.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(teal.opacity(0.12), lineWidth: 1)
                )
        )
    }

    // MARK: - Shimmer

    private var helpShimmer: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let sweepWidth = w * 0.6

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.7), location: 0.4),
                    .init(color: .white.opacity(0.85), location: 0.5),
                    .init(color: .white.opacity(0.7), location: 0.6),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: sweepWidth)
            .offset(x: shimmerPhase * (w + sweepWidth) - sweepWidth)
            .blendMode(.sourceAtop)
        }
    }
}
