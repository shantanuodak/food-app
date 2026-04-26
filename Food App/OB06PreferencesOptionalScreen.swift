import SwiftUI

/// Self-contained preferences + allergies screen. Matches the visual
/// vocabulary of the other "modern" onboarding screens (OB02b, OB05) —
/// instrument-serif headline, secondary subhead, capsule pills laid out in
/// a flowing line-wrapping grid, single centered CTA at the bottom. No
/// progress bar, no value cards, no skip button.
struct OB06PreferencesOptionalScreen: View {
    @Binding var preferences: Set<PreferenceChoice>
    @Binding var allergies: Set<AllergyChoice>
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        ZStack {
            OnboardingStaticBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Headline + subhead — typography matches OB02b/OB05.
                        VStack(spacing: 6) {
                            Text("Food preferences")
                                .font(OnboardingTypography.instrumentSerif(style: .regular, size: 41))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                                .multilineTextAlignment(.center)

                            Text("Personalize suggestions and flag conflicts.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(OnboardingGlassTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)

                        // Diet section — label and pills both centered.
                        VStack(alignment: .center, spacing: 10) {
                            sectionLabel("Diet")
                            FlowingPillSelector(
                                options: PreferenceChoice.allCases,
                                selected: $preferences,
                                exclusiveOption: .noPreference
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .opacity(appeared ? 1 : 0)

                        // Allergies section — label and pills both centered.
                        VStack(alignment: .center, spacing: 10) {
                            sectionLabel("Allergies")
                            FlowingPillSelector(
                                options: AllergyChoice.allCases,
                                selected: $allergies,
                                exclusiveOption: nil
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .opacity(appeared ? 1 : 0)

                        Spacer(minLength: 24)
                    }
                    .padding(.bottom, 12)
                }

                // Centered CTA — matches OB02b/OB05 vocabulary.
                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text("Next")
                            .font(.system(size: 16, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(OnboardingGlassTheme.ctaForeground)
                    .frame(width: 220, height: 60)
                    .background(OnboardingGlassTheme.ctaBackground, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            // Reset on every appearance so back-and-forward navigation
            // replays the entrance animation (same pattern as OB02b).
            appeared = false
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.4)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - Sub-views

    private var topBar: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white)
                            .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
                    )
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OnboardingGlassTheme.textMuted)
            .textCase(.uppercase)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }
}

// MARK: - FlowingPillSelector

/// Multi-select pill bank that wraps its chips left-to-right and centers
/// each line. Idle and selected pills share the same fill — selection is
/// communicated by a leading black checkmark plus a slightly darker
/// border. Keeping the fill identical means the pill bank doesn't compete
/// visually with the solid-black "Next" CTA below.
///
/// Optional `exclusiveOption` clears the rest when tapped (used by "No
/// preference").
private struct FlowingPillSelector<Option: ChipOption>: View {
    let options: [Option]
    @Binding var selected: Set<Option>
    let exclusiveOption: Option?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 8) {
            ForEach(options) { option in
                let isSelected = selected.contains(option)
                pill(for: option, isSelected: isSelected)
                    .onTapGesture { toggle(option) }
            }
        }
        .animation(.easeOut(duration: 0.18), value: selected)
    }

    @ViewBuilder
    private func pill(for option: Option, isSelected: Bool) -> some View {
        // Idle pills are text-only with symmetric 14pt padding — no
        // reserved checkmark slot, so there's no leading whitespace.
        // Selected pills grow slightly to show the leading checkmark;
        // the parent FlowLayout's `.animation(.easeOut(0.18))` smooths
        // the resize on tap.
        HStack(spacing: 6) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(checkmarkColor)
                    .transition(.scale.combined(with: .opacity))
            }

            Text(option.title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(textColor(isSelected: isSelected))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous).fill(idleFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    strokeColor(isSelected: isSelected),
                    lineWidth: 1
                )
        )
        .contentShape(Capsule(style: .continuous))
    }

    private var idleFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.55)
    }

    private var checkmarkColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private func textColor(isSelected: Bool) -> Color {
        if isSelected {
            return OnboardingGlassTheme.textPrimary
        }
        return OnboardingGlassTheme.textMuted
    }

    private func strokeColor(isSelected: Bool) -> Color {
        // Selected pills get a subtle but slightly more visible border —
        // same shape language as idle, just enough contrast to read as "on"
        // alongside the checkmark. No fill change, so the bank doesn't
        // visually compete with the black Next button below.
        if isSelected {
            return colorScheme == .dark
                ? Color.white.opacity(0.45)
                : Color.black.opacity(0.30)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.12)
    }

    private func toggle(_ option: Option) {
        if let exclusive = exclusiveOption, option == exclusive {
            selected = selected.contains(exclusive) ? [] : [exclusive]
            return
        }
        if let exclusive = exclusiveOption {
            selected.remove(exclusive)
        }
        if selected.contains(option) {
            selected.remove(option)
        } else {
            selected.insert(option)
        }
    }
}

// MARK: - FlowLayout

/// Lays subviews out left-to-right, wrapping to the next line when the
/// current line is full. Each line is centered horizontally within the
/// available width — the user wanted the pills to read as a centered,
/// justified bank rather than left-anchored. Lightweight stand-in for
/// SwiftUI's missing native flow layout.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 10

    /// Internal helper: groups subviews into lines based on a max width,
    /// returning the index ranges and per-line dimensions. Used by both
    /// sizeThatFits and placeSubviews so they can't disagree.
    private func computeLines(subviews: Subviews, maxWidth: CGFloat) -> [(range: Range<Int>, totalWidth: CGFloat, height: CGFloat)] {
        var lines: [(range: Range<Int>, totalWidth: CGFloat, height: CGFloat)] = []
        var lineStart = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let widthIfAdded = lineWidth == 0 ? size.width : (lineWidth + spacing + size.width)
            if lineWidth > 0, widthIfAdded > maxWidth {
                lines.append((range: lineStart..<index, totalWidth: lineWidth, height: lineHeight))
                lineStart = index
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth = widthIfAdded
                lineHeight = max(lineHeight, size.height)
            }
        }
        if lineStart < subviews.count {
            lines.append((range: lineStart..<subviews.count, totalWidth: lineWidth, height: lineHeight))
        }
        return lines
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = computeLines(subviews: subviews, maxWidth: maxWidth)
        let totalHeight = lines.reduce(CGFloat(0)) { acc, line in acc + line.height } +
            (lines.isEmpty ? 0 : CGFloat(lines.count - 1) * lineSpacing)
        return CGSize(
            width: proposal.width ?? (lines.map(\.totalWidth).max() ?? 0),
            height: totalHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = computeLines(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for line in lines {
            // Center each line: leftover horizontal space is split evenly
            // on either side, so the row of pills sits in the middle of
            // the available width.
            let leftover = max(0, bounds.width - line.totalWidth)
            var x = bounds.minX + leftover / 2

            for index in line.range {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }
}
