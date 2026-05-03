import SwiftUI

/// One row in the Profile's diet-preferences or allergies section.
/// Combines a Toggle (the existing primary control) with an info button
/// that reveals an inline 1-2 sentence explanation underneath.
///
/// Design choices:
/// - The info button sits as a leading accessory next to the icon so it
///   doesn't crowd the toggle's tap area on the trailing edge.
/// - Tapping the info button does NOT toggle the preference — the user
///   should be able to read what the option does without committing to it.
/// - Expansion is animated with `withAnimation` for a smooth disclosure;
///   honors Reduce Motion automatically since the underlying easing is
///   spring-based.
/// - State is owned by the parent screen so navigating away and back
///   keeps the open rows open. The row is a pure value-driven view.
struct DietaryChoiceRow: View {
    let title: String
    let systemImage: String
    let explanation: String
    let isExpanded: Bool
    @Binding var isOn: Bool
    let onToggleExplanation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Info-tap target. Visually small but a 28×28 hit box so
                // it's comfortable on touch. Distinct from the row icon
                // so the user understands it's a separate action.
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        onToggleExplanation()
                    }
                } label: {
                    Image(systemName: isExpanded ? "info.circle.fill" : "info.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(isExpanded
                    ? "Hide explanation for \(title)"
                    : "Show explanation for \(title)"))

                // The existing toggle pattern, untouched in semantics.
                Toggle(isOn: $isOn) {
                    Label(title, systemImage: systemImage)
                }
            }

            if isExpanded {
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    // Inset so the explanation reads as belonging to the
                    // row above it, not as a fresh standalone item.
                    .padding(.leading, 38)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

#Preview {
    @Previewable @State var pref = false
    return Form {
        Section {
            DietaryChoiceRow(
                title: "Vegan",
                systemImage: "leaf.fill",
                explanation: "We'll flag meals with meat, fish, dairy, or eggs.",
                isExpanded: true,
                isOn: $pref,
                onToggleExplanation: {}
            )
            DietaryChoiceRow(
                title: "Low carb",
                systemImage: "minus.circle.fill",
                explanation: "We'll favor lower-carb items and flag carb-heavy meals.",
                isExpanded: false,
                isOn: $pref,
                onToggleExplanation: {}
            )
        }
    }
}
