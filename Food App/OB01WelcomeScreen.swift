import SwiftUI

struct OB01WelcomeScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            OnboardingTypingDemoView()
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
