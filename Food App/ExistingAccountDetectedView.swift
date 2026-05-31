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

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601Plain = ISO8601DateFormatter()

    private var daysSinceCreated: Int? {
        guard let createdAt = status.createdAt else { return nil }
        let created = Self.iso8601WithFractional.date(from: createdAt)
            ?? Self.iso8601Plain.date(from: createdAt)
        guard let created else { return nil }
        let components = Calendar.current.dateComponents([.day], from: created, to: Date())
        return components.day.map { max(0, $0) }
    }

    var body: some View {
        ZStack {
            ExistingAccountPalette.backgroundGradient.ignoresSafeArea()

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
                .foregroundStyle(ExistingAccountPalette.badgeInk)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ExistingAccountPalette.badgeFill, in: Capsule())
                .overlay(
                    Capsule().stroke(ExistingAccountPalette.borderColor, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 12, y: 6)

            Text(headline)
                .font(.custom("InstrumentSerif-Italic", size: 38))
                .foregroundStyle(ExistingAccountPalette.inkColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(ExistingAccountPalette.mutedColor)
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
                .fill(ExistingAccountPalette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(ExistingAccountPalette.borderColor, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 18, y: 8)
        )
    }

    private func statRow(label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(ExistingAccountPalette.mutedColor)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(ExistingAccountPalette.inkColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(ExistingAccountPalette.borderColor)
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
                                        ExistingAccountPalette.brandOrange
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: ExistingAccountPalette.brandOrange.opacity(0.30), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Skips setup and signs in to your existing account.")

            Button(action: onUpdateProfile) {
                Text("Update my profile with new info")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(ExistingAccountPalette.secondaryButtonInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(ExistingAccountPalette.secondaryButtonFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(ExistingAccountPalette.secondaryButtonStroke, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Finishes onboarding and overwrites your existing profile fields. Your food logs stay.")

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(ExistingAccountPalette.mutedColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Goes back to the previous screen.")
        }
    }
}

private enum ExistingAccountPalette {
    static let inkColor = adaptiveColor(
        light: UIColor(red: 0.141, green: 0.098, blue: 0.078, alpha: 1.0),
        dark: UIColor(white: 0.96, alpha: 1.0)
    )
    static let mutedColor = adaptiveColor(
        light: UIColor(red: 0.467, green: 0.416, blue: 0.380, alpha: 1.0),
        dark: UIColor(white: 0.84, alpha: 0.78)
    )
    static let brandOrange = Color(red: 0.902, green: 0.361, blue: 0.102)
    static let badgeInk = adaptiveColor(
        light: UIColor(red: 0.725, green: 0.306, blue: 0.071, alpha: 1.0),
        dark: UIColor(red: 0.98, green: 0.77, blue: 0.56, alpha: 1.0)
    )
    static let borderColor = adaptiveColor(
        light: UIColor(red: 0.278, green: 0.176, blue: 0.098, alpha: 0.11),
        dark: UIColor(white: 1.0, alpha: 0.12)
    )
    static let badgeFill = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.72),
        dark: UIColor(white: 1.0, alpha: 0.10)
    )
    static let cardFill = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.72),
        dark: UIColor(red: 0.19, green: 0.16, blue: 0.14, alpha: 0.84)
    )
    static let secondaryButtonFill = adaptiveColor(
        light: UIColor(white: 1.0, alpha: 0.78),
        dark: UIColor(red: 0.18, green: 0.15, blue: 0.13, alpha: 0.90)
    )
    static let secondaryButtonInk = adaptiveColor(
        light: UIColor(red: 0.725, green: 0.306, blue: 0.071, alpha: 1.0),
        dark: UIColor(red: 0.97, green: 0.75, blue: 0.54, alpha: 1.0)
    )
    static let secondaryButtonStroke = adaptiveColor(
        light: UIColor(red: 0.902, green: 0.361, blue: 0.102, alpha: 0.45),
        dark: UIColor(red: 1.0, green: 0.62, blue: 0.20, alpha: 0.26)
    )
    static let backgroundGradient = LinearGradient(
        colors: [
            adaptiveColor(
                light: UIColor(red: 0.965, green: 0.886, blue: 0.792, alpha: 1.0),
                dark: UIColor(red: 0.09, green: 0.07, blue: 0.06, alpha: 1.0)
            ),
            adaptiveColor(
                light: UIColor(red: 1.000, green: 0.976, blue: 0.941, alpha: 1.0),
                dark: UIColor(red: 0.13, green: 0.10, blue: 0.09, alpha: 1.0)
            ),
            adaptiveColor(
                light: UIColor(red: 0.957, green: 0.918, blue: 0.875, alpha: 1.0),
                dark: UIColor(red: 0.16, green: 0.11, blue: 0.08, alpha: 1.0)
            )
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
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
