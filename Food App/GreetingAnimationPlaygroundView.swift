//
//  GreetingAnimationPlaygroundView.swift
//  Food App
//
//  Admin-only debug screen — renders every greeting animation in the
//  rotation, grouped by time-of-day slot, plus a card showing what the
//  resolver would pick right now for the signed-in user.
//
//  Useful for QA-ing the animation set without waiting for time-of-day
//  transitions. The "Replay all" button forces every animation view to
//  re-init so periodic ones (peek, sun, moon, sprout, pancakes,
//  confetti — currently on a 30s pause between plays) fire again
//  immediately.
//

import SwiftUI

struct GreetingAnimationPlaygroundView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appStore: AppStore

    /// Changes whenever the user taps Replay. Used as the View's `id`
    /// so SwiftUI tears down and re-creates every animation view —
    /// which restarts each `Task { while !cancelled }` loop from its
    /// first stage.
    @State private var replayKey = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    currentlyShowingCard
                    replayButton
                    ForEach(orderedSlots, id: \.self) { slot in
                        slotSection(slot)
                    }
                }
                .padding(.bottom, 32)
                .id(replayKey)
            }
            .navigationTitle("Greeting animations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var orderedSlots: [GreetingSlot] {
        [.morning, .anytime, .evening, .night, .milestone]
    }

    private var currentlyShowingCard: some View {
        let resolved = GreetingAnimationResolver.resolve(
            userId: appStore.authSessionStore.session?.userID,
            date: Date()
        )

        return VStack(alignment: .leading, spacing: 10) {
            Text("Resolver pick · right now")
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                GreetingAnimationView(animation: resolved.animation)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(resolved.animation.rawValue.capitalized)
                        .font(.system(size: 17, weight: .bold))
                    HStack(spacing: 6) {
                        slotChip(resolved.slot)
                        Text("·").foregroundStyle(.secondary)
                        Text(formattedTime)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var replayButton: some View {
        Button {
            replayKey = UUID()
        } label: {
            Label("Replay all animations", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
    }

    private func slotSection(_ slot: GreetingSlot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                slotChip(slot)
                Text(slotWindow(slot))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(slot.pool) { animation in
                    animationCard(animation, in: slot)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Animation card

    private func animationCard(_ animation: GreetingAnimation, in slot: GreetingSlot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                GreetingAnimationView(animation: animation)
                    .frame(width: 28, height: 28)
                    .padding(10)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(animation.rawValue.capitalized)
                        .font(.system(size: 15, weight: .semibold))
                    Text(animationDescription(animation))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            // In-context preview — what the chip actually looks like with
            // this animation + slot-appropriate greeting prefix.
            HStack(spacing: 6) {
                GreetingAnimationView(animation: animation)
                Text("\(slot.greetingPrefix), Tester")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Helpers

    private func slotChip(_ slot: GreetingSlot) -> some View {
        Text(slotLabel(slot))
            .font(.system(size: 11, weight: .bold))
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(slotColor(slot).opacity(0.15))
            .foregroundStyle(slotColor(slot))
            .clipShape(Capsule())
    }

    private func slotLabel(_ slot: GreetingSlot) -> String {
        switch slot {
        case .morning:   return "🌅 Morning"
        case .anytime:   return "☀️ Anytime"
        case .evening:   return "🌆 Evening"
        case .night:     return "🌙 Night"
        case .milestone: return "🎉 Milestone"
        }
    }

    private func slotWindow(_ slot: GreetingSlot) -> String {
        switch slot {
        case .morning:   return "05:00 – 11:00"
        case .anytime:   return "11:00 – 18:00"
        case .evening:   return "18:00 – 21:00"
        case .night:     return "21:00 – 05:00"
        case .milestone: return "Override on streak / goal hit"
        }
    }

    private func slotColor(_ slot: GreetingSlot) -> Color {
        switch slot {
        case .morning:   return Color(red: 0.79, green: 0.55, blue: 0.10)
        case .anytime:   return Color(red: 0.23, green: 0.36, blue: 0.65)
        case .evening:   return Color(red: 0.43, green: 0.25, blue: 0.67)
        case .night:     return Color(red: 0.35, green: 0.27, blue: 0.52)
        case .milestone: return Color(red: 0.72, green: 0.29, blue: 0.18)
        }
    }

    private func animationDescription(_ a: GreetingAnimation) -> String {
        switch a {
        case .wave:     return "Continuous slow rotation."
        case .peek:     return "Pops up + wiggles + drops. 30s rest between cycles."
        case .dog:      return "Continuous head bob + tail wag."
        case .heart:    return "Continuous double-beat pulse with overshoot."
        case .sparkle:  return "Continuous twinkle + slow rotate."
        case .sprout:   return "Stem grows + leaves unfurl. 30s rest."
        case .coffee:   return "Continuous staggered steam wisps."
        case .pancakes: return "3 pancakes drop in sequence + syrup. 30s rest."
        case .sun:      return "Rises + holds + sets. 30s rest."
        case .zzz:      return "Continuous staggered z's drifting up."
        case .moon:     return "Rises + holds + sets. Star twinkle stays continuous."
        case .confetti: return "8 mixed-shape bits burst with gravity arc. 30s rest."
        }
    }

    private var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: Date())
    }
}
