import SwiftUI

struct OB02bSocialProofScreen: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var graphProgress: CGFloat = 0
    @State private var statVisible = false
    @State private var floating = false

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                Spacer()

                // Headline
                Text("Food App provides\nlong-term results")
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 41))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .padding(.horizontal, 24)

                // Animated graph card — floats gently
                graphCard
                    .padding(.top, 32)
                    .padding(.horizontal, 36)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: floating ? -8 : 8)

                // Research stat
                researchStat
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                    .opacity(statVisible ? 1 : 0)
                    .offset(y: statVisible ? 0 : 10)

                Spacer()

                // CTA
                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text("Next")
                            .font(.system(size: 16, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(OnboardingGlassTheme.ctaForeground)
                    .frame(width: 220, height: 60)
                    .background(OnboardingGlassTheme.ctaBackground, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
            // Plot the curve slowly, after the screen has settled in.
            withAnimation(.easeInOut(duration: 3.0).delay(0.6)) {
                graphProgress = 1.0
            }
            // Stat arrives just as the curve completes.
            withAnimation(.easeOut(duration: 0.5).delay(3.0)) {
                statVisible = true
            }
            // Gentle, noticeable float — starts after the graph finishes drawing.
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true).delay(3.6)) {
                floating = true
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

    // MARK: - Graph Card

    private var graphCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Graph
            ZStack(alignment: .bottomLeading) {
                // Grid lines
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Spacer()
                        Rectangle()
                            .fill(OnboardingGlassTheme.textPrimary.opacity(0.08))
                            .frame(height: 1)
                    }
                    Spacer()
                }

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let teal = Color(red: 0.18, green: 0.56, blue: 0.42)
                    let coral = Color(red: 0.90, green: 0.35, blue: 0.30)

                    // Food App: smooth downward curve (2 points)
                    let foodAppPoints: [CGPoint] = [
                        CGPoint(x: 0.00, y: 0.65),
                        CGPoint(x: 1.00, y: 0.08)
                    ]

                    // Other apps: dips down first, then rebounds UP
                    let otherAppsPoints: [CGPoint] = [
                        CGPoint(x: 0.00, y: 0.65),
                        CGPoint(x: 0.35, y: 0.40),
                        CGPoint(x: 1.00, y: 0.88)
                    ]

                    // Other apps — dashed coral
                    AnimatedCurvePath(points: otherAppsPoints, size: geo.size, progress: graphProgress)
                        .stroke(style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [10, 7]))
                        .foregroundStyle(coral)

                    // Food App — solid teal
                    AnimatedCurvePath(points: foodAppPoints, size: geo.size, progress: graphProgress)
                        .stroke(style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .foregroundStyle(teal)

                    // Dots — teal start + end
                    graphDot(color: teal, x: 0, y: (1 - 0.65) * h, visible: true)
                    graphDot(color: teal, x: w, y: (1 - 0.08) * h, visible: graphProgress > 0.92)

                    // Dots — coral start (shared) + end
                    graphDot(color: coral, x: 0, y: (1 - 0.65) * h, visible: true)
                        .offset(x: 0, y: -1)
                    graphDot(color: coral, x: w, y: (1 - 0.88) * h, visible: graphProgress > 0.92)

                    // Labels
                    if graphProgress > 0.35 {
                        Text("Other apps")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(coral)
                            .position(x: w * 0.78, y: (1 - 0.88) * h - 18)

                        Text("Food App")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(teal, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .position(x: w * 0.68, y: (1 - 0.22) * h)
                    }

                    // Axis labels
                    Text("Your weight")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .position(x: w * 0.16, y: h * 0.08)

                    Text("Time")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(OnboardingGlassTheme.textMuted)
                        .position(x: w * 0.08, y: h * 0.97)
                }
            }
            .frame(height: 240)
            .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
                .shadow(color: Color.black.opacity(floating ? 0.10 : 0.06), radius: floating ? 24 : 16, y: floating ? 8 : 4)
        )
    }

    private func graphDot(color: Color, x: CGFloat, y: CGFloat, visible: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(Circle().fill(Color.white).frame(width: 5, height: 5))
            .position(x: x, y: y)
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.3)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: visible)
    }

    // MARK: - Research Stat

    private var researchStat: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color(red: 0.18, green: 0.56, blue: 0.42))

            Text("Research shows consistent calorie tracking leads to **2x more weight loss** sustained over 6 months.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.18, green: 0.56, blue: 0.42).opacity(0.08))
        )
    }
}

// MARK: - Animated Curve Path

private struct AnimatedCurvePath: Shape {
    let points: [CGPoint]
    let size: CGSize
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard points.count >= 2 else { return Path() }

        let scaled = points.map { pt in
            CGPoint(x: pt.x * size.width, y: (1 - pt.y) * size.height)
        }

        var path = Path()
        path.move(to: scaled[0])

        for i in 1..<scaled.count {
            let prev = scaled[i - 1]
            let curr = scaled[i]
            let midX = (prev.x + curr.x) / 2
            path.addCurve(
                to: curr,
                control1: CGPoint(x: midX, y: prev.y),
                control2: CGPoint(x: midX, y: curr.y)
            )
        }

        // Trim to progress
        return path.trimmedPath(from: 0, to: progress)
    }
}
