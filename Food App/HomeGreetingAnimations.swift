//
//  HomeGreetingAnimations.swift
//  Food App
//
//  Premium animation set for the home-screen greeting chip.
//  12 cases total: 11 base animations across 4 time-of-day slots + 1
//  milestone override. Selection is deterministic per (user, day, slot)
//  so the animation stays stable within a slot, varies across days, and
//  varies between users.
//
//  Implementation notes:
//  - Each animation respects `accessibilityReduceMotion`.
//  - Looping is driven by `.task { while !cancelled }` with explicit
//    `withAnimation { … }` blocks per stage. This is preferred over
//    `.repeatForever` for any animation with more than one stage,
//    because we get smooth, interruption-safe motion that pauses cleanly
//    when the view leaves the hierarchy.
//  - Frame is locked at 22×22 inside a 24×24 GreetingAnimationView. The
//    chip's text + chevron sit next to that frame.
//

import SwiftUI

// MARK: - Animation enum

enum GreetingAnimation: String, CaseIterable, Identifiable {
    // anytime (11:00–18:00)
    case wave, peek, dog
    // evening (18:00–21:00)
    case heart, sparkle, sprout
    // morning (05:00–11:00)
    case coffee, pancakes, sun
    // night (21:00–05:00)
    case zzz, moon
    // milestone override
    case confetti

    var id: String { rawValue }
}

// MARK: - Slot

enum GreetingSlot: String, CaseIterable {
    case morning, anytime, evening, night, milestone

    var pool: [GreetingAnimation] {
        switch self {
        case .morning:   return [.coffee, .pancakes, .sun]
        case .anytime:   return [.wave, .peek, .dog]
        case .evening:   return [.heart, .sparkle, .sprout]
        case .night:     return [.zzz, .moon]
        case .milestone: return [.confetti]
        }
    }

    /// Greeting word that pairs with this slot's mood.
    var greetingPrefix: String {
        switch self {
        case .morning:   return "Good morning"
        case .anytime:   return "Hey"
        case .evening:   return "Evening"
        case .night:     return "Good night"
        case .milestone: return "Nice"
        }
    }
}

// MARK: - Resolver

enum GreetingAnimationResolver {
    /// Hour-of-day → slot. Boundaries: 5/11/18/21.
    static func currentSlot(date: Date = Date(), calendar: Calendar = .current) -> GreetingSlot {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<11:   return .morning
        case 11..<18:  return .anytime
        case 18..<21:  return .evening
        default:       return .night    // 21–24 and 0–5
        }
    }

    /// Deterministic per (user, day, slot). Hash isn't crypto-strong on
    /// purpose — we just want a stable, spread-out index. The seed string
    /// changes when any of (user, day, slot) changes.
    static func resolve(
        userId: String?,
        date: Date = Date(),
        hasMilestone: Bool = false,
        calendar: Calendar = .current
    ) -> (slot: GreetingSlot, animation: GreetingAnimation) {
        if hasMilestone {
            return (.milestone, .confetti)
        }
        let slot = currentSlot(date: date, calendar: calendar)
        let pool = slot.pool
        guard !pool.isEmpty else { return (slot, .wave) }

        let dateString = dailySeedFormatter.string(from: date)
        let seed = "\(userId ?? "anon")-\(dateString)-\(slot.rawValue)"
        // Foundation `hashValue` varies per-launch in Swift — that's the
        // OPPOSITE of what we want. Roll a simple stable hash so the
        // animation stays the same across launches in a single slot.
        var hash: UInt64 = 5381
        for byte in seed.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        let index = Int(hash % UInt64(pool.count))
        return (slot, pool[index])
    }

    private static let dailySeedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Dispatch view

/// Renders the selected animation in a 24×24 frame. Used inside the
/// greeting chip; can be reused anywhere a single greeting animation is
/// needed.
struct GreetingAnimationView: View {
    let animation: GreetingAnimation

    var body: some View {
        Group {
            switch animation {
            case .wave:     WaveAnimation()
            case .peek:     PeekAnimation()
            case .dog:      DogAnimation()
            case .heart:    HeartAnimation()
            case .sparkle:  SparkleAnimation()
            case .sprout:   SproutAnimation()
            case .coffee:   CoffeeAnimation()
            case .pancakes: PancakeAnimation()
            case .sun:      SunAnimation()
            case .zzz:      SleepyAnimation()
            case .moon:     MoonAnimation()
            case .confetti: ConfettiAnimation()
            }
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Shimmer text

/// Text with a warm gold highlight that sweeps across once every
/// `cycleDuration` seconds. Sweep takes 2s, then sits idle for the
/// remainder of the cycle.
struct ShimmerText: View {
    let text: String
    let baseColor: Color
    var highlightColor: Color = Color(red: 1.00, green: 0.66, blue: 0.05)
    var cycleDuration: Double = 12
    var sweepDuration: Double = 2

    @State private var startTime = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Text(text).foregroundStyle(baseColor)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                let elapsed = context.date.timeIntervalSince(startTime)
                let cycle = elapsed.truncatingRemainder(dividingBy: cycleDuration)

                // Sweep maps phase from -1 → 1 over the sweep window.
                // After the sweep, phase stays at 1 (highlight off-screen
                // to the right; text reads as solid baseColor).
                let sweepT = min(max(cycle / sweepDuration, 0), 1)
                // Smoothstep ease — symmetric, gentle entry and exit.
                let eased = sweepT * sweepT * (3 - 2 * sweepT)
                let phase = -1 + eased * 2

                Text(text)
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: baseColor, location: 0),
                                .init(color: baseColor, location: 0.35),
                                .init(color: highlightColor, location: 0.5),
                                .init(color: baseColor, location: 0.65),
                                .init(color: baseColor, location: 1.0),
                            ],
                            startPoint: UnitPoint(x: phase, y: 0.5),
                            endPoint: UnitPoint(x: phase + 1.0, y: 0.5)
                        )
                    )
            }
        }
    }
}

// MARK: - 1. Wave

private struct WaveAnimation: View {
    @State private var rotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("👋")
            .font(.system(size: 20))
            .saturation(1.15)
            .rotationEffect(.degrees(rotation), anchor: .bottomTrailing)
            .onAppear { startAnimation() }
            .onChange(of: reduceMotion) { _, _ in
                rotation = 0
                startAnimation()
            }
    }

    private func startAnimation() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
            rotation = 18
        }
    }
}

// MARK: - 2. Peek-a-boo

private struct PeekAnimation: View {
    @State private var offsetY: CGFloat = 22
    @State private var wiggleX: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let skinHighlight = Color(red: 1.00, green: 0.79, blue: 0.55)
    private let skinMid       = Color(red: 1.00, green: 0.67, blue: 0.43)
    private let skinShadow    = Color(red: 0.90, green: 0.55, blue: 0.27)
    private let cheekColor    = Color(red: 0.96, green: 0.48, blue: 0.43)

    var body: some View {
        ZStack {
            face
                .offset(x: wiggleX, y: offsetY)
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task { await loop() }
        .onChange(of: reduceMotion) { _, _ in offsetY = reduceMotion ? -2 : 22 }
    }

    private var face: some View {
        ZStack {
            // Head — clay-mation feel via radial gradient + drop shadow
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [skinHighlight, skinMid, skinShadow],
                        center: UnitPoint(x: 0.32, y: 0.30),
                        startRadius: 1,
                        endRadius: 14
                    )
                )
                .frame(width: 20, height: 20)
                .shadow(color: Color(red: 0.5, green: 0.25, blue: 0.1).opacity(0.18),
                        radius: 1.5, x: 0, y: 1)

            // Cheeks — soft blurred blush
            HStack(spacing: 9) {
                Ellipse()
                    .fill(cheekColor)
                    .frame(width: 3.5, height: 2.5)
                    .opacity(0.55)
                    .blur(radius: 0.6)
                Ellipse()
                    .fill(cheekColor)
                    .frame(width: 3.5, height: 2.5)
                    .opacity(0.55)
                    .blur(radius: 0.6)
            }
            .offset(y: 2.5)

            // Eyes — black with subtle white highlight
            HStack(spacing: 5.5) {
                eye
                eye
            }
            .offset(y: -2)

            // Smile
            SmileShape()
                .stroke(Color.black.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                .frame(width: 8, height: 3)
                .offset(y: 5)
        }
    }

    private var eye: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.88))
                .frame(width: 3, height: 3)
            Circle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 1, height: 1)
                .offset(x: 0.4, y: -0.4)
        }
    }

    private func loop() async {
        guard !reduceMotion else {
            offsetY = -2
            return
        }

        // === Initial appearance — pop up + first-time wiggle ===
        withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
            offsetY = -2
        }
        try? await Task.sleep(for: .seconds(0.5))

        withAnimation(.easeInOut(duration: 0.28)) { wiggleX = 2 }
        try? await Task.sleep(for: .seconds(0.28))
        withAnimation(.easeInOut(duration: 0.32)) { wiggleX = -2 }
        try? await Task.sleep(for: .seconds(0.32))
        withAnimation(.easeInOut(duration: 0.28)) { wiggleX = 0 }

        // === Stay visible at rest. Every 30s, do a quick peek-a-boo
        // gesture (dip down + pop back up). The dip is brisk so the
        // chip is effectively never empty for more than ~0.4s. ===
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))

            // Dip down (fast, then immediately rebound)
            withAnimation(.easeIn(duration: 0.28)) { offsetY = 22 }
            try? await Task.sleep(for: .seconds(0.28))

            // Pop back up with a springy overshoot
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                offsetY = -2
            }
            try? await Task.sleep(for: .seconds(0.6))
        }
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: 0),
            control: CGPoint(x: rect.width / 2, y: rect.height * 1.4)
        )
        return path
    }
}

// MARK: - 3. Dog wag

private struct DogAnimation: View {
    @State private var headBob: Double = -3
    @State private var tailAngle: Double = -30
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Tail (wags faster than head)
            DogTailShape()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.55, green: 0.36, blue: 0.18),
                                 Color(red: 0.42, green: 0.27, blue: 0.12)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 10, height: 6)
                .rotationEffect(.degrees(tailAngle), anchor: .leading)
                .offset(x: 5, y: -2)

            // Head bobs gently
            Image(systemName: "dog.fill")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.72, green: 0.50, blue: 0.27),
                                 Color(red: 0.55, green: 0.36, blue: 0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .rotationEffect(.degrees(headBob), anchor: .bottom)
                .offset(y: 1)
        }
        .frame(width: 24, height: 24)
        .onAppear { startAnimation() }
        .onChange(of: reduceMotion) { _, _ in
            headBob = 0
            tailAngle = 0
            startAnimation()
        }
    }

    private func startAnimation() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            headBob = 3
        }
        withAnimation(.easeInOut(duration: 0.12).repeatForever(autoreverses: true)) {
            tailAngle = 35
        }
    }
}

private struct DogTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 0, y: h * 0.6))
        path.addQuadCurve(to: CGPoint(x: w, y: 0),
                          control: CGPoint(x: w * 0.5, y: -h * 0.1))
        path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.4))
        path.addQuadCurve(to: CGPoint(x: 0, y: h),
                          control: CGPoint(x: w * 0.4, y: h))
        path.closeSubpath()
        return path
    }
}

// MARK: - 4. Heart pulse

private struct HeartAnimation: View {
    @State private var scale: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 1.00, green: 0.45, blue: 0.36),
                             Color(red: 1.00, green: 0.27, blue: 0.20)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: Color(red: 1.00, green: 0.37, blue: 0.28).opacity(0.45),
                    radius: 2.5, x: 0, y: 0)
            .scaleEffect(scale)
            .task { await pulse() }
            .onChange(of: reduceMotion) { _, _ in scale = 1.0 }
    }

    private func pulse() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                scale = 1.25
            }
            try? await Task.sleep(for: .seconds(0.15))
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                scale = 1.05
            }
            try? await Task.sleep(for: .seconds(0.12))
            withAnimation(.spring(response: 0.16, dampingFraction: 0.55)) {
                scale = 1.22
            }
            try? await Task.sleep(for: .seconds(0.18))
            withAnimation(.easeOut(duration: 0.32)) {
                scale = 1.0
            }
            try? await Task.sleep(for: .seconds(0.5))
        }
    }
}

// MARK: - 5. Sparkle

private struct SparkleAnimation: View {
    @State private var scale: Double = 0.9
    @State private var opacity: Double = 0.8
    @State private var rotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 1.00, green: 0.87, blue: 0.36),
                             Color(red: 1.00, green: 0.69, blue: 0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: Color(red: 1.00, green: 0.69, blue: 0.0).opacity(0.5),
                    radius: 2, x: 0, y: 0)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .onAppear { startAnimation() }
            .onChange(of: reduceMotion) { _, _ in
                scale = 1.0; opacity = 1.0; rotation = 0
                startAnimation()
            }
    }

    private func startAnimation() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            scale = 1.18
            opacity = 1.0
        }
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

// MARK: - 6. Sprout

private struct SproutAnimation: View {
    @State private var stemHeight: CGFloat = 0
    @State private var leafScale: CGFloat = 0
    @State private var leafOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Soil bump
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.42, green: 0.31, blue: 0.20),
                                 Color(red: 0.29, green: 0.21, blue: 0.13)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 18, height: 3)
                .offset(y: 10)

            // Stem grows up
            RoundedRectangle(cornerRadius: 1)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.55, green: 0.81, blue: 0.36),
                                 Color(red: 0.40, green: 0.66, blue: 0.22)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2, height: max(stemHeight, 0.01))
                .offset(y: 8.5 - stemHeight / 2)

            // Leaves
            HStack(spacing: 1) {
                LeafShape()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.66, green: 0.86, blue: 0.42),
                                     Color(red: 0.40, green: 0.66, blue: 0.22)],
                            center: UnitPoint(x: 0.3, y: 0.4),
                            startRadius: 0,
                            endRadius: 5
                        )
                    )
                    .frame(width: 7, height: 5)
                    .scaleEffect(x: -1, y: 1)
                    .scaleEffect(leafScale, anchor: .trailing)
                    .opacity(leafOpacity)
                LeafShape()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.66, green: 0.86, blue: 0.42),
                                     Color(red: 0.40, green: 0.66, blue: 0.22)],
                            center: UnitPoint(x: 0.3, y: 0.4),
                            startRadius: 0,
                            endRadius: 5
                        )
                    )
                    .frame(width: 7, height: 5)
                    .scaleEffect(leafScale, anchor: .leading)
                    .opacity(leafOpacity)
            }
            .offset(y: 0)
        }
        .frame(width: 24, height: 24)
        .task { await loop() }
    }

    private func loop() async {
        guard !reduceMotion else {
            stemHeight = 12; leafScale = 1; leafOpacity = 1
            return
        }

        // === Initial grow (once): stem extends, leaves unfurl, hold. ===
        withAnimation(.easeInOut(duration: 0.9)) { stemHeight = 12 }
        try? await Task.sleep(for: .seconds(0.65))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) { leafScale = 1 }
        withAnimation(.easeOut(duration: 0.4)) { leafOpacity = 1 }

        // === Stay fully grown. Every 30s, the leaves squish briefly
        // and spring back — like a tiny breath. Stem + leaves remain
        // visible the whole time. ===
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            withAnimation(.easeInOut(duration: 0.25)) { leafScale = 0.78 }
            try? await Task.sleep(for: .seconds(0.25))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { leafScale = 1 }
            try? await Task.sleep(for: .seconds(0.5))
        }
    }
}

private struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w, y: h))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: 0),
            control: CGPoint(x: 0, y: h * 0.85)
        )
        path.addQuadCurve(
            to: CGPoint(x: w, y: h),
            control: CGPoint(x: w, y: h * 0.15)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - 7. Coffee + steam

private struct CoffeeAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SteamWisp(delay: 0)   .offset(x: -4, y: -7)
            SteamWisp(delay: 0.55).offset(x:  0, y: -7)
            SteamWisp(delay: 1.10).offset(x:  4, y: -7)

            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.60, green: 0.42, blue: 0.24),
                                 Color(red: 0.42, green: 0.27, blue: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .offset(y: 3)
        }
        .frame(width: 24, height: 24)
    }
}

private struct SteamWisp: View {
    let delay: Double
    @State private var offsetY: CGFloat = 4
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(Color(red: 0.55, green: 0.41, blue: 0.27).opacity(0.7))
            .frame(width: 1.6, height: 5)
            .blur(radius: 0.5)
            .offset(y: offsetY)
            .opacity(opacity)
            .task {
                try? await Task.sleep(for: .seconds(delay))
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    offsetY = 4
                    opacity = 0
                    withAnimation(.easeOut(duration: 0.3)) { opacity = 0.85 }
                    withAnimation(.linear(duration: 1.65)) { offsetY = -8 }
                    try? await Task.sleep(for: .seconds(1.25))
                    withAnimation(.easeIn(duration: 0.4)) { opacity = 0 }
                    try? await Task.sleep(for: .seconds(0.4))
                }
            }
    }
}

// MARK: - 8. Pancake stack

private struct PancakeAnimation: View {
    var body: some View {
        ZStack {
            Pancake(restingY: 7,  delay: 0.00)
            Pancake(restingY: 3,  delay: 0.35)
            Pancake(restingY: -1, delay: 0.70)
            Syrup(delay: 1.10)
        }
        .frame(width: 24, height: 24)
    }
}

private struct Pancake: View {
    let restingY: CGFloat
    let delay: Double

    @State private var translateY: CGFloat = -14
    @State private var scaleX: CGFloat = 0.6
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.96, green: 0.69, blue: 0.38),
                             Color(red: 0.79, green: 0.48, blue: 0.24)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 18, height: 4)
            .offset(y: translateY)
            .scaleEffect(x: scaleX, y: 1)
            .opacity(opacity)
            .task {
                guard !reduceMotion else {
                    translateY = restingY; scaleX = 1; opacity = 1
                    return
                }

                // === Initial drop (once): pancake falls into the stack. ===
                try? await Task.sleep(for: .seconds(delay))
                withAnimation(.easeOut(duration: 0.25)) { opacity = 1 }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                    translateY = restingY
                    scaleX = 1.12
                }
                try? await Task.sleep(for: .seconds(0.35))
                withAnimation(.easeOut(duration: 0.15)) { scaleX = 1.0 }

                // === Stack stays visible. Each pancake squishes briefly
                // every 30s, staggered by its delay so the whole stack
                // does a small wave. ===
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    withAnimation(.easeInOut(duration: 0.18)) { scaleX = 1.12 }
                    try? await Task.sleep(for: .seconds(0.18))
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.5)) { scaleX = 1.0 }
                    try? await Task.sleep(for: .seconds(0.5))
                }
            }
    }
}

private struct Syrup: View {
    let delay: Double
    @State private var scaleY: CGFloat = 0
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.37, green: 0.21, blue: 0.09),
                             Color(red: 0.25, green: 0.14, blue: 0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 10, height: 4)
            .offset(y: -3)
            .scaleEffect(y: scaleY, anchor: .top)
            .opacity(opacity)
            .task {
                guard !reduceMotion else { scaleY = 1; opacity = 1; return }

                // === Initial pour (once) ===
                try? await Task.sleep(for: .seconds(delay))
                withAnimation(.easeOut(duration: 0.5)) {
                    scaleY = 1
                    opacity = 1
                }

                // === Stays visible. Brief drip pulse every 30s. ===
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    withAnimation(.easeInOut(duration: 0.22)) { scaleY = 0.82 }
                    try? await Task.sleep(for: .seconds(0.22))
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { scaleY = 1.0 }
                    try? await Task.sleep(for: .seconds(0.5))
                }
            }
    }
}

// MARK: - 9. Rising sun

private struct SunAnimation: View {
    @State private var offsetY: CGFloat = 13
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "sun.max.fill")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 1.00, green: 0.88, blue: 0.54),
                             Color(red: 1.00, green: 0.76, blue: 0.28),
                             Color(red: 1.00, green: 0.56, blue: 0.24)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: Color(red: 1.00, green: 0.71, blue: 0.31).opacity(0.55),
                    radius: 2.5, x: 0, y: 0)
            .offset(y: offsetY)
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .task { await loop() }
    }

    private func loop() async {
        guard !reduceMotion else { offsetY = 0; return }

        // === Initial rise (once) — sun comes up over the horizon ===
        withAnimation(.easeOut(duration: 1.5)) { offsetY = 0 }

        // === Stay up. Every 30s, a brief dip-and-bounce so the sun
        // looks alive without ever leaving the chip empty. ===
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))

            // Small dip below the resting position
            withAnimation(.easeInOut(duration: 0.28)) { offsetY = 5 }
            try? await Task.sleep(for: .seconds(0.28))

            // Spring back up
            withAnimation(.spring(response: 0.42, dampingFraction: 0.5)) { offsetY = 0 }
            try? await Task.sleep(for: .seconds(0.5))
        }
    }
}

// MARK: - 10. Sleepy z's

private struct SleepyAnimation: View {
    var body: some View {
        ZStack {
            SleepyZ(size: 9,  xOffset: -7, delay: 0.0)
            SleepyZ(size: 11, xOffset:  0, delay: 0.85)
            SleepyZ(size: 14, xOffset:  6, delay: 1.70)
        }
        .frame(width: 24, height: 24)
    }
}

private struct SleepyZ: View {
    let size: CGFloat
    let xOffset: CGFloat
    let delay: Double

    @State private var offsetY: CGFloat = 4
    @State private var rotation: Double = -8
    @State private var scale: Double = 0.7
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("z")
            .font(.system(size: size, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 0.69, green: 0.50, blue: 0.88),
                             Color(red: 0.54, green: 0.37, blue: 0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: Color(red: 0.43, green: 0.33, blue: 0.54).opacity(0.20),
                    radius: 0, x: 0, y: 1)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .offset(x: xOffset, y: offsetY)
            .opacity(opacity)
            .task {
                try? await Task.sleep(for: .seconds(delay))
                guard !reduceMotion else { opacity = 1; offsetY = 0; rotation = 0; scale = 1; return }
                while !Task.isCancelled {
                    offsetY = 4
                    rotation = -8
                    scale = 0.7
                    opacity = 0
                    withAnimation(.easeOut(duration: 0.35)) { opacity = 1 }
                    withAnimation(.linear(duration: 2.4)) {
                        offsetY = -11
                        rotation = 10
                        scale = 1.15
                    }
                    try? await Task.sleep(for: .seconds(2.0))
                    withAnimation(.easeIn(duration: 0.4)) { opacity = 0 }
                    try? await Task.sleep(for: .seconds(0.2))
                }
            }
    }
}

// MARK: - 11. Moon & stars

private struct MoonAnimation: View {
    @State private var offsetY: CGFloat = 13
    @State private var twinkle: Double = 0.4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "moon.stars.fill")
            .font(.system(size: 18, weight: .medium))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                Color(red: 0.99, green: 0.95, blue: 0.78),  // moon
                Color(red: 1.00, green: 0.85, blue: 0.36)   // stars
            )
            .shadow(color: Color(red: 1.00, green: 0.93, blue: 0.55).opacity(0.55),
                    radius: 2.5, x: 0, y: 0)
            .opacity(0.7 + twinkle * 0.3)
            .offset(y: offsetY)
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .task { await loop() }
    }

    private func loop() async {
        guard !reduceMotion else { offsetY = 0; twinkle = 1.0; return }
        // Start twinkle immediately; rise/set on its own cadence.
        Task {
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 1.0)) { twinkle = 1.0 }
                try? await Task.sleep(for: .seconds(1.0))
                withAnimation(.easeInOut(duration: 1.0)) { twinkle = 0.4 }
                try? await Task.sleep(for: .seconds(1.0))
            }
        }
        // === Initial rise (once) ===
        withAnimation(.easeOut(duration: 1.7)) { offsetY = 0 }

        // === Stay up. Brief dip + spring back every 30s so the moon
        // is always visible but periodically reasserts itself. ===
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            withAnimation(.easeInOut(duration: 0.3)) { offsetY = 5 }
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { offsetY = 0 }
            try? await Task.sleep(for: .seconds(0.5))
        }
    }
}

// MARK: - 12. Confetti (milestone)

private struct ConfettiAnimation: View {
    private let bits: [ConfettiBit.Spec] = [
        .init(color: Color(red: 1.00, green: 0.37, blue: 0.28),  dx: -10, dy: -8,  rotation: -75, delay: 0.00, shape: .square),
        .init(color: Color(red: 1.00, green: 0.69, blue: 0.00),  dx:  10, dy: -8,  rotation:  85, delay: 0.05, shape: .rect),
        .init(color: Color(red: 0.42, green: 0.69, blue: 0.90),  dx: -12, dy:  3,  rotation: -135, delay: 0.10, shape: .circle),
        .init(color: Color(red: 0.40, green: 0.66, blue: 0.22),  dx:  12, dy:  3,  rotation: 130, delay: 0.15, shape: .square),
        .init(color: Color(red: 0.70, green: 0.53, blue: 0.88),  dx:   0, dy: -11, rotation:  15, delay: 0.03, shape: .rect),
        .init(color: Color(red: 1.00, green: 0.65, blue: 0.59),  dx:  -7, dy: -11, rotation: -45, delay: 0.08, shape: .circle),
        .init(color: Color(red: 1.00, green: 0.83, blue: 0.32),  dx:   7, dy: -11, rotation:  60, delay: 0.12, shape: .square),
        .init(color: Color(red: 0.53, green: 0.78, blue: 0.36),  dx:  -3, dy:  6,  rotation: -15, delay: 0.18, shape: .rect),
    ]

    var body: some View {
        ZStack {
            ForEach(0..<bits.count, id: \.self) { i in
                ConfettiBit(spec: bits[i])
            }
        }
        .frame(width: 24, height: 24)
    }
}

private struct ConfettiBit: View {
    enum Shape { case square, rect, circle }
    struct Spec {
        let color: Color
        let dx: CGFloat
        let dy: CGFloat
        let rotation: Double
        let delay: Double
        let shape: Shape
    }

    let spec: Spec

    @State private var offsetX: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 2026-05-23: bitShape returns `some View` via @ViewBuilder so
        // `.fill` (a Shape-only modifier) doesn't compile. Tint via
        // foregroundStyle instead — works the same visually for these
        // single-color confetti bits.
        bitShape
            .foregroundStyle(spec.color)
            .frame(width: spec.shape == .rect ? 5 : 4,
                   height: spec.shape == .rect ? 2 : 4)
            .offset(x: offsetX, y: offsetY)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .task {
                guard !reduceMotion else { opacity = 1; return }
                while !Task.isCancelled {
                    offsetX = 0
                    offsetY = 0
                    rotation = 0
                    opacity = 0
                    try? await Task.sleep(for: .seconds(spec.delay))

                    withAnimation(.easeOut(duration: 0.12)) { opacity = 1 }
                    withAnimation(.easeOut(duration: 1.4)) {
                        offsetX = spec.dx
                        offsetY = spec.dy + 4   // gravity bias on exit
                        rotation = spec.rotation
                    }
                    try? await Task.sleep(for: .seconds(0.9))
                    withAnimation(.easeIn(duration: 0.5)) { opacity = 0 }
                    try? await Task.sleep(for: .seconds(max(0.05, 1.4 - spec.delay)))
                }
            }
    }

    @ViewBuilder
    private var bitShape: some View {
        switch spec.shape {
        case .square: RoundedRectangle(cornerRadius: 1, style: .continuous)
        case .rect:   RoundedRectangle(cornerRadius: 1, style: .continuous)
        case .circle: Circle()
        }
    }
}
