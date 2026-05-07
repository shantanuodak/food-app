import SwiftUI

struct VoiceRecordingOverlay: View {
    enum Phase: Equatable {
        case listening
        case handoff
    }

    let transcribedText: String
    let isListening: Bool
    let audioLevel: Float
    let phase: Phase
    let onCancel: () -> Void
    /// Called when the user stays silent for too long after the overlay appears.
    var onSilenceTimeout: (() -> Void)? = nil

    @State private var labelOpacity: Double = 1.0
    @State private var gradientPhase: CGFloat = 0
    /// Smooth audio level with easing — avoids jittery gradient jumps.
    @State private var smoothLevel: CGFloat = 0
    /// Tracks seconds since last detected speech for auto-dismiss.
    @State private var silenceTimer: Task<Void, Never>?

    private let silenceTimeoutSeconds: UInt64 = 6
    private let glowHeight: CGFloat = 620

    private var level: CGFloat { smoothLevel }
    private var phaseBoost: CGFloat { phase == .handoff ? 0.30 : 0 }

    // MARK: - Mesh Gradient (expanded + dispersed)

    private var meshPoints: [SIMD2<Float>] {
        let phase = Float(gradientPhase)
        let l = Float(level)
        // Slow drift keeps the wash alive without feeling like a busy equalizer.
        let cx = 0.50 + phase * 0.16 + l * 0.05
        let cy = 0.40 + l * 0.08 - Float(phaseBoost) * 0.06
        let bx = 0.50 - phase * 0.12
        let by = 0.82 + l * 0.04
        let tx = 0.48 + phase * 0.10
        return [
            [0, 0],    [tx, 0],  [1, 0],
            [0, 0.4],  [cx, cy], [1, 0.45],
            [0, 1],    [bx, by], [1, 1]
        ]
    }

    private var meshColors: [Color] {
        let l = Double(level)
        // Softer, more modern saturation: color is present, not posterized.
        return [
            Color(red: 0.52, green: 0.24, blue: 1.00).opacity(0.44 + l * 0.08 + Double(phaseBoost) * 0.08),
            Color(red: 0.42, green: 0.52, blue: 1.00).opacity(0.40 + l * 0.10 + Double(phaseBoost) * 0.08),
            Color(red: 0.16, green: 0.72, blue: 0.95).opacity(0.36 + l * 0.08 + Double(phaseBoost) * 0.06),

            Color(red: 0.94, green: 0.28, blue: 0.66).opacity(0.42 + l * 0.12 + Double(phaseBoost) * 0.06),
            Color(red: 0.62, green: 0.30, blue: 1.00).opacity(0.52 + l * 0.12 + Double(phaseBoost) * 0.08),
            Color(red: 0.24, green: 0.60, blue: 0.98).opacity(0.42 + l * 0.10 + Double(phaseBoost) * 0.06),

            Color(red: 0.50, green: 0.22, blue: 0.96).opacity(0.38 + l * 0.08 + Double(phaseBoost) * 0.05),
            Color(red: 0.95, green: 0.42, blue: 0.74).opacity(0.46 + l * 0.10 + Double(phaseBoost) * 0.05),
            Color(red: 0.48, green: 0.34, blue: 0.96).opacity(0.38 + l * 0.08 + Double(phaseBoost) * 0.05)
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .contentShape(Rectangle())

            backgroundObscurer
            ambientVoiceWash
            edgeGlow
            voiceContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                labelOpacity = 0.58
            }
            withAnimation(.easeInOut(duration: 6.8).repeatForever(autoreverses: true)) {
                gradientPhase = 1
            }
            startSilenceTimer()
        }
        .onDisappear {
            silenceTimer?.cancel()
        }
        .onChange(of: audioLevel) { _, newLevel in
            // Smooth the audio level with a spring so the gradient flows naturally
            withAnimation(.interpolatingSpring(stiffness: 26, damping: 12)) {
                smoothLevel = min(max(CGFloat(newLevel), 0), 1)
            }
        }
        .onChange(of: transcribedText) { _, newText in
            // Any new speech resets the silence timer
            if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                silenceTimer?.cancel()
            }
        }
    }

    private var ambientVoiceWash: some View {
        ZStack(alignment: .bottom) {
            MeshGradient(width: 3, height: 3, points: meshPoints, colors: meshColors)
                .scaleEffect(1.38 + level * 0.04 + phaseBoost * 0.10)
                .blur(radius: 26)
                .saturation(1.04 + level * 0.08)
                .opacity(0.95)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.10), location: 0.12),
                            .init(color: .black.opacity(0.46), location: 0.34),
                            .init(color: .black.opacity(0.88), location: 0.62),
                            .init(color: .black, location: 0.82),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.white.opacity(0.05), location: 0.30),
                    .init(color: Color.white.opacity(0.13), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            RadialGradient(
                colors: [
                    Color.white.opacity(0.24 + Double(level) * 0.08 + Double(phaseBoost) * 0.08),
                    Color.white.opacity(0.08),
                    .clear
                ],
                center: .bottom,
                startRadius: 20,
                endRadius: 300
            )
            .blendMode(.screen)
        }
        .frame(maxWidth: .infinity)
        .frame(height: glowHeight)
        .allowsHitTesting(false)
    }

    private var backgroundObscurer: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.white.opacity(0.10), location: 0.24),
                        .init(color: Color.white.opacity(0.20), location: 0.55),
                        .init(color: Color.white.opacity(0.30), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.10), location: 0.16),
                        .init(color: .black.opacity(0.72), location: 0.40),
                        .init(color: .black, location: 0.58),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var edgeGlow: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(red: 0.65, green: 0.30, blue: 1.00).opacity(0.30 + Double(level) * 0.08),
                    Color(red: 0.90, green: 0.38, blue: 0.78).opacity(0.16 + Double(phaseBoost) * 0.08),
                    .clear
                ],
                center: .bottom,
                startRadius: 90,
                endRadius: 520
            )
            .blur(radius: 18)

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color(red: 0.64, green: 0.34, blue: 1.00).opacity(0.20 + Double(level) * 0.05),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 80)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [
                        .clear,
                        Color(red: 0.20, green: 0.72, blue: 0.95).opacity(0.18 + Double(level) * 0.05)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 80)
            }
            .blur(radius: 18)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var voiceContent: some View {
        VStack(spacing: 16) {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.18))
                .frame(width: 34, height: 4)
                .padding(.bottom, 6)

            if transcribedText.isEmpty {
                Text(phase == .handoff ? "Adding to your log" : "Listening")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .opacity(phase == .handoff ? 0.92 : labelOpacity)
            } else {
                Text(transcribedText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity)
            }

            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.black.opacity(0.66))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(.white.opacity(0.34), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.26), lineWidth: 1)
            )
            .opacity(phase == .handoff ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, phase == .handoff ? 104 : 84)
        .scaleEffect(phase == .handoff ? 0.94 : 1)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: phase)
    }

    // MARK: - Silence Timeout

    private func startSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: silenceTimeoutSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            // Only auto-dismiss if user hasn't said anything
            if transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onSilenceTimeout?() ?? onCancel()
            }
        }
    }
}
