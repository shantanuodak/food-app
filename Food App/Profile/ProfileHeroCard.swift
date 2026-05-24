//
//  ProfileHeroCard.swift
//  Food App
//
//  Hero card that opens the bento dashboard. Replaced the earlier
//  inline `identityRow` (name + "Manage Account" link) on 2026-05-24.
//  Visual language was prototyped in `profile-card-mockup.html`:
//
//    • Image-style backdrop with dark gradient overlay
//    • Avatar circle with serif initials (matches "Logged" / hero serif)
//    • Compact body line (age · sex · height · weight)
//    • Two frosted "Preferences" + "Allergies" count chips
//    • Top-right Edit pill with backdrop blur
//    • CoreMotion-driven 3D tilt parallax (uses `DeviceTiltMotion`
//      from HomeProfileBentoScreen.swift — same instance pattern as
//      the daily-progress hero)
//
//  Real photographic backgrounds (mountain / forest / sunset / abstract)
//  will be added in a follow-up via Assets.xcassets. The current
//  procedural gradient is a stand-in that already feels premium and lets
//  the rest of the wiring land first.
//

import SwiftUI

struct ProfileHeroCard: View {
    /// First name from auth session — used to derive the avatar initials
    /// alongside `lastName`. Nil falls back to "?".
    let firstName: String?
    let lastName: String?

    /// Display name (e.g. "Shantanu Odak"). Falls back to email local part
    /// at the call site if no name is available.
    let displayName: String

    /// Account email, shown below the name.
    let email: String?

    /// Pre-formatted body line. E.g. "32 · Male · 5'10\" · 175 lb".
    /// Empty string hides the line (lets the call site decide formatting).
    let bodyLine: String

    let preferencesCount: Int
    let allergiesCount: Int

    /// Fires when the user taps the Edit pill or anywhere on the card.
    let onEdit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var tilt = DeviceTiltMotion()

    /// Matches the daily-progress hero's tilt magnitude so both hero cards
    /// on the bento feel like they share one physical reality.
    private let cardTiltDegrees: Double = 8
    private let cardPerspective: CGFloat = 0.55
    /// Background shifts opposite the tilt at a smaller magnitude — gives
    /// the foreground content a sense of "floating above" the backdrop.
    private let backgroundShiftPoints: CGFloat = 10

    private var parallaxEnabled: Bool { !reduceMotion }

    private var initials: String {
        let first = firstName?.trimmingCharacters(in: .whitespaces).first
        let last  = lastName?.trimmingCharacters(in: .whitespaces).first
        switch (first, last) {
        case let (f?, l?): return "\(f)\(l)".uppercased()
        case let (f?, nil): return String(f).uppercased()
        case let (nil, l?): return String(l).uppercased()
        default:           return "?"
        }
    }

    var body: some View {
        Button(action: onEdit) {
            ZStack {
                landscapeBackdrop
                    .offset(
                        x: parallaxEnabled ? -tilt.roll * backgroundShiftPoints : 0,
                        y: parallaxEnabled ? -tilt.pitch * backgroundShiftPoints : 0
                    )

                darkOverlay
                content
                editPill
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
            .rotation3DEffect(
                .degrees(parallaxEnabled ? -cardTiltDegrees * tilt.roll : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: cardPerspective
            )
            .rotation3DEffect(
                .degrees(parallaxEnabled ? cardTiltDegrees * tilt.pitch : 0),
                axis: (x: 1, y: 0, z: 0),
                perspective: cardPerspective
            )
            .animation(.easeOut(duration: 0.20), value: tilt.roll)
            .animation(.easeOut(duration: 0.20), value: tilt.pitch)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(displayName). Tap to edit profile."))
        .onAppear { if parallaxEnabled { tilt.start() } }
        .onDisappear { tilt.stop() }
        .onChange(of: reduceMotion) { _, newValue in
            if newValue { tilt.stop() } else { tilt.start() }
        }
    }

    // MARK: - Layers

    /// Curated photo backdrop, picked by the current hour of the day.
    /// Morning (5–11) → red-rock starscape · Afternoon (11–17) →
    /// rolling green valley · Evening (17–5) → forest under alpine
    /// ridge. Assets live in `Assets.xcassets/ProfileBg{Morning,
    /// Afternoon,Evening}.imageset`.
    private var landscapeBackdrop: some View {
        Image(timeOfDayImageName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            // Over-fill so the tilt shift never reveals the card bg
            // underneath. 1.12× also gives the image a touch of zoom for
            // the parallax to play against.
            .scaleEffect(1.12)
    }

    private var timeOfDayImageName: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11:  return "ProfileBgMorning"
        case 11..<17: return "ProfileBgAfternoon"
        default:      return "ProfileBgEvening"
        }
    }

    private var darkOverlay: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.05),
                Color.black.opacity(0.30),
                Color.black.opacity(0.72)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)

                    if !bodyLine.isEmpty {
                        Text(bodyLine)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    }
                }
            }

            summaryChips
                .padding(.top, 12)
        }
        // 2026-05-24: extra bottom padding so the chips don't crowd the
        // card edge — the previous 16pt left them feeling pinned to the
        // bottom and the user perceived them as missing.
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var avatar: some View {
        Text(initials)
            .font(.custom("InstrumentSerif-Regular", size: 19))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(
                LinearGradient(
                    colors: [AppColor.brandOrange, AppColor.brandOrangeDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .overlay(
                Circle().stroke(.white.opacity(0.40), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }

    private var summaryChips: some View {
        HStack(spacing: 8) {
            summaryChip(count: preferencesCount, label: "Preferences")
            summaryChip(count: allergiesCount, label: "Allergies")
        }
    }

    private func summaryChip(count: Int, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(count)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        // 2026-05-24: ultraThinMaterial blended too far into the dark
        // image overlay below the gradient — chips read as invisible
        // against the darkened bottom of the card. Solid semi-opaque
        // white tint guarantees visibility on any image.
        .background(Color.white.opacity(0.18), in: Capsule())
        .overlay(
            Capsule().stroke(.white.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }

    private var editPill: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer()
                HStack(spacing: 4) {
                    Text("Edit")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().stroke(.white.opacity(0.25), lineWidth: 1)
                )
            }
            Spacer()
        }
        .padding(12)
    }
}
