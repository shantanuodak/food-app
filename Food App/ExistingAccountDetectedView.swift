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
///
/// Phase F redesign (2026-05-22): tone-down pass to match the rest of the
/// app's cream + brand-orange language. Drops the green CTA, uses
/// InstrumentSerif for the hero, surfaces a small data preview card so the
/// user can see what they're recovering.
struct ExistingAccountDetectedView: View {
    /// Status fetched from `/v1/onboarding/status` after OAuth completed.
    let status: OnboardingStatusResponse
    /// Optional display name we can greet with — likely the user's first
    /// name from the OAuth payload (passed through from AuthService).
    let displayName: String?

    let onContinueWithExisting: () -> Void
    let onUpdateProfile: () -> Void
    let onCancel: () -> Void

    private static let inkColor = Color(red: 0.141, green: 0.098, blue: 0.078)
    private static let mutedColor = Color(red: 0.467, green: 0.416, blue: 0.380)
    private static let brandOrange = Color(red: 0.902, green: 0.361, blue: 0.102)
    private static let brandOrangeDeep = Color(red: 0.725, green: 0.306, blue: 0.071)
    private static let borderColor = Color(red: 0.278, green: 0.176, blue: 0.098).opacity(0.11)
    private static let surfaceGradient = LinearGradient(
        colors: [
            Color(red: 0.965, green: 0.886, blue: 0.792),
            Color(red: 1.000, green: 0.976, blue: 0.941),
            Color(red: 0.957, green: 0.918, blue: 0.875)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private var headline: String {
        if let displayName, !displayName.isEmpty {
            return "Welcome back, \(displayName)"
        }
        return "Welcome back"
    }

    private var subtitle: String {
        let mealsPart = status.mealCount > 0
            ? "\(status.mealCount) meal\(status.mealCount == 1 ? "" : "s") logged"
            : "goals saved"
        let daysPart = daysSinceCreated.map { "joined \($0) day\($0 == 1 ? "" : "s") ago" }
        if let daysPart {
            return "\(mealsPart) · \(daysPart)"
        }
        return mealsPart
    }

    private var daysSinceCreated: Int? {
        guard let createdAt = status.createdAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let created = formatter.date(from: createdAt)
            ?? ISO8601DateFormatter().date(from: createdAt)
        guard let created else { return nil }
        let components = Calendar.current.dateComponents([.day], from: created, to: Date())
        return components.day.map { max(0, $0) }
    }

    var body: some View {
        ZStack {
            Self.surfaceGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 96)

                heroBlock
                    .padding(.horizontal, 28)

                Spacer().frame(height: 28)

                if status.mealCount > 0 || daysSinceCreated != nil {
                    statsCard
                        .padding(.horizontal, 28)
                }

                Spacer()

                actionStack
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account found")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Self.brandOrangeDeep)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.white.opacity(0.72), in: Capsule())
                .overlay(
                    Capsule().stroke(Self.borderColor, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 12, y: 6)

            Text(headline)
                .font(.custom("InstrumentSerif-Italic", size: 38))
                .foregroundStyle(Self.inkColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Self.mutedColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            statRow(label: "Meals logged", value: "\(status.mealCount)")
            divider
            if let days = daysSinceCreated {
                statRow(label: "Member since", value: "\(days) day\(days == 1 ? "" : "s") ago")
            }
            if status.hasCompletedOnboarding {
                divider
                statRow(label: "Profile", value: "Set up")
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Self.borderColor, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 18, y: 8)
        )
    }

    private func statRow(label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Self.mutedColor)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Self.inkColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Self.borderColor)
            .frame(height: 1)
            .padding(.horizontal, 18)
    }

    private var actionStack: some View {
        VStack(spacing: 12) {
            Button(action: onContinueWithExisting) {
                Text("Continue with my existing account")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.00, green: 0.62, blue: 0.20),
                                        Self.brandOrange
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: Self.brandOrange.opacity(0.30), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Skips setup and signs in to your existing account.")

            Button(action: onUpdateProfile) {
                Text("Update my profile with new info")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Self.brandOrangeDeep)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.white.opacity(0.78))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Self.brandOrange.opacity(0.45), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Finishes onboarding and overwrites your existing profile fields. Your food logs stay.")

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Self.mutedColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Goes back to the previous screen.")
        }
    }
}

#if DEBUG
#Preview("Existing user — 47 meals") {
    ExistingAccountDetectedView(
        status: OnboardingStatusResponse(
            hasCompletedOnboarding: true,
            mealCount: 47,
            createdAt: "2026-04-12T12:00:00Z",
            displayName: nil
        ),
        displayName: "Shantanu",
        onContinueWithExisting: { print("preview: continue") },
        onUpdateProfile: { print("preview: update") },
        onCancel: { print("preview: cancel") }
    )
}

#Preview("Existing user — no meals (just goals)") {
    ExistingAccountDetectedView(
        status: OnboardingStatusResponse(
            hasCompletedOnboarding: true,
            mealCount: 0,
            createdAt: "2026-05-01T12:00:00Z",
            displayName: nil
        ),
        displayName: nil,
        onContinueWithExisting: { print("preview: continue") },
        onUpdateProfile: { print("preview: update") },
        onCancel: { print("preview: cancel") }
    )
}

#Preview("Existing user — single meal") {
    ExistingAccountDetectedView(
        status: OnboardingStatusResponse(
            hasCompletedOnboarding: true,
            mealCount: 1,
            createdAt: "2026-05-20T12:00:00Z",
            displayName: nil
        ),
        displayName: "Pornima",
        onContinueWithExisting: { print("preview: continue") },
        onUpdateProfile: { print("preview: update") },
        onCancel: { print("preview: cancel") }
    )
}
#endif
