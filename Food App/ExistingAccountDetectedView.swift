import SwiftUI

/// V3.1 Phase 5: shown when a user who completed onboarding before signs in
/// again with the same Apple/Google identity during a "Sign Up" flow.
/// Without this screen they could overwrite their existing profile or end
/// up with phantom duplicate accounts. Three explicit options:
///
///   1. Continue with existing account — short-circuits the rest of
///      onboarding, marks complete, lands on home with old profile intact.
///   2. Update my profile with new info — continues normal onboarding; the
///      final `submitOnboarding` UPSERTs over the existing row. Food logs
///      are never touched in either path.
///   3. Cancel — dismisses the sheet so the user can pick a different
///      provider or back out.
struct ExistingAccountDetectedView: View {
    /// Status fetched from `/v1/onboarding/status` after OAuth completed.
    let status: OnboardingStatusResponse
    /// Optional display name we can greet with — likely the user's first
    /// name from the OAuth payload (passed through from AuthService).
    let displayName: String?

    let onContinueWithExisting: () -> Void
    let onUpdateProfile: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var titleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : Color.black
    }

    private var bodyColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.78) : Color.black.opacity(0.72)
    }

    private var primaryCTA: Color {
        Color(red: 0.126, green: 0.494, blue: 0.216)
    }

    private var headline: String {
        if let displayName, !displayName.isEmpty {
            return "Welcome back, \(displayName)!"
        }
        return "Welcome back!"
    }

    private var summary: String {
        let mealsPart = status.mealCount > 0
            ? "\(status.mealCount) meal\(status.mealCount == 1 ? "" : "s") logged"
            : "your goals already saved"
        return "Looks like you already have an account with \(mealsPart). Want to keep using it?"
    }

    var body: some View {
        ZStack {
            OnboardingStaticBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 72)

                // Icon + headline
                VStack(spacing: 18) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(primaryCTA)

                    Text(headline)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.center)

                    Text(summary)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(bodyColor)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
                .padding(.horizontal, 30)

                Spacer()

                // CTAs
                VStack(spacing: 14) {
                    // Primary — continue with existing
                    Button(action: onContinueWithExisting) {
                        Text("Continue with my existing account")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 55)
                            .background(primaryCTA, in: RoundedRectangle(cornerRadius: 52, style: .continuous))
                            .shadow(color: Color(red: 0.184, green: 0.357, blue: 0.118).opacity(0.45), radius: 11, x: 1, y: -1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Skips setup and signs in to your existing account.")

                    // Secondary — update profile with what they just entered
                    Button(action: onUpdateProfile) {
                        Text("Update my profile with new info")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(titleColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 52, style: .continuous)
                                    .stroke(titleColor.opacity(0.30), lineWidth: 1.2)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Finishes onboarding and overwrites your existing profile fields. Your food logs stay.")

                    // Tertiary — cancel
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(bodyColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Goes back to the previous screen.")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}
