import SwiftUI

/// A small contextual banner shown on the home logging screen below a saved
/// meal that conflicts with the user's diet preferences or allergies.
///
/// Visual language matches the rest of the home screen (system semantic
/// colors, light tinted backgrounds), NOT the onboarding glass theme.
///
/// Severity drives the look:
/// - `critical` (allergy): red triangle + soft red tint
/// - `warning` (diet preference): orange info icon + soft orange tint
///
/// Tap to expand and see all flag details. Long-press to dismiss for that
/// specific saved log (persisted in UserDefaults so the card stays hidden
/// across app launches and day-swipes).
struct HomeMealInsightCard: View {
    let serverLogId: String
    let rawText: String
    let flags: [DietaryFlag]
    let onDismiss: (String) -> Void

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Worst severity wins for the headline tint.
    private var isCritical: Bool { flags.contains(where: { $0.isCritical }) }
    private var iconName: String { isCritical ? "exclamationmark.triangle.fill" : "info.circle.fill" }
    private var accentColor: Color { isCritical ? .red : .orange }
    private var tint: Color { accentColor.opacity(0.08) }
    private var stroke: Color { accentColor.opacity(0.22) }

    /// Headline summarizing the highest-severity flag.
    private var headline: String {
        guard let primary = flags.first(where: { $0.isCritical }) ?? flags.first else {
            return ""
        }
        return "Heads up — \(primary.itemName) contains \(humanRule(primary))"
    }

    private var moreCount: Int { max(0, flags.count - 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 8 : 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 22)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    if !expanded && moreCount > 0 {
                        Text("\(moreCount) more conflict\(moreCount == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if flags.count > 1 {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 22, minHeight: 22)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(flags.enumerated()), id: \.offset) { _, flag in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(flag.isCritical ? Color.red : Color.orange)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text("\(flag.itemName) → \(humanRule(flag))")
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.leading, 32)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            guard flags.count > 1 else { return }
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.2)) {
                expanded.toggle()
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDismiss(serverLogId)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isCritical ? [.isStaticText, .isHeader] : .isStaticText)
        .accessibilityHint("Long press to dismiss this insight for this meal.")
    }

    private var accessibilityDescription: String {
        let severityWord = isCritical ? "Critical." : "Heads up."
        let detail = flags.map { "\($0.itemName) \(humanRule($0))" }.joined(separator: ", ")
        return "\(severityWord) \(detail)"
    }

    private func humanRule(_ flag: DietaryFlag) -> String {
        switch flag.ruleKey {
        case "peanuts": return "peanut allergy"
        case "tree_nuts": return "tree nut allergy"
        case "gluten": return "gluten / wheat"
        case "dairy": return "dairy"
        case "eggs": return "eggs"
        case "shellfish": return "shellfish"
        case "fish": return "fish"
        case "soy": return "soy"
        case "sesame": return "sesame"
        case "vegetarian": return "non-vegetarian item"
        case "vegan": return "non-vegan item"
        case "pescatarian": return "non-pescatarian item"
        case "gluten_free": return "gluten / wheat"
        case "dairy_free": return "dairy"
        case "halal": return "non-halal item"
        default: return flag.ruleKey.replacingOccurrences(of: "_", with: " ")
        }
    }
}

/// Loops over the saved logs for the day and renders one insight card per
/// log entry that has unflagged flags (i.e. flags whose serverLogId hasn't
/// been dismissed yet).
struct HomeMealInsightSection: View {
    let logs: [DayLogEntry]
    @Binding var dismissedLogIds: Set<String>
    let onDismiss: (String) -> Void

    private static let dismissedKey = "food-app.insight.dismissed.v1"

    /// UserDefaults helper — call from the home view to load dismissed ids on appear.
    static func loadDismissedLogIds(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: dismissedKey) ?? [])
    }

    static func persistDismissedLogIds(_ ids: Set<String>, defaults: UserDefaults = .standard) {
        defaults.set(Array(ids), forKey: dismissedKey)
    }

    var body: some View {
        let active = logs.filter { entry in
            (entry.dietaryFlags?.isEmpty == false) && !dismissedLogIds.contains(entry.id)
        }

        if !active.isEmpty {
            VStack(spacing: 10) {
                ForEach(active) { entry in
                    HomeMealInsightCard(
                        serverLogId: entry.id,
                        rawText: entry.rawText,
                        flags: entry.dietaryFlags ?? [],
                        onDismiss: { id in
                            dismissedLogIds.insert(id)
                            HomeMealInsightSection.persistDismissedLogIds(dismissedLogIds)
                            onDismiss(id)
                        }
                    )
                }
            }
        }
    }
}
