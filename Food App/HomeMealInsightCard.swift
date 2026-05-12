import SwiftUI

/// Floating card shown above the home dock when the most recently logged
/// meal conflicts with the user's diet preferences or allergies.
struct RecentFlaggedMealCard: View {
    let logs: [DayLogEntry]
    let contextKey: String
    @Binding var dismissedLogIds: Set<String>

    @State private var visibleEntry: DayLogEntry?
    @State private var visibleFlags: [DietaryFlag] = []
    @State private var visibleContextKey: String?

    private var mostRecentFlagged: DayLogEntry? {
        // `logs` is server-ordered ASC by loggedAt — last one is the freshest.
        logs.last(where: { entry in
            (entry.dietaryFlags?.isEmpty == false) && !dismissedLogIds.contains(entry.id)
        })
    }

    private var mostRecentFlaggedID: String? {
        mostRecentFlagged?.id
    }

    var body: some View {
        Group {
            if let entry = visibleEntry, !visibleFlags.isEmpty {
                FloatingInsightCard(
                    entry: entry,
                    flags: visibleFlags,
                    onDismiss: {
                        dismissedLogIds.insert(entry.id)
                        visibleEntry = nil
                        visibleFlags = []
                        visibleContextKey = nil
                        RecentFlaggedMealCard.persistDismissedLogIds(dismissedLogIds)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.58, dampingFraction: 0.88), value: visibleEntry?.id)
        .onAppear {
            syncVisibleCard(clearWhenMissing: false)
        }
        .onChange(of: mostRecentFlaggedID) { _, _ in
            syncVisibleCard(clearWhenMissing: false)
        }
        .onChange(of: contextKey) { _, _ in
            syncVisibleCard(clearWhenMissing: true)
        }
    }

    // MARK: - Persistence helpers

    private static let dismissedKey = "food-app.insight.dismissed.v1"

    static func loadDismissedLogIds(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: dismissedKey) ?? [])
    }

    static func persistDismissedLogIds(_ ids: Set<String>, defaults: UserDefaults = .standard) {
        defaults.set(Array(ids), forKey: dismissedKey)
    }

    private func syncVisibleCard(clearWhenMissing: Bool) {
        if let entry = mostRecentFlagged,
           let flags = entry.dietaryFlags,
           !flags.isEmpty {
            visibleEntry = entry
            visibleFlags = flags
            visibleContextKey = contextKey
        } else if clearWhenMissing || visibleContextKey != contextKey {
            visibleEntry = nil
            visibleFlags = []
            visibleContextKey = nil
        }
    }
}

// MARK: - Floating card

private let insightOrange = Color(red: 0.96, green: 0.38, blue: 0.08)
private let insightAmber = Color(red: 1.00, green: 0.67, blue: 0.24)

private struct FloatingInsightCard: View {
    let entry: DayLogEntry
    let flags: [DietaryFlag]
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerOffset: CGFloat = -0.6
    @State private var hasShimmered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, insightOrange)
                .shadow(color: insightOrange.opacity(0.24), radius: 8, y: 3)
                .accessibilityHidden(true)

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
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(displayName). \(subtitleSentence)"))

            Spacer(minLength: 0)

            AppCloseButton(
                action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                },
                visualSize: 36,
                hitSize: 44,
                accessibilityLabel: "Dismiss insight"
            )
            .accessibilityHint(Text("Keeps this food preference note hidden."))
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 14)
        .background(cardBackground)
        .overlay(shimmerOverlay)
        .overlay(cardStroke)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .compositingGroup()
        .shadow(color: insightOrange.opacity(0.16), radius: 20, y: 10)
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 7)
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

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            insightAmber.opacity(0.20),
                            insightOrange.opacity(0.11),
                            Color(.systemBackground).opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        insightAmber.opacity(0.70),
                        insightOrange.opacity(0.40),
                        .white.opacity(0.46)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )
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
        guard !reduceMotion else { return }
        guard !hasShimmered else { return }
        hasShimmered = true
        // Slight delay so the slide-up transition settles before the sweep
        // begins; otherwise both motions compete and the shimmer is missed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeInOut(duration: 0.9)) {
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
