import SwiftUI
import Combine
import CoreMotion

// MARK: - Why this works (3D carousel redesign, 2026-05-31)
//
// Replaces the old vertical card list with a slowly auto-rotating 3D ring of
// feature cards (one in focus at a time; side/back cards blur + dim for depth).
// Intro choreography is preserved: the heading types itself out, then the cards
// spring into the ring, then the ring starts spinning. Hold anywhere on the
// carousel to pause it. Reduce Motion presents a static ring with no spin.
//
// Ported from the HTML exploration (onboarding-why-this-works-carousel.html).
// First SwiftUI pass — expect to iterate on feel.

struct OB02eHowItWorksScreen: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let headingText = "Why this works"
    private let features = WhyFeature.all

    // Intro choreography
    @State private var typedCount = 0
    @State private var showCaret = false
    @State private var cardsRevealed = false
    @State private var nextVisible = false
    @State private var introComplete = false
    @State private var skipRequested = false

    // Spin state (continuous rotation driven by TimelineView elapsed time).
    @State private var spinning = false
    @State private var spinStart: TimeInterval = 0
    @State private var pausedAccum: TimeInterval = 0
    @State private var pauseStart: TimeInterval = 0
    @State private var isPaused = false

    // Manual swipe rotation (added on top of the auto-spin angle).
    @State private var manualAngle: Double = 0
    @State private var dragStartManual: Double = 0
    @State private var dragStartAuto: Double = 0
    @State private var lastFrontIndex = 0

    // Device-motion parallax.
    @StateObject private var parallax = ParallaxMotion()

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                // Placeholder app-icon mark above the heading. Loads the current
                // app icon at runtime today; swap for the updated icon later.
                AppIconBadge()
                    .padding(.top, 8)

                TypewriterHeading(
                    fullText: headingText,
                    typedCount: typedCount,
                    showCaret: showCaret
                )
                .padding(.horizontal, 24)
                .padding(.top, 14)

                Spacer(minLength: 8)

                carousel

                Spacer(minLength: 8)

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
                .opacity(nextVisible ? 1 : 0)
                .allowsHitTesting(nextVisible)
                .padding(.bottom, 24)
            }

            if !introComplete {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { skipIntro() }
                    .ignoresSafeArea()
            }
        }
        .task { await runIntro() }
        .onAppear { if !reduceMotion { parallax.start() } }
        .onDisappear { parallax.stop() }
    }

    // MARK: - Carousel

    private var carousel: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !spinning || reduceMotion)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let active = spinning
                ? max(0, now - spinStart - pausedAccum - (isPaused ? (now - pauseStart) : 0))
                : 0
            let rotation = -WhyCarousel.speed * active + manualAngle

            VStack(spacing: 20) {
                ZStack {
                    ForEach(features) { feature in
                        let theta = rotation + Double(feature.id) * WhyCarousel.step
                        let depth = cos(theta * .pi / 180)
                        WhyCarouselCard(feature: feature, front: depth >= -0.05)
                            .modifier(RingPlacement(
                                theta: theta,
                                index: feature.id,
                                revealed: cardsRevealed,
                                reduceMotion: reduceMotion,
                                tiltX: parallax.tiltX,
                                tiltY: parallax.tiltY
                            ))
                    }
                }
                .frame(height: WhyCarousel.cardH + 18)

                pageDots(front: frontIndex(rotation))
                    .opacity(cardsRevealed ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private func pageDots(front: Int) -> some View {
        HStack(spacing: 9) {
            ForEach(0..<features.count, id: \.self) { i in
                Capsule()
                    .fill(i == front
                          ? OnboardingGlassTheme.accentStart
                          : OnboardingGlassTheme.textPrimary.opacity(0.18))
                    .frame(width: i == front ? 16 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.4), value: front)
            }
        }
    }

    /// Index of the card closest to facing the viewer (largest cos).
    private func frontIndex(_ rotation: Double) -> Int {
        var best = 0
        var bestCos = -2.0
        for i in 0..<features.count {
            let c = cos((rotation + Double(i) * WhyCarousel.step) * .pi / 180)
            if c > bestCos { bestCos = c; best = i }
        }
        return best
    }

    /// One gesture does both jobs: a still press pauses the auto-spin; a drag
    /// rotates the ring by hand. A haptic fires each time a new card reaches the
    /// front. On release the auto-spin resumes from the new position.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard introComplete else { return }
                if !isPaused {
                    isPaused = true
                    let t = Date().timeIntervalSinceReferenceDate
                    pauseStart = t
                    dragStartManual = manualAngle
                    dragStartAuto = spinning ? (-WhyCarousel.speed * max(0, t - spinStart - pausedAccum)) : 0
                    lastFrontIndex = frontIndex(dragStartAuto + dragStartManual)
                }
                manualAngle = dragStartManual + Double(value.translation.width) * WhyCarousel.dragSensitivity
                let fi = frontIndex(dragStartAuto + manualAngle)
                if fi != lastFrontIndex {
                    lastFrontIndex = fi
                    AppHaptics.softImpact(intensity: 0.6)   // per-card feedback while swiping
                }
            }
            .onEnded { _ in
                guard isPaused else { return }
                pausedAccum += Date().timeIntervalSinceReferenceDate - pauseStart
                isPaused = false
            }
    }

    // MARK: - Top Bar

    private var topBar: some View {
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
        .frame(height: 44)
    }

    // MARK: - Intro choreography

    @MainActor
    private func runIntro() async {
        if reduceMotion {
            typedCount = headingText.count
            cardsRevealed = true
            nextVisible = true
            spinning = false       // static ring, no spin
            introComplete = true
            return
        }

        func stillRunning() -> Bool { !Task.isCancelled && !skipRequested }

        await sleep(0.45)
        guard stillRunning() else { return }

        showCaret = true
        let chars = Array(headingText)
        for index in 1...chars.count {
            guard stillRunning() else { return }
            typedCount = index
            if chars[index - 1] != " " { AppHaptics.softImpact(intensity: 0.5) }
            await sleep(chars[index - 1] == " " ? 0.092 : 0.06)
        }

        guard stillRunning() else { return }
        await sleep(0.55)
        showCaret = false
        AppHaptics.mediumImpact()

        // Cards spring into the ring (RingPlacement staggers per index).
        withAnimation { cardsRevealed = true }
        await sleep(0.7)
        guard stillRunning() else { return }

        withAnimation(.easeOut(duration: 0.4)) { nextVisible = true }
        beginSpin()
        introComplete = true
    }

    @MainActor
    private func skipIntro() {
        guard !introComplete else { return }
        skipRequested = true
        showCaret = false
        withAnimation(.easeOut(duration: 0.3)) {
            typedCount = headingText.count
            cardsRevealed = true
            nextVisible = true
        }
        if !reduceMotion { beginSpin() }
        introComplete = true
    }

    private func beginSpin() {
        spinStart = Date().timeIntervalSinceReferenceDate
        pausedAccum = 0
        isPaused = false
        spinning = true
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Carousel geometry

private enum WhyCarousel {
    static let cardW: CGFloat = 188
    static let cardH: CGFloat = 252
    static let radius: CGFloat = 208   // wide enough that neighbours clear the front card
    static let step: Double = 60       // 360 / 6 cards
    static let speed: Double = 11      // degrees per second
    static let dragSensitivity: Double = 0.55  // degrees of ring rotation per point dragged
    static let parallaxAmplitude: CGFloat = 16 // max points a front card shifts on full tilt
}

// MARK: - Device-motion parallax

/// Publishes a smoothed, normalized tilt (-1...1 on each axis) relative to the
/// device's attitude when updates began, so the carousel can parallax-shift as
/// the phone moves. No-op (and never started) under Reduce Motion.
private final class ParallaxMotion: ObservableObject {
    @Published var tiltX: Double = 0   // roll (left/right)
    @Published var tiltY: Double = 0   // pitch (up/down)

    private let manager = CMMotionManager()
    private var reference: CMAttitude?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let attitude = motion.attitude
            guard let reference = self.reference else {
                self.reference = attitude.copy() as? CMAttitude
                return
            }
            attitude.multiply(byInverseOf: reference)          // relative to start
            let targetX = max(-1, min(1, attitude.roll / 0.6))
            let targetY = max(-1, min(1, attitude.pitch / 0.6))
            self.tiltX += (targetX - self.tiltX) * 0.12         // low-pass smoothing
            self.tiltY += (targetY - self.tiltY) * 0.12
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        reference = nil
        tiltX = 0
        tiltY = 0
    }
}

// MARK: - Feature model

private struct WhyFeature: Identifiable {
    let id: Int
    let number: String
    let title: String
    let subtitle: String
    let kind: Kind

    enum Kind { case type, photo, progress, recipe, importWeb, widget }

    static let all: [WhyFeature] = [
        .init(id: 0, number: "01", title: "Type anything",
              subtitle: "Instant calories & macros from plain words.", kind: .type),
        .init(id: 1, number: "02", title: "Take a food photo",
              subtitle: "Snap a picture — we’ll log the rest.", kind: .photo),
        .init(id: 2, number: "03", title: "Track your progress",
              subtitle: "See your daily progress and trends.", kind: .progress),
        .init(id: 3, number: "04", title: "Curated recipes",
              subtitle: "Hand-picked meals that hit your targets.", kind: .recipe),
        .init(id: 4, number: "05", title: "Import from the web",
              subtitle: "A link from a site, Instagram, or TikTok.", kind: .importWeb),
        .init(id: 5, number: "06", title: "Add a widget later",
              subtitle: "Home & Lock Screen shortcuts keep logging close.", kind: .widget),
    ]
}

// MARK: - Ring placement modifier

/// Positions a card on the rotating ring: horizontal arc offset, depth-based
/// scale/opacity/blur (front sharp, sides/back blurred), a Y-axis 3D tilt, and
/// a spring-in keyed off `revealed`. Per-card stagger via `index`.
private struct RingPlacement: ViewModifier {
    let theta: Double
    let index: Int
    let revealed: Bool
    let reduceMotion: Bool
    var tiltX: Double = 0
    var tiltY: Double = 0

    func body(content: Content) -> some View {
        let rad = theta * .pi / 180
        let depth = cos(rad)                                   // 1 at front
        let x = CGFloat(sin(rad)) * WhyCarousel.radius
        // Side cards shrink faster than before so they sit visibly behind the
        // front card instead of crowding it.
        let scale = CGFloat(0.66 + 0.34 * max(0, depth))
        let opacity = 0.42 + 0.58 * max(0, depth)
        let blur = reduceMotion ? 0 : CGFloat(max(0, 1 - depth) * 3.6)
        // Parallax: front cards (depth→1) move more than the ones behind.
        let parallaxFactor = CGFloat(0.4 + 0.6 * max(0, depth))
        let px = CGFloat(tiltX) * WhyCarousel.parallaxAmplitude * parallaxFactor
        let py = CGFloat(tiltY) * WhyCarousel.parallaxAmplitude * parallaxFactor

        return content
            .scaleEffect(revealed ? scale : 0.42)
            .opacity(revealed ? opacity : 0)
            .blur(radius: blur)
            .rotation3DEffect(.degrees(theta), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .offset(x: x + px, y: py)
            .zIndex(depth)
            .animation(
                reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.82).delay(Double(index) * 0.06),
                value: revealed
            )
    }
}

// MARK: - Carousel card (front + back faces)

private struct WhyCarouselCard: View {
    let feature: WhyFeature
    /// True when this card faces the viewer; false shows the frosted back.
    let front: Bool

    private var accent: LinearGradient {
        LinearGradient(
            colors: [OnboardingGlassTheme.accentStart, OnboardingGlassTheme.accentEnd],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            frontFace.opacity(front ? 1 : 0)
            backFace
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(front ? 0 : 1)
        }
        .frame(width: WhyCarousel.cardW, height: WhyCarousel.cardH)
    }

    // Front: visual on top, then title + subtitle.
    private var frontFace: some View {
        VStack(spacing: 0) {
            visual
                .frame(width: WhyCarousel.cardW, height: 150)
                .clipped()

            VStack(spacing: 4) {
                Text(feature.title)
                    .font(.system(size: 15.5, weight: .heavy))
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)
                    .lineLimit(1)

                Text(feature.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 32, alignment: .top)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
        }
        .frame(width: WhyCarousel.cardW, height: WhyCarousel.cardH)
        .background(OnboardingGlassTheme.panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(OnboardingGlassTheme.panelStroke, lineWidth: 1)
        )
        .shadow(color: OnboardingGlassTheme.buttonShadow, radius: 14, y: 8)
    }

    private var backFace: some View {
        ZStack {
            Text(feature.number)
                .font(OnboardingTypography.instrumentSerif(style: .regular, size: 110))
                .foregroundStyle(OnboardingGlassTheme.textPrimary.opacity(0.05))

            Circle()
                .fill(accent)
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: "sparkle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                )
                .shadow(color: OnboardingGlassTheme.accentStart.opacity(0.35), radius: 10, y: 6)
        }
        .frame(width: WhyCarousel.cardW, height: WhyCarousel.cardH)
        .background(OnboardingGlassTheme.panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(OnboardingGlassTheme.panelStroke, lineWidth: 1)
        )
    }

    // MARK: Per-feature visuals

    @ViewBuilder
    private var visual: some View {
        switch feature.kind {
        case .type:     typeVisual
        case .photo:    photoVisual
        case .progress: progressVisual
        case .recipe:   recipeVisual
        case .importWeb: importVisual
        case .widget:   widgetVisual
        }
    }

    private var typeVisual: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(accent)
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "sparkle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                )
            LoggingDemoAnimation()
                .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
    }

    private var photoVisual: some View {
        ZStack {
            Image("food_photo_demo")
                .resizable()
                .scaledToFill()
                .frame(width: 126, height: 126)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Camera focus frame: four corner brackets sitting just inside the
            // photo edges (the "four lines"), like a viewfinder.
            CameraCorners(length: 17, inset: 8)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 126, height: 126)
                .shadow(color: .black.opacity(0.35), radius: 2)
        }
        .frame(width: WhyCarousel.cardW, height: 150)
    }

    private var progressVisual: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(OnboardingGlassTheme.textPrimary.opacity(0.12), lineWidth: 8)
                    .padding(5)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(5)
                VStack(spacing: 0) {
                    Text("720")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(OnboardingGlassTheme.textPrimary)
                    Text("of 2000")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(OnboardingGlassTheme.textSecondary)
                }
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 7) {
                macroBar("P", 0.72, "90g")
                macroBar("C", 0.54, "68g")
                macroBar("F", 0.40, "24g")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func macroBar(_ label: String, _ frac: CGFloat, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .frame(width: 12, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(OnboardingGlassTheme.textPrimary.opacity(0.12)).frame(width: 50, height: 6)
                Capsule().fill(accent).frame(width: 50 * frac, height: 6)
            }
            Text(value)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                .monospacedDigit()
        }
    }

    private var recipeVisual: some View {
        ZStack(alignment: .bottomLeading) {
            Image("food_photo_demo")
                .resizable()
                .scaledToFill()
                .frame(width: 154, height: 118)
                .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                Text("Greek Yogurt Bowl")
                    .font(.system(size: 12.5, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("9 ingr · 4 steps · 320 cal")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(9)
        }
        .frame(width: 154, height: 118)
        .overlay(alignment: .topTrailing) {
            Label("Fits", systemImage: "checkmark.circle.fill")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.30))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color(red: 0.85, green: 0.95, blue: 0.88), in: Capsule())
                .padding(7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var importVisual: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                SocialIcon(.instagram, size: 28)
                SocialIcon(.tiktok, size: 28)
                SocialIcon(.facebook, size: 28)
            }

            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OnboardingGlassTheme.textSecondary)
                Capsule()
                    .fill(OnboardingGlassTheme.textPrimary.opacity(0.18))
                    .frame(width: 50, height: 6)
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(OnboardingGlassTheme.panelFill, in: Capsule())
            .overlay(Capsule().strokeBorder(OnboardingGlassTheme.panelStroke, lineWidth: 1))

            Label("Import", systemImage: "square.and.arrow.down.fill")
                .font(.system(size: 9.5, weight: .heavy))
                .foregroundStyle(Color(red: 0.16, green: 0.20, blue: 0.42))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Color(red: 0.84, green: 0.88, blue: 1.0), in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var widgetVisual: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(accent)
                        .frame(width: 15, height: 15)
                        .overlay(Image(systemName: "sparkle").font(.system(size: 7, weight: .black)).foregroundStyle(.white))
                    Text("Calorie").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(OnboardingGlassTheme.accentStart)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("842").font(.system(size: 25, weight: .black, design: .rounded)).foregroundStyle(.white)
                Text("/ 2000").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            }
            Capsule().fill(.white.opacity(0.16)).frame(height: 6)
                .overlay(alignment: .leading) { Capsule().fill(accent).frame(width: 56, height: 6) }
            HStack(spacing: 7) {
                ForEach(["camera.fill", "mic.fill", "plus"], id: \.self) { symbol in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.1))
                        .frame(height: 26)
                        .overlay(Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                }
            }
        }
        .padding(13)
        .frame(width: 158)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.10, green: 0.09, blue: 0.16), Color(red: 0.06, green: 0.10, blue: 0.11)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }
}

/// Four camera-style corner brackets, inset from the rect edges.
private struct CameraCorners: Shape {
    var length: CGFloat = 16
    var inset: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: inset, dy: inset)
        let l = length
        // top-left
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        // top-right
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        // bottom-right
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        // bottom-left
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

/// Stylized social-platform chip (approximations — real brand glyphs would need
/// image assets added to the catalog later). Used on the curated-recipes card.
private struct SocialIcon: View {
    enum Kind { case instagram, tiktok, facebook }
    let kind: Kind
    var size: CGFloat = 18
    init(_ kind: Kind, size: CGFloat = 18) { self.kind = kind; self.size = size }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(glyph)
            .shadow(color: .black.opacity(0.25), radius: size * 0.11, y: 1)
    }

    private var fill: AnyShapeStyle {
        switch kind {
        case .instagram:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 1.0, green: 0.85, blue: 0.46),
                         Color(red: 0.84, green: 0.16, blue: 0.46),
                         Color(red: 0.59, green: 0.18, blue: 0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .tiktok:
            return AnyShapeStyle(Color.black)
        case .facebook:
            return AnyShapeStyle(Color(red: 0.09, green: 0.47, blue: 0.95))
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch kind {
        case .instagram:
            Image(systemName: "camera").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white)
        case .tiktok:
            Image(systemName: "music.note").font(.system(size: size * 0.5, weight: .black)).foregroundStyle(.white)
        case .facebook:
            Text("f").font(.system(size: size * 0.62, weight: .black, design: .serif)).foregroundStyle(.white)
        }
    }
}

// MARK: - App icon badge

/// Rounded app-icon mark shown above the heading. Loads the current app icon
/// from the bundle at runtime (no asset wiring needed); falls back to an accent
/// placeholder if it can't be found. Swap for the updated icon when ready.
private struct AppIconBadge: View {
    private static let icon: UIImage? = {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else { return nil }
        return UIImage(named: name)
    }()

    var body: some View {
        Group {
            if let icon = Self.icon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [OnboardingGlassTheme.accentStart, OnboardingGlassTheme.accentEnd],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "fork.knife")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                )
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Typewriter heading (reused)

/// Types `fullText` one character at a time (driven by `typedCount`) without
/// layout reflow: an invisible full-text copy reserves the final frame, and the
/// visible prefix is leading-anchored within that centered block.
private struct TypewriterHeading: View {
    let fullText: String
    let typedCount: Int
    let showCaret: Bool

    private var serif: Font { OnboardingTypography.instrumentSerif(style: .regular, size: 38) }

    var body: some View {
        ZStack(alignment: .leading) {
            Text(fullText)
                .font(serif)
                .lineLimit(1)
                .opacity(0)

            HStack(alignment: .center, spacing: 2) {
                Text(String(fullText.prefix(typedCount)))
                    .font(serif)
                    .foregroundStyle(OnboardingGlassTheme.textPrimary)
                    .lineLimit(1)

                CaretView()
                    .opacity(showCaret ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement()
        .accessibilityLabel(Text(fullText))
    }
}

/// Thin blinking caret for the typewriter heading.
private struct CaretView: View {
    @State private var lit = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(OnboardingGlassTheme.textPrimary)
            .frame(width: 2.5, height: 30)
            .opacity(lit ? 1 : 0)
            .onAppear {
                guard !UIAccessibility.isReduceMotionEnabled else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    lit = false
                }
            }
    }
}

// MARK: - Logging Demo Animation (reused)

/// Simulates the real home-screen logging experience: text types in, a brief
/// "thinking" shimmer appears, the calorie estimate fades in, then it loops.
struct LoggingDemoAnimation: View {
    @Environment(\.colorScheme) private var colorScheme

    private let items: [(text: String, calories: String)] = [
        ("eggs & toast", "310 cal"),
        ("chicken salad", "420 cal"),
        ("greek yogurt", "180 cal"),
        ("cheese pizza", "285 cal")
    ]

    @State private var currentIndex = 0
    @State private var typedCount = 0
    @State private var phase: DemoPhase = .idle
    @State private var timerTask: Task<Void, Never>?

    private enum DemoPhase { case idle, typing, thinking, result, hold }

    private var currentItem: (text: String, calories: String) {
        items[currentIndex % items.count]
    }

    private var displayedText: String {
        String(currentItem.text.prefix(typedCount))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 0) {
                    Text(displayedText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 0.11, green: 0.13, blue: 0.18))
                        .lineLimit(1)

                    if phase == .typing || phase == .idle {
                        Text("|")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(Color.black.opacity(0.4))
                            .opacity(phase == .typing ? 1 : 0.4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if phase == .thinking {
                        thinkingIndicator
                            .transition(.opacity)
                    } else if phase == .result || phase == .hold {
                        ShimmerCalorieText(text: currentItem.calories)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .frame(width: 92, alignment: .trailing)
                .animation(.easeInOut(duration: 0.3), value: phase)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .onboardingGlassPanel(cornerRadius: 14, fillOpacity: 0.10, strokeOpacity: 0.14)
        }
        .onAppear { startAnimation() }
        .onDisappear { timerTask?.cancel() }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase == .thinking ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15),
                        value: phase
                    )
            }
        }
    }

    private func startAnimation() {
        timerTask?.cancel()

        if UIAccessibility.isReduceMotionEnabled {
            typedCount = currentItem.text.count
            phase = .hold
            return
        }

        timerTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)

            while !Task.isCancelled {
                typedCount = 0
                phase = .typing

                let text = currentItem.text
                for charIndex in 1...text.count {
                    guard !Task.isCancelled else { return }
                    typedCount = charIndex
                    let char = text[text.index(text.startIndex, offsetBy: charIndex - 1)]
                    let baseDelay: UInt64 = char == " " ? 30_000_000 : 55_000_000
                    let jitter = UInt64.random(in: 0...20_000_000)
                    try? await Task.sleep(nanoseconds: baseDelay + jitter)
                }

                guard !Task.isCancelled else { return }
                phase = .thinking
                try? await Task.sleep(nanoseconds: 1_200_000_000)

                guard !Task.isCancelled else { return }
                phase = .result
                try? await Task.sleep(nanoseconds: 300_000_000)
                phase = .hold

                try? await Task.sleep(nanoseconds: 2_500_000_000)

                guard !Task.isCancelled else { return }
                currentIndex = (currentIndex + 1) % items.count
                phase = .idle
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
    }
}

// MARK: - Shimmer Calorie Text (reused)

/// A calorie label with a continuous lighting sweep across the text.
private struct ShimmerCalorieText: View {
    let text: String
    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        // Deeper, more saturated than the brand pastels so the calorie result
        // pops against the light input field.
        let accentTint = LinearGradient(
            colors: [Color(red: 0.97, green: 0.45, blue: 0.10), Color(red: 0.04, green: 0.70, blue: 0.55)],
            startPoint: .leading,
            endPoint: .trailing
        )

        return HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accentTint)

            Text(text)
                .font(.system(size: 14.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(accentTint)
        }
        .overlay(
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
                .offset(x: shimmerOffset * (w + sweepWidth) - sweepWidth)
                .blendMode(.sourceAtop)
            }
        )
        .compositingGroup()
        .onAppear {
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) {
                shimmerOffset = 1
            }
        }
    }
}
