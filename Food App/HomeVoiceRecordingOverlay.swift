import SwiftUI

struct VoiceRecordingOverlay: View {
    let transcribedText: String
    let isListening: Bool
    let audioLevel: Float
    let onCancel: () -> Void
    /// Called when the user stays silent for too long after the overlay appears.
    var onSilenceTimeout: (() -> Void)? = nil

    @State private var labelOpacity: Double = 1.0
    @State private var gradientPhase: CGFloat = 0
    /// Smooth audio level with easing — avoids jittery gradient jumps.
    @State private var smoothLevel: CGFloat = 0
    /// Tracks seconds since last detected speech for auto-dismiss.
    @State private var silenceTimer: Task<Void, Never>?

    private let silenceTimeoutSeconds: UInt64 = 4

    private var level: CGFloat { smoothLevel }

    // MARK: - Mesh Gradient (expanded + dispersed)

    private var meshPoints: [SIMD2<Float>] {
        let phase = Float(gradientPhase)
        let l = Float(level)
        // Organic sway — points drift gently based on phase + audio
        let cx = 0.5 + phase * 0.2 + l * 0.08
        let cy = 0.35 + l * 0.15
        let bx = 0.5 - phase * 0.15
        let by = 0.85 + l * 0.1
        let tx = 0.5 + phase * 0.12
        return [
            [0, 0],    [tx, 0],  [1, 0],
            [0, 0.4],  [cx, cy], [1, 0.45],
            [0, 1],    [bx, by], [1, 1]
        ]
    }

    private var meshColors: [Color] {
        let l = Double(level)
        // Richer saturation + spread across the full gradient area
        return [
            Color(red: 0.45, green: 0.15, blue: 0.85).opacity(0.55 + l * 0.2),
            Color(red: 0.35, green: 0.40, blue: 0.95).opacity(0.50 + l * 0.25),
            Color(red: 0.20, green: 0.60, blue: 0.90).opacity(0.45 + l * 0.15),

            Color(red: 0.75, green: 0.20, blue: 0.65).opacity(0.50 + l * 0.3),
            Color(red: 0.55, green: 0.25, blue: 0.95).opacity(0.65 + l * 0.3),
            Color(red: 0.30, green: 0.50, blue: 0.90).opacity(0.50 + l * 0.2),

            Color(red: 0.40, green: 0.20, blue: 0.80).opacity(0.45 + l * 0.15),
            Color(red: 0.70, green: 0.25, blue: 0.70).opacity(0.55 + l * 0.25),
            Color(red: 0.45, green: 0.30, blue: 0.85).opacity(0.45 + l * 0.15)
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                // Gradient background — taller, fades from top
                MeshGradient(width: 3, height: 3, points: meshPoints, colors: meshColors)
                    .frame(height: 240)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.3), location: 0.25),
                                .init(color: .black, location: 0.55)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                VStack(spacing: 12) {
                    if transcribedText.isEmpty {
                        Text("Listening")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .opacity(labelOpacity)
                    } else {
                        Text(transcribedText)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 24)
                    }

                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.top, 50)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                labelOpacity = 0.4
            }
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                gradientPhase = 1
            }
            startSilenceTimer()
        }
        .onDisappear {
            silenceTimer?.cancel()
        }
        .onChange(of: audioLevel) { _, newLevel in
            // Smooth the audio level with a spring so the gradient flows naturally
            withAnimation(.interpolatingSpring(stiffness: 40, damping: 8)) {
                smoothLevel = CGFloat(newLevel)
            }
        }
        .onChange(of: transcribedText) { _, newText in
            // Any new speech resets the silence timer
            if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                silenceTimer?.cancel()
            }
        }
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
