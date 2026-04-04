import SwiftUI

struct OnboardingAnimatedBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OnboardingGlassTheme.backgroundStart,
                    OnboardingGlassTheme.backgroundEnd
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()

            AnimatedOrbLayer()

            DotMatrixOverlay()
                .ignoresSafeArea()

            NoiseOverlay()
                .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Static gradient-only background for non-welcome onboarding screens.
struct OnboardingStaticBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                OnboardingGlassTheme.backgroundStart,
                OnboardingGlassTheme.backgroundEnd
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AnimatedOrbLayer: View {
    private let loopDuration: TimeInterval = 20.0

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let progress = normalizedProgress(from: context.date.timeIntervalSinceReferenceDate)
                let state = OrbKeyframes.interpolate(progress: progress)
                let orbSize = proxy.size.width * 0.86
                let blurRadius = proxy.size.width * 0.14

                Circle()
                    .fill(state.color)
                    .frame(width: orbSize, height: orbSize)
                    .scaleEffect(state.scale)
                    .blur(radius: blurRadius)
                    .opacity(0.52)
                    .offset(
                        x: state.xVW * proxy.size.width,
                        y: state.yVH * proxy.size.height
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .ignoresSafeArea()
    }

    private func normalizedProgress(from time: TimeInterval) -> Double {
        let cycle = time.truncatingRemainder(dividingBy: loopDuration)
        return cycle / loopDuration
    }
}

private struct DotMatrixOverlay: View {
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let spacing: CGFloat = 24
            let radius: CGFloat = 1.2
            let dotColor = OnboardingGlassTheme.dotOverlay

            for x in stride(from: 0, through: size.width, by: spacing) {
                for y in stride(from: 0, through: size.height, by: spacing) {
                    let rect = CGRect(
                        x: x - radius,
                        y: y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                }
            }
        }
    }
}

private struct NoiseOverlay: View {
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let sampleCount = max(1200, Int((size.width * size.height) / 220))

            for i in 0..<sampleCount {
                let x = pseudoRandom(i, salt: 17) * size.width
                let y = pseudoRandom(i, salt: 53) * size.height
                let alpha = 0.008 + (pseudoRandom(i, salt: 91) * 0.018)

                let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                context.fill(Path(pixel), with: .color(OnboardingGlassTheme.noiseOverlay.opacity(alpha / 0.03)))
            }
        }
        .opacity(0.03)
    }

    private func pseudoRandom(_ seed: Int, salt: Int) -> CGFloat {
        let value = sin(Double(seed * 97 + salt * 131)) * 43758.5453
        return CGFloat(value - floor(value))
    }
}

private struct OrbKeyframeState {
    let xVW: CGFloat
    let yVH: CGFloat
    let scale: CGFloat
    let color: Color
}

private enum OrbKeyframes {
    private struct Point {
        let progress: Double
        let xVW: CGFloat
        let yVH: CGFloat
        let scale: CGFloat
        let color: RGBA
    }

    private static let points: [Point] = [
        Point(progress: 0.00, xVW: -0.12, yVH: -0.08, scale: 1.00, color: .sunset),
        Point(progress: 0.25, xVW: 0.30, yVH: 0.12, scale: 1.16, color: .aqua),
        Point(progress: 0.50, xVW: 0.15, yVH: 0.40, scale: 0.92, color: .citrus),
        Point(progress: 0.75, xVW: -0.24, yVH: 0.20, scale: 1.08, color: .ember),
        Point(progress: 1.00, xVW: -0.12, yVH: -0.08, scale: 1.00, color: .sunset)
    ]

    static func interpolate(progress rawProgress: Double) -> OrbKeyframeState {
        let progress = min(max(rawProgress, 0.0), 1.0)

        guard let endIndex = points.firstIndex(where: { progress <= $0.progress }) else {
            return toState(points[points.count - 1])
        }

        if endIndex == 0 {
            return toState(points[0])
        }

        let start = points[endIndex - 1]
        let end = points[endIndex]
        let span = max(end.progress - start.progress, 0.0001)
        let local = (progress - start.progress) / span
        let eased = smoothStep(local)

        let x = lerp(start.xVW, end.xVW, eased)
        let y = lerp(start.yVH, end.yVH, eased)
        let scale = lerp(start.scale, end.scale, eased)
        let color = RGBA.lerp(start.color, end.color, eased).toColor()

        return OrbKeyframeState(xVW: x, yVH: y, scale: scale, color: color)
    }

    private static func toState(_ point: Point) -> OrbKeyframeState {
        OrbKeyframeState(
            xVW: point.xVW,
            yVH: point.yVH,
            scale: point.scale,
            color: point.color.toColor()
        )
    }

    private static func smoothStep(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }

    private static func lerp(_ start: CGFloat, _ end: CGFloat, _ t: Double) -> CGFloat {
        start + (end - start) * CGFloat(t)
    }
}

private struct RGBA {
    let r: Double
    let g: Double
    let b: Double

    static let sunset = RGBA(r: 248 / 255, g: 158 / 255, b: 63 / 255)
    static let aqua = RGBA(r: 31 / 255, g: 199 / 255, b: 184 / 255)
    static let citrus = RGBA(r: 146 / 255, g: 213 / 255, b: 84 / 255)
    static let ember = RGBA(r: 231 / 255, g: 101 / 255, b: 76 / 255)

    static func lerp(_ start: RGBA, _ end: RGBA, _ t: Double) -> RGBA {
        let clamped = min(max(t, 0), 1)
        return RGBA(
            r: start.r + (end.r - start.r) * clamped,
            g: start.g + (end.g - start.g) * clamped,
            b: start.b + (end.b - start.b) * clamped
        )
    }

    func toColor() -> Color {
        Color(red: r, green: g, blue: b)
    }
}

#Preview {
    OnboardingAnimatedBackground()
}
