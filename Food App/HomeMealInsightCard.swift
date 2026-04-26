import SwiftUI

/// Floating glass-effect card shown above the home dock when the most
/// recently logged meal conflicts with the user's diet preferences or
/// allergies.
///
/// Design (2026-04-26 refresh):
/// - **Text-only.** The leading icon (orange info / red triangle in v1) is
///   gone — colour-coded severity icons read as scolding and were the
///   biggest source of visual weight on the home screen.
/// - **Purple-tinted glass.** Frosted `.ultraThinMaterial` base + a soft
///   purple wash on the fill + a 1.2 pt purple stroke. Same purple as the
///   leading stop in `aiShimmerGradient` (HomeFlowComponents.swift) so
///   the card reads as part of the same AI / insight visual family.
/// - **Shimmer on appear.** A one-shot diagonal sweep fires after the
///   slide-up transition settles, matching the shimmer pattern used on
///   voice-inserted food rows and camera-parse reveals.
/// - **Sentence subtitle.** Replaces the noun-phrase summary
///   (`peanut allergy, non-vegan`) with full sentences (`Contains
///   peanuts. Not vegan.`) so the card reads as guidance rather than
///   a tag list.
/// - **One card at a time** — even if multiple saved meals have flags,
///   only the most-recently-saved unflagged-by-user one renders.
struct RecentFlaggedMealCard: View {
    let logs: [DayLogEntry]
    @Binding var dismissedLogIds: Set<String>

    private var mostRecentFlagged: DayLogEntry? {
        // `logs` is server-ordered ASC by loggedAt — last one is the freshest.
        logs.last(where: { entry in
            (entry.dietaryFlags?.isEmpty == false) && !dismissedLogIds.contains(entry.id)
        })
    }

    var body: some View {
        Group {
            if let entry = mostRecentFlagged,
               let flags = entry.dietaryFlags,
               !flags.isEmpty {
                FloatingInsightCard(
                    entry: entry,
                    flags: flags,
                    onDismiss: {
                        dismissedLogIds.insert(entry.id)
                        RecentFlaggedMealCard.persistDismissedLogIds(dismissedLogIds)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: mostRecentFlagged?.id)
    }

    // MARK: - Persistence helpers

    private static let dismissedKey = "food-app.insight.dismissed.v1"

    static func loadDismissedLogIds(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: dismissedKey) ?? [])
    }

    static func persistDismissedLogIds(_ ids: Set<String>, defaults: UserDefaults = .standard) {
        defaults.set(Array(ids), forKey: dismissedKey)
    }
}

// MARK: - Floating card

/// Brand purple for insight surfaces. Matches the leading stop in
/// `aiShimmerGradient` (HomeFlowComponents.swift). Kept inline here so
/// this file stays standalone; if a third surface needs the same colour,
/// promote both to a shared `Color+Brand` file.
private let insightPurple = Color(red: 0.58, green: 0.29, blue: 0.98)

private struct FloatingInsightCard: View {
    let entry: DayLogEntry
    let flags: [DietaryFlag]
    let onDismiss: () -> Void

    @State private var shimmerOffset: CGFloat = -0.6
    @State private var hasShimmered = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitleSentence)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss insight"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(cardBackground)
        .overlay(shimmerOverlay)
        .overlay(cardStroke)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .compositingGroup()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(displayName). \(subtitleSentence)")
        )
        .onAppear {
            triggerShimmer()
        }
    }

    // MARK: - Background / stroke

    private var cardBackground: some View {
        ZStack {
            // Frosted glass base
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
            // Purple tint wash so the card reads as AI / insight context
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(insightPurple.opacity(0.10))
        }
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(insightPurple.opacity(0.55), lineWidth: 1.2)
    }

    // MARK: - Shimmer
    //
    // Same shape as `InsertShimmerModifier` (HomeFlowComponents.swift) used on
    // voice-inserted food rows: a 55%-wide white sweep travels from
    // off-screen-left to off-screen-right once, on first appear. Source-atop
    // blend keeps the sweep clipped to the card's pixel coverage.

    @ViewBuilder
    private var shimmerOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let sweepWidth = w * 0.55

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.55), location: 0.45),
                    .init(color: .white.opacity(0.85), location: 0.5),
                    .init(color: .white.opacity(0.55), location: 0.55),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: sweepWidth)
            .offset(x: shimmerOffset * (w + sweepWidth) - sweepWidth)
            .blendMode(.sourceAtop)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false)
    }

    private func triggerShimmer() {
        guard !hasShimmered else { return }
        hasShimmered = true
        // Slight delay so the slide-up transition settles before the sweep
        // begins; otherwise both motions compete and the shimmer is missed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeInOut(duration: 0.7)) {
                shimmerOffset = 1.0
            }
        }
    }

    // MARK: - Copy

    /// Best display name: the parsed item name from the first flag (closest
    /// to what the user typed and what conflicted), falling back to raw input.
    private var displayName: String {
        flags.first?.itemName ?? entry.rawText
    }

    /// Deduped rule keys preserving first-seen order, so a meal that hits
    /// both `peanuts` (allergy) and `vegan` (diet) renders one card with both.
    private var dedupedRuleKeys: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for flag in flags {
            if !seen.contains(flag.ruleKey) {
                seen.insert(flag.ruleKey)
                ordered.append(flag.ruleKey)
            }
        }
        return ordered
    }

    /// Single-sentence subtitle. Examples:
    /// - `Contains peanuts.`
    /// - `Not vegan.`
    /// - `Contains peanuts and dairy. Not vegan.`
    private var subtitleSentence: String {
        let allergyTerms = dedupedRuleKeys.compactMap(allergyTerm(_:))
        let dietTerms = dedupedRuleKeys.compactMap(dietTerm(_:))
        let otherTerms = dedupedRuleKeys.compactMap { key -> String? in
            if allergyTerm(key) != nil || dietTerm(key) != nil { return nil }
            return key.replacingOccurrences(of: "_", with: " ")
        }

        var sentences: [String] = []
        if !allergyTerms.isEmpty {
            sentences.append("Contains \(joinTerms(allergyTerms)).")
        }
        if !dietTerms.isEmpty {
            sentences.append("Not \(joinTerms(dietTerms)).")
        }
        if !otherTerms.isEmpty {
            sentences.append("Conflicts with \(joinTerms(otherTerms)).")
        }
        return sentences.joined(separator: " ")
    }

    private func allergyTerm(_ key: String) -> String? {
        switch key {
        case "peanuts": return "peanuts"
        case "tree_nuts": return "tree nuts"
        case "gluten", "gluten_free": return "gluten"
        case "dairy", "dairy_free": return "dairy"
        case "eggs": return "eggs"
        case "shellfish": return "shellfish"
        case "fish": return "fish"
        case "soy": return "soy"
        case "sesame": return "sesame"
        default: return nil
        }
    }

    private func dietTerm(_ key: String) -> String? {
        switch key {
        case "vegetarian": return "vegetarian"
        case "vegan": return "vegan"
        case "pescatarian": return "pescatarian"
        case "halal": return "halal"
        default: return nil
        }
    }

    /// Oxford-comma list join: "a", "a and b", "a, b, and c".
    private func joinTerms(_ terms: [String]) -> String {
        switch terms.count {
        case 0: return ""
        case 1: return terms[0]
        case 2: return "\(terms[0]) and \(terms[1])"
        default:
            let head = terms.dropLast().joined(separator: ", ")
            return "\(head), and \(terms.last!)"
        }
    }
}
