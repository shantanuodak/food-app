import SwiftUI

/// Home-screen greeting button. No longer a "chip" visually (the yellow
/// capsule is gone), but the struct name is preserved so the call site
/// in `MainLoggingTopHeaderStrip` doesn't need to change.
///
/// The view now:
///   - Resolves a time-of-day-aware animation via `GreetingAnimationResolver`
///   - Renders the selected animation in a 24×24 frame
///   - Greets with a slot-aware prefix ("Good morning", "Hey", "Evening",
///     "Good night", "Nice")
///   - Shimmers the name once on first render then every ~10s
///   - Trails a small chevron to signal "opens a sheet"
struct HomeGreetingChip: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let firstName: String?
    /// Override hook for milestone moments (streak hit, goal met). The
    /// caller flips this true for the duration of one launch.
    var hasMilestone: Bool = false

    var body: some View {
        let resolved = GreetingAnimationResolver.resolve(
            userId: appStore.authSessionStore.session?.userID,
            date: Date(),
            hasMilestone: hasMilestone
        )
        let nameLine = greetingLine(prefix: resolved.slot.greetingPrefix, firstName: firstName)

        return HStack(spacing: 6) {
            GreetingAnimationView(animation: resolved.animation)

            ShimmerText(text: nameLine, baseColor: textColor)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(textColor.opacity(0.45))
                .padding(.leading, -2)
        }
        // The wrapping Button in MainLoggingTopHeaderStrip now uses
        // LiquidGlassCapsuleButtonStyle (14h × 8v padding + glassy capsule),
        // which matches the date chip on the right. Don't add vertical
        // padding here — the button style handles spacing.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(nameLine). Opens profile."))
    }

    private var textColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.96)
            : Color.primary.opacity(0.85)
    }

    private func greetingLine(prefix: String, firstName: String?) -> String {
        if let name = firstName, !name.isEmpty {
            return "\(prefix), \(name)"
        }
        // Slot-aware fallback when we don't have a first name.
        return prefix == "Hey" ? "Hey there" : prefix
    }
}
