import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// `FocalWheelPicker` — a depth-of-field wheel picker for whole-number values.
///
/// Visual model: shallow-depth-of-field camera lens. The selected value sits in
/// focus at the centre; rows further from the centre become smaller, more
/// transparent, and progressively blurred — like a shallow camera focus.
///
/// **Motion model: 1:1 continuous tracking.** The wheel's vertical position is
/// strictly proportional to finger translation — fast finger means fast scroll,
/// slow finger means slow scroll. Every visual property (font size, opacity,
/// blur, vertical offset) is a *continuous* function of fractional distance
/// from the centre, so as the wheel rolls, focus shifts smoothly across rows
/// rather than snapping in discrete steps. A spring only fires once: at the
/// end of the drag, to settle the residual partial-row offset to zero.
///
/// This is the canonical wheel-picker pattern for the Food App. Reuse this
/// component anywhere a whole-number scalar is selected — do not re-implement
/// the visuals locally. See `docs/UI_COMPONENTS.md` for the full design spec.
///
/// Used by:
/// - `OB03AgeScreen` ("How old are you?")
/// - `OB03BaselineScreen` ("How tall are you?", "How much do you weigh?")
struct FocalWheelPicker: View {
    let value: Int
    let range: ClosedRange<Int>
    let onSet: (Int) -> Void
    var pickerWidth: CGFloat = 220

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Recorded once at drag start; reset on drag end.
    @State private var dragStartValue: Int?
    /// Pixel offset of the wheel from rest (signed; positive = pulled down =
    /// lower values shifting toward the centre). Always 0 when not dragging.
    @State private var dragOffset: CGFloat = 0

    // MARK: - Layout tokens
    //
    // rowHeight controls drag sensitivity only: 1 rowHeight of finger drag = 1
    // value step. 60pt feels close to the iOS native picker.
    //
    // rowSpacing controls the *visual* gap between rendered rows. Decoupled
    // from rowHeight so we can give the numbers more breathing room without
    // changing how fast the wheel scrolls under the finger.

    private let rowHeight: CGFloat = 60
    private let rowSpacing: CGFloat = 70
    private let visibleRadius: Int = 3 // ±3 rendered rows; outer ones clipped by frame

    // MARK: - Body

    var body: some View {
        ZStack {
            ForEach(visibleValues, id: \.self) { val in
                row(for: val)
            }
        }
        .frame(width: pickerWidth, height: rowSpacing * 5)
        .clipped()
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .accessibilityElement()
        .accessibilityLabel(Text("Picker"))
        .accessibilityValue(Text("\(value)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                let next = min(value + 1, range.upperBound)
                if next != value { onSet(next) }
            case .decrement:
                let prev = max(value - 1, range.lowerBound)
                if prev != value { onSet(prev) }
            @unknown default:
                break
            }
        }
    }

    // MARK: - Continuous position
    //
    // The single source of truth for "what's at the centre right now."
    // Equals `value` exactly when the wheel is at rest. During drag it
    // takes a continuous fractional value as the wheel rolls.

    private var visualPosition: CGFloat {
        CGFloat(value) - dragOffset / rowHeight
    }

    private var visibleValues: [Int] {
        let centerInt = Int(visualPosition.rounded())
        let lowerBound = max(centerInt - visibleRadius, range.lowerBound)
        let upperBound = min(centerInt + visibleRadius, range.upperBound)
        guard lowerBound <= upperBound else { return [] }
        return Array(lowerBound...upperBound)
    }

    @ViewBuilder
    private func row(for val: Int) -> some View {
        let delta = CGFloat(val) - visualPosition  // signed, fractional
        let absDelta = abs(delta)

        Text("\(val)")
            .font(.system(size: fontSize(absDelta: absDelta), weight: .bold, design: .rounded))
            .monospacedDigit() // stable horizontal layout regardless of digit widths
            .foregroundStyle(OnboardingGlassTheme.textPrimary.opacity(opacity(absDelta: absDelta)))
            .blur(radius: blurRadius(absDelta: absDelta))
            .offset(y: delta * rowSpacing)
    }

    // MARK: - Continuous visual scaling
    //
    // Each property is a smooth function of fractional distance from centre.
    // No discrete buckets — as the wheel rolls, every property interpolates
    // continuously, producing a fluid focus shift instead of stepped pops.

    private func fontSize(absDelta: CGFloat) -> CGFloat {
        // 84pt at centre, decaying to 36pt by distance 2; clamped beyond.
        let t = min(absDelta / 2.0, 1.0)
        return 84 - (84 - 36) * t
    }

    private func opacity(absDelta: CGFloat) -> Double {
        // 1.0 at centre, 0 by distance 2.5. Quadratic ease-out keeps adjacent
        // rows readable while making the falloff at the edges feel natural.
        let t = min(Double(absDelta) / 2.5, 1.0)
        return 1.0 - t * t
    }

    private func blurRadius(absDelta: CGFloat) -> CGFloat {
        // 0 at centre, 4pt by distance 3. Quadratic ease-in keeps the centre
        // and immediate neighbours sharp; only distant rows pick up real blur.
        let t = min(absDelta / 3.0, 1.0)
        return t * t * 4
    }

    // MARK: - Animation token
    //
    // The Focal Spring only runs at drag-end to settle the residual partial-row
    // offset to zero. During drag, motion is strictly 1:1 with the finger — no
    // animation, no curve. That's what produces the native-picker feel.

    /// Standard Focal Spring — used for the drag-end settle only.
    /// `response: 0.45, dampingFraction: 0.92` produces a gentle ~440 ms glide
    /// to rest with effectively no overshoot.
    private var focalSpring: Animation {
        if reduceMotion {
            return .linear(duration: 0.14)
        }
        return .spring(response: 0.45, dampingFraction: 0.92)
    }

    // MARK: - Gesture
    //
    // The picker tracks finger position 1:1. Each integer crossing fires a
    // light haptic and reports the new value via onSet. Crucially, no
    // animation runs during drag — the wheel's position is direct.

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if dragStartValue == nil {
                    dragStartValue = value
                }

                // Continuous candidate position based on total drag from start.
                // Drag DOWN (positive translation) → lower numbers move to centre.
                let start = CGFloat(dragStartValue ?? value)
                let candidatePosition = start - gesture.translation.height / rowHeight

                // Clamp to range. Hard-stop at boundaries (no rubber band).
                let clampedPosition = min(
                    max(candidatePosition, CGFloat(range.lowerBound)),
                    CGFloat(range.upperBound)
                )

                // Which integer is currently the "selected" one — i.e. the one
                // closest to centre? That's the one we report via onSet.
                let snappedValue = Int(clampedPosition.rounded(.toNearestOrAwayFromZero))

                if snappedValue != value {
                    onSet(snappedValue)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                // Re-anchor dragOffset against the (now-current) value so that
                // visualPosition exactly equals clampedPosition.
                //   visualPosition = value - dragOffset/rowHeight
                //   ⇒  dragOffset  = (value - visualPosition) * rowHeight
                // We use snappedValue here because that's what `value` will be
                // after the onSet propagates back through the parent.
                dragOffset = (CGFloat(snappedValue) - clampedPosition) * rowHeight
            }
            .onEnded { _ in
                dragStartValue = nil
                // Spring the residual partial-row offset back to zero. This is
                // the *only* animation in the entire interaction.
                withAnimation(focalSpring) {
                    dragOffset = 0
                }
            }
    }
}

// MARK: - Back-compat typealias

/// Deprecated. Retained so existing call sites in `OB03AgeScreen` and
/// `OB03BaselineScreen` continue to compile. Migrate to `FocalWheelPicker`
/// at the next opportunity.
typealias SmoothScrollPicker = FocalWheelPicker
