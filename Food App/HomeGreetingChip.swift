import SwiftUI

/// Home-screen greeting button. The struct name is preserved so the call site
/// in `MainLoggingTopHeaderStrip` doesn't need to change, but this now renders
/// as inline header text instead of a glass capsule.
///
/// The view now:
///   - Resolves a time-of-day-aware animation via `GreetingAnimationResolver`
///   - Renders the selected animation in a 24×24 frame
///   - Shows "Hi, <first name>" so the header reads as a greeting, not a nav
///     chip competing with the date control.
///   - Trails a small chevron to signal "opens a sheet"
struct HomeGreetingChip: View {
    @EnvironmentObject private var appStore: AppStore
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
        let nameLine = displayLabel(firstName: firstName)

        return HStack(spacing: 7) {
            GreetingAnimationView(animation: resolved.animation)

            Text(nameLine)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(textColor)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(textColor.opacity(0.45))
                .padding(.leading, -2)
        }
        .frame(minHeight: 44, alignment: .center)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(nameLine). Opens profile."))
    }

    private var textColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.96)
            : Color.primary.opacity(0.85)
    }

    private func displayLabel(firstName: String?) -> String {
        let trimmed = firstName?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? "Hi" : "Hi, \(trimmed)"
    }
}
