import SwiftUI

struct HomeGreetingChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var handRotation = 0.0

    let firstName: String?

    var body: some View {
        HStack(spacing: 6) {
            Text("👋")
                .font(.system(size: 14))
                .rotationEffect(.degrees(handRotation), anchor: .bottomTrailing)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.96) : Color.primary.opacity(0.80))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 1.00, green: 0.78, blue: 0.33).opacity(0.12))
        )
        .glassEffect(.regular.interactive(), in: .capsule)
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
            return "Hello"
        }
        return "Hey, \(firstName)"
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
