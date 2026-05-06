import SwiftUI

extension AnyTransition {
    /// Consistent enter/exit transition applied to every onboarding screen.
    /// Enter: fade in + slide up 22pt. Exit: fade out only to avoid clashing with the entering screen.
    static var obScreen: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 22)),
            removal: .opacity
        )
    }
}
