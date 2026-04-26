import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// `SlideToConfirmButton` — a slide-to-confirm pill control.
///
/// Pattern: the user drags a circular thumb from the left edge to the right
/// past a threshold to fire `onConfirm`. Used for **high-intent commitment
/// moments** where a single accidental tap shouldn't trigger the action
/// (e.g. Ready screen "Start logging" — we want the user to make a small
/// deliberate gesture before the onboarding submission fires).
///
/// **Interaction:**
/// - 1:1 finger tracking — drag is direct, no spring during drag.
/// - The track label fades as the thumb moves rightward.
/// - At ≥ `confirmThreshold` of the available travel (default 85 %), the
///   gesture commits: a medium haptic fires, the thumb springs to the end,
///   and `onConfirm` is invoked after a short visual settle.
/// - Released before threshold → snaps back to start with a soft spring.
/// - Re-grab during snap-back is handled (thumb continues from current
///   position, no jump).
///
/// **Accessibility:**
/// - Surfaces as a single Button-trait element to VoiceOver.
/// - VoiceOver activation calls `onConfirm` directly — dragging is
///   impractical under a screen reader so we offer a tap-equivalent.
/// - Reduced motion: snap-back uses a brief linear ease instead of spring.
/// - Disabled state (`@Environment(\.isEnabled)`) dims the control to 50 %
///   and ignores all drag input.
///
/// **Where it's used:**
/// - `OB10ReadyScreen` ("Start logging" — final commit at end of onboarding).
///
/// See `docs/UI_COMPONENTS.md` for the full design spec.
struct SlideToConfirmButton: View {
    let label: String
    let onConfirm: () -> Void

    /// Track height in points. Default 60 pt matches the Onboarding primary
    /// button height for visual continuity with adjacent CTAs.
    var height: CGFloat = 60
    /// Fraction of max travel required to commit. 0.85 = 85 %.
    var confirmThreshold: Double = 0.85

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    @State private var dragOffset: CGFloat = 0
    @State private var dragStartOffset: CGFloat?
    @State private var isConfirmed = false

    /// Diameter of the thumb. 8 pt smaller than `height` (4 pt vertical inset).
    private var thumbSize: CGFloat { height - 8 }

    /// Horizontal padding inset between the thumb and track edges.
    private let thumbInset: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            let maxOffset = max(0, trackWidth - thumbSize - thumbInset * 2)
            let progress: Double = maxOffset > 0
                ? min(max(Double(dragOffset / maxOffset), 0), 1)
                : 0

            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.black)

                // Label — fades as the thumb travels rightward so the
                // user's commitment becomes the dominant visual signal.
                Text(isConfirmed ? "Starting…" : label)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(1.0 - progress * 0.8))
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Image(systemName: isConfirmed ? "checkmark" : "chevron.right")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.black)
                    )
                    .padding(.leading, thumbInset)
                    .offset(x: dragOffset)
                    .gesture(dragGesture(maxOffset: maxOffset))
            }
            .frame(width: trackWidth, height: height)
        }
        .frame(height: height)
        .opacity(isEnabled ? 1.0 : 0.5)
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text("Slide right to confirm, or double-tap to activate."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            // Tap-equivalent for VoiceOver users.
            guard isEnabled, !isConfirmed else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onConfirm()
        }
    }

    // MARK: - Gesture

    private func dragGesture(maxOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled, !isConfirmed else { return }
                // Anchor at drag-start so re-grabbing during snap-back resumes
                // smoothly instead of jumping to translation-0 origin.
                if dragStartOffset == nil {
                    dragStartOffset = dragOffset
                }
                let proposed = (dragStartOffset ?? 0) + value.translation.width
                dragOffset = min(max(proposed, 0), maxOffset)
            }
            .onEnded { _ in
                dragStartOffset = nil
                guard isEnabled, !isConfirmed else { return }

                let crossedThreshold =
                    maxOffset > 0
                    && Double(dragOffset / maxOffset) >= confirmThreshold

                if crossedThreshold {
                    isConfirmed = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(reduceMotion
                                  ? .linear(duration: 0.12)
                                  : .easeOut(duration: 0.18)) {
                        dragOffset = maxOffset
                    }
                    // Brief settle so the user sees the checkmark before the
                    // screen transitions away.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onConfirm()
                    }
                } else {
                    withAnimation(reduceMotion
                                  ? .linear(duration: 0.12)
                                  : .spring(response: 0.35, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }
}
