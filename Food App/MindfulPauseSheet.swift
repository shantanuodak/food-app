import SwiftUI

/// One-shot fullscreen pause for users who picked "emotional eating" as
/// their biggest challenge. Surfaces once per day, just before the user
/// starts logging — fulfilling the promise made on
/// `OB02cChallengeInsightScreen`: "Just open the app — that one moment
/// creates a mindful pause."
///
/// Visual stays calm and home-screen-native (system colors, no
/// onboarding glass theme), so it doesn't feel like a marketing
/// interruption.
struct MindfulPauseSheet: View {
    var onContinueLogging: () -> Void
    var onSkipForToday: () -> Void

    var body: some View {
        ZStack {
            // Calm background — pale-blue tone that reads "spa", not "alert".
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.98, blue: 1.0),
                    Color(red: 0.91, green: 0.95, blue: 0.99)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    Text("Take a breath.")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text("Notice what you actually need right now.")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                BreathingCircleView(accent: Color(red: 0.55, green: 0.40, blue: 0.85))

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button(action: onContinueLogging) {
                        Text("I'm good — log my meal")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.black, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onSkipForToday) {
                        Text("Skip for today")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .padding(.top, 24)
        }
    }
}

/// UserDefaults helpers for the once-per-day cap.
enum MindfulPauseGate {
    private static let keyPrefix = "food-app.breath.shown."

    static func shouldShow(today date: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        let key = keyPrefix + dateKey(date)
        return !defaults.bool(forKey: key)
    }

    static func markShown(today date: Date = Date(), defaults: UserDefaults = .standard) {
        let key = keyPrefix + dateKey(date)
        defaults.set(true, forKey: key)
    }

    private static func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
