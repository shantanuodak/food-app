import SwiftUI

struct HomeGreetingChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var handRotation = 0.0

    let firstName: String?

    var body: some View {
        HStack(spacing: 6) {
            Text("👋")
                .font(.system(size: 14))
                .rotationEffect(.degrees(handRotation), anchor: .bottomTrailing)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 0.16, green: 0.64, blue: 0.98))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Greeting: \(title)"))
        .onAppear {
            applyWaveAnimation(isReducedMotion: reduceMotion)
        }
        .onChange(of: reduceMotion) { _, newValue in
            applyWaveAnimation(isReducedMotion: newValue)
        }
        .onDisappear {
            handRotation = 0
        }
    }

    private var title: String {
        guard let firstName, !firstName.isEmpty else {
            return "Hey"
        }
        return "Hey \(firstName)"
    }

    private func applyWaveAnimation(isReducedMotion: Bool) {
        handRotation = 0
        guard !isReducedMotion else {
            return
        }

        withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
            handRotation = 16
        }
    }
}
