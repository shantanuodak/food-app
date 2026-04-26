import SwiftUI

/// Floating glass-effect card shown above the home dock when the most
/// recently logged meal conflicts with the user's diet preferences or
/// allergies.
///
/// Design constraints (per design feedback):
/// - **One card at a time** — even if multiple saved meals have flags,
///   only the most-recently-saved unflagged-by-user one renders.
/// - **Glass material** matches the existing dock's `.glassEffect` so
///   the card visually belongs to the floating-controls layer.
/// - **Compact, single line** — meal name + a deduped human rule
///   summary. No banner stacks, no scolding header.
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

private struct FloatingInsightCard: View {
    let entry: DayLogEntry
    let flags: [DietaryFlag]
    let onDismiss: () -> Void

    private var isCritical: Bool { flags.contains(where: { $0.isCritical }) }
    private var iconName: String { isCritical ? "exclamationmark.triangle.fill" : "info.circle.fill" }
    private var iconColor: Color { isCritical ? .red : .orange }

    /// Dedupe rules per item — if "peanut chat" matches both `peanuts`
    /// allergy and a vegan rule, we want one card with both labels, not two.
    private var humanRulesSummary: String {
        let dedupedKeys: [String] = {
            var seen = Set<String>()
            var ordered: [String] = []
            for flag in flags {
                if !seen.contains(flag.ruleKey) {
                    seen.insert(flag.ruleKey)
                    ordered.append(flag.ruleKey)
                }
            }
            return ordered
        }()
        return dedupedKeys.map(humanRule).joined(separator: ", ")
    }

    /// Pick the best display name: the parsed item name from the first
    /// flag (closest to what the user typed and what conflicted), falling
    /// back to the raw input.
    private var displayName: String {
        flags.first?.itemName ?? entry.rawText
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.16))
                    .frame(width: 32, height: 32)
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(humanRulesSummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss insight"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(isCritical ? "Critical." : "Heads up.") \(displayName), \(humanRulesSummary).")
        )
    }

    private func humanRule(_ ruleKey: String) -> String {
        switch ruleKey {
        case "peanuts": return "peanut allergy"
        case "tree_nuts": return "tree nut allergy"
        case "gluten": return "gluten / wheat"
        case "dairy": return "dairy"
        case "eggs": return "eggs"
        case "shellfish": return "shellfish"
        case "fish": return "fish"
        case "soy": return "soy"
        case "sesame": return "sesame"
        case "vegetarian": return "non-vegetarian"
        case "vegan": return "non-vegan"
        case "pescatarian": return "non-pescatarian"
        case "gluten_free": return "gluten / wheat"
        case "dairy_free": return "dairy"
        case "halal": return "non-halal"
        default: return ruleKey.replacingOccurrences(of: "_", with: " ")
        }
    }
}
