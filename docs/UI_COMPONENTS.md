# UI Components — Food App

A living catalogue of reusable UI components in the Food App, with the design intent behind each. Reach for this doc whenever you're tempted to re-implement a visual pattern that already has a canonical home in the codebase.

Last updated: 2026-04-26

---

## Onboarding refresh — in progress

A pilot redesign of the onboarding visual language, currently scoped to **OB08 Account screen only**. Direction: **Quiet Wellness** — softer, warmer, flatter than the rest of onboarding (which still uses the animated-gradient + glass language). If the pilot validates well, the rest of onboarding (`OB01–OB07`, `OB09`, `OB10`) follows in a separate pass.

**Status:** Pilot live on `OB08AccountScreen` + `accountRouteView` in `OnboardingView.swift` (2026-04-26). Other onboarding screens still use `OnboardingAnimatedBackground` and the existing glass language; expect a visible style break at the OB07 → OB08 → OB09 transitions until the migration completes.

### Tokens

Live as static properties on `OnboardingGlassTheme` in `OnboardingComponents.swift` so they're available alongside the existing glass tokens during the migration period.

| Token | Light | Dark | Usage |
|---|---|---|---|
| `neutralBackground` | `#FAF7F2` | `#161512` | Static screen background; replaces `OnboardingAnimatedBackground` on migrated screens. |
| `neutralSurface` | `#FFFFFF` | `#1F1E1A` | Card surfaces and button backgrounds. |
| `accentAmber` | `#E8A33D` | `#F0B458` | Single accent — feature icons, stars, focus rings. No gradients on migrated screens. |
| `hairline` | `rgba(0,0,0,0.06)` | `rgba(255,255,255,0.10)` | 1pt borders on cards, buttons, and circle nav buttons. |

### Pattern principles

- **One accent, no gradients.** `accentAmber` is the sole non-neutral colour on a migrated screen. Gradient pairs (`accentStart` × `accentEnd`) are reserved for legacy screens.
- **Flat, hairline-bordered surfaces.** Cards and buttons use `neutralSurface` fills with a 1 pt `hairline` border. Soft shadow (`0 4px 24px rgba(0,0,0,0.04)`) reserved for the primary content card only.
- **Static background.** No animated gradient. The screen-level breathing is handled by spacing, not motion.
- **Motion as confirmation, not decoration.** Entrance fade per element (≤450 ms, eased) is fine; auto-rotating carousels and ambient motion are explicitly disallowed (skill rule §7 `motion-meaning`).
- **Typography is the brand voice.** Keep InstrumentSerif italic for hero headlines (single signature element). Body / labels in SF Pro at the established type scale.

### What's on OB08 today

| Element | Treatment |
|---|---|
| Background | `neutralBackground`, full-bleed, static. |
| Back button | 44×44 circle, `neutralSurface` fill, `hairline` border, no shadow. |
| Hero | "Almost *there*", 36 pt InstrumentSerif (italic on "there"), centred. |
| Subtitle | 16 pt SF, `textSecondary`, centred. *"Save your progress to unlock your personalized plan."* |
| Feature card | Three rows on `neutralSurface` + `hairline` + soft 4 pt shadow; 20 pt vertical gap between rows; no row dividers. |
| Feature row icon | 20 pt SF Symbol in `accentAmber`, no background box (was 40×40 gradient box). |
| Ratings strip | Inline row: 5 amber stars, 1 pt `hairline` divider, label. No surrounding panel. |
| Auth buttons | 60 pt tall (was 96 pt), horizontal icon + label, `neutralSurface` + `hairline` border, 12 pt corner. No multi-layer shadow. |

### Why this direction

- **Health/food apps trend toward calm palettes.** The animated background and gradient icons read as "fitness app circa 2021"; the new direction reads as "thoughtful and trustworthy."
- **Conversion moments don't need motion.** The carousel and animated background were decorative-only motion (skill anti-pattern). Removing them improves perceived quality and reduces cognitive load at the sign-in decision point.
- **Single accent + flat surfaces let typography do the work.** InstrumentSerif italic is the most distinctive thing about the brand voice; it works harder when it's not competing with gradients.

### Migrating another screen

When migrating `OB01–OB07` / `OB09` / `OB10` later:

1. Replace `OnboardingAnimatedBackground()` with `OnboardingGlassTheme.neutralBackground.ignoresSafeArea()`.
2. Replace `.onboardingGlassPanel(...)` modifiers with `neutralSurface` fill + `hairline` border + optional soft shadow.
3. Replace `accentStart` / `accentEnd` gradient pairs with `accentAmber` (single colour).
4. Move any inline copy to `L10n.swift` under the screen's namespace.
5. Add an entry under "What's on [screen] today" in this section.
6. Remove decorative-only animations (auto-rotates, ambient gradient sweeps).

---

## Slide-to-Confirm Button

**Pattern name:** Slide to Confirm
**Component:** `SlideToConfirmButton` — file `Food App/Food App/SlideToConfirmButton.swift`
**Where it's used today:** `OB10ReadyScreen` ("Start logging" — final commit at end of onboarding).

### What it is

A pill-shaped CTA where the user drags a circular thumb from left to right past a threshold (~85 % of the available travel) to fire the action. Replaces a plain tap button when the action is **a high-intent commitment** that shouldn't be triggered by an accidental tap (the final onboarding submission, in this case).

### Why use this instead of a tap button

- **Forces deliberate intent.** A 5–10 cm drag is harder to do by accident than a tap. Good for irreversible actions (submission, delete, sign-out).
- **Telegraphs commitment.** Sliding "all the way" reads as "I really mean it" — useful UX language at moments where you want the user to feel their own conviction (the Ready screen, where they're closing onboarding for good).
- **Removes the need for a secondary "Are you sure?" affordance.** No "Explore app" escape hatch needed below the CTA — the slide *is* the confirmation step.

### Visual + interaction spec

- **Track:** black `Capsule()`, default 60 pt tall, full available width.
- **Label:** the `label` parameter, 17 pt semibold white, centred. **Fades** as the thumb moves rightward (linearly: at full travel, the label sits at 0.2 opacity so it's still legible behind the thumb but no longer competes for attention).
- **Thumb:** white `Circle()`, diameter `height − 8 pt` (so 52 pt for the default 60 pt track). 4 pt inset from each track edge. Carries a chevron-right SF Symbol while idle, swapped for a checkmark on confirm.
- **Drag:** 1:1 with finger. No spring, no animation curve during drag — direct tracking.
- **Threshold:** at ≥ 85 % of max travel (`confirmThreshold` parameter), release commits.
- **Commit visual:** thumb springs to the right edge with a brief ease-out (~180 ms), label flips to "Starting…", icon flips to checkmark, medium haptic fires. After a 200 ms settle the `onConfirm` closure is invoked.
- **Snap-back:** released before threshold → thumb springs back to the start with `spring(response: 0.35, dampingFraction: 0.85)`.
- **Re-grab handling:** if the user grabs the thumb mid-snap-back, the drag resumes from the current position rather than jumping to translation-0 origin. Uses an internal `dragStartOffset` snapshot.

### API

```swift
SlideToConfirmButton(
    label: String,                 // text shown on the track
    onConfirm: () -> Void,         // fires once when threshold is crossed
    height: CGFloat = 60,          // optional; track height
    confirmThreshold: Double = 0.85 // optional; 0…1 fraction of travel
)
```

Honours `@Environment(\.isEnabled)` (dims to 50 %, ignores drag input) and `@Environment(\.accessibilityReduceMotion)` (snap animations collapse to a 120 ms linear ease).

### Accessibility

- Surfaces as a single Button-trait element to VoiceOver.
- VoiceOver activation calls `onConfirm` directly — slider gestures are impractical under a screen reader, so we expose a tap-equivalent through `accessibilityAction`.
- Hint copy: *"Slide right to confirm, or double-tap to activate."*

### When NOT to use this

- Frequent, low-stakes CTAs (Save, Continue, Next). The friction is the point — applying it everywhere makes the app feel laborious.
- Forms with multiple primary actions. A standard button is better when the user might want to back out and pick a different action.
- Anywhere a tap-and-go expectation is established by the surrounding UI.

---

## Focal Wheel Picker

**Pattern name:** Focal Wheel
**Component:** `FocalWheelPicker` — file `Food App/Food App/FocalWheelPicker.swift`
**Animation token:** Focal Spring — `spring(response: 0.45, dampingFraction: 0.92)` — used **only** for the drag-end settle, never during drag
**Back-compat alias:** `typealias SmoothScrollPicker = FocalWheelPicker`

### What it is

A depth-of-field wheel picker for selecting a single whole-number value. The selected value sits in focus at the centre; rows further from the centre get smaller, more transparent, and progressively blurred — like a shallow camera focus.

**Motion model: 1:1 continuous tracking.** The wheel's position follows the finger pixel-for-pixel — fast finger means fast scroll, slow finger means slow scroll. Every visual property (font size, opacity, blur, y-offset) is a *continuous* function of fractional distance from the centre, so as the wheel rolls, focus shifts smoothly across rows. A spring only fires *once*: at drag-end, to settle the residual partial-row offset to zero. **No animation runs during drag** — that's what produces the native-picker feel.

### Why this pattern

A standard iOS `UIPickerView` (or SwiftUI `.pickerStyle(.wheel)`) is functional but feels generic. The Focal Wheel:

- **Establishes a clear focal point.** Blur + opacity gradient + size scaling give a strong "this is the one" cue without needing chrome (no selection band, no separator lines).
- **Communicates motion physically.** The Focal Spring's mild overshoot lands the value with weight rather than snapping. It feels like a real wheel coming to rest.
- **Reads at a glance.** The 86 pt centre value is large enough to confirm a selection from across the screen — useful in onboarding where the user is making a single anchored choice.
- **Stays within Apple HIG.** Spring physics, light haptics on each step, respects `prefers-reduced-motion`, and uses native gesture timing.

### Visual spec

Each property is a **continuous function of fractional distance** from the centre — no discrete buckets. The table below gives the values at the integer-row positions; intermediate fractional positions (during drag) interpolate smoothly between them.

| Distance from centre | Font size | Opacity | Blur radius |
|---|---|---|---|
| 0 (selected)        | 84 pt | 1.00 | 0 pt |
| 1 (adjacent)        | 60 pt | 0.84 | 0.44 pt |
| 2 (distant)         | 36 pt | 0.36 | 1.78 pt |
| 2.5+ (fade boundary) | 36 pt | 0 | 2.78 pt |
| 3+ (clipped)        | 36 pt | 0 | 4 pt |

The exact functions:

- `fontSize(d) = 84 − 48 · clamp(d / 2, 0, 1)` — linear interpolation from 84 → 36.
- `opacity(d) = 1 − (clamp(d / 2.5, 0, 1))²` — quadratic ease-out (slow falloff near centre, faster at the edges).
- `blur(d) = 4 · (clamp(d / 3, 0, 1))²` — quadratic ease-in (centre and immediate neighbours stay sharp; only distant rows pick up real blur).

Other style details:

- Font: `.system(size:, weight: .bold, design: .rounded)` with `.monospacedDigit()` so digit-width changes don't cause horizontal jitter.
- Colour: `OnboardingGlassTheme.textPrimary` modulated by opacity.
- Frame: `pickerWidth × (rowSpacing × 5)`. Default `pickerWidth = 220`, `rowSpacing = 70`.
- **Two layout tokens, deliberately decoupled:**
  - `rowHeight = 60` controls **drag sensitivity** only (1 rowHeight of finger drag = 1 value step). 60 pt is close to the iOS native picker.
  - `rowSpacing = 70` controls **visual spacing** between rendered rows.
  - Decoupling these means you can change the visual breathing room (rowSpacing) without changing how fast the wheel scrolls under the finger (rowHeight), and vice versa.
- Rows beyond ±3 are not rendered. Rows between distance 2.5 and 3 render at opacity 0 with growing blur — this margin keeps SwiftUI's view tree stable during fast drags.

### Interaction spec

- **Drag** vertically to scrub. **1:1 finger tracking.** Each `rowHeight` (60 pt) of drag advances the wheel by one value step. No multipliers, no rubber band, no animation curve during drag — the wheel is welded to the finger.
- **Continuous visual position.** A single `visualPosition: CGFloat = value − dragOffset / rowHeight` drives every visible property. As the user drags, `visualPosition` moves continuously through fractional values; rows slide and re-focus continuously rather than in discrete buckets.
- **Haptic.** Light `UIImpactFeedbackGenerator` fires the moment `visualPosition` crosses a half-step boundary (which is also when `onSet` fires with the new integer).
- **Range clamping.** Hard-stops at `range.lowerBound` and `range.upperBound`. No rubber-band overshoot in the current revision; if a user drags past the boundary, the wheel sits flush against it until the finger comes back into range.
- **Release.** Only here does the Focal Spring run: `dragOffset` springs from its residual partial-row offset back to 0, locking `visualPosition` exactly onto the integer that was already reported via `onSet` during drag.
- **Reduced motion.** When `accessibilityReduceMotion` is on, the Focal Spring degrades to `.linear(duration: 0.14)` — the snap-to-rest stays brief, the bounce never existed in the first place.
- **Accessibility.** The picker is a single accessibility element with adjustable action support — VoiceOver users can swipe up/down to increment/decrement.

### API

```swift
FocalWheelPicker(
    value: Int,            // current selection
    range: ClosedRange<Int>,
    onSet: (Int) -> Void,  // called on every step crossing
    pickerWidth: CGFloat = 220
)
```

### Where it's used

- `OB03AgeScreen.swift` — "How old are you?"
- `OB03BaselineScreen.swift` — "How tall are you?" (metric cm; imperial feet + inches as two side-by-side wheels) and "How much do you weigh?"

### When to use it

- A bounded whole-number selection where the value carries weight (age, height, weight, year, target, etc.).
- Onboarding-style screens where the picker is the single hero element.

### When NOT to use it

- Multi-value or paged selection — use a segmented control or list.
- Continuous values (decimals, durations down to seconds) — design a slider variant; the Focal Wheel is intentionally integer-only and step-based.
- Dense forms where many controls compete for attention — the 86 pt centre value is too loud; use a small SwiftUI `Picker` instead.

### Future variants (not yet built)

- **Two-column linked wheel** for unit-mixed values (feet + inches is currently two independent wheels; a linked variant could enforce range coupling). Add when needed.
- **Decimal step variant** (e.g. weight to 0.5 lb) — same visuals, different `step` semantics. Add when needed.

### Tweaking the Focal Spring

The named animation curve `spring(response: 0.45, dampingFraction: 0.92)` only runs at the drag-end settle. If you change it:

- Lower `response` (e.g. 0.3) snaps the residual offset away faster — risks looking abrupt at the end of a drag.
- Lower `dampingFraction` (e.g. 0.75) re-introduces overshoot — playful, but reintroduces the "jumpy" feel.
- Higher `response` (e.g. 0.6) makes the settle feel more languid.

If you adopt a different curve elsewhere in the app, name it (e.g. *Sheet Spring*, *Pill Spring*) and add it to this doc — don't proliferate anonymous magic numbers.

### Tuning history

- **2026-04-25 (v1, discrete-step model):** `response 0.38 / damping 0.72`, sizes 86/44/30, opacities 1.0/0.45/0.18, blur 0/1.5/3.5. Drag step-size = 50 pt; spring fired *every* integer crossing. **Felt jumpy** because the wheel snapped continuously during drag and the spring couldn't keep up.
- **2026-04-25 (v2, softened discrete-step):** `response 0.5 / damping 0.9`, sizes 84/52/36, opacities 1.0/0.55/0.28, blur 0/1.0/2.5. Same architecture, gentler curves. **Still jumpy** — the underlying discrete-step model couldn't be saved by tuning.
- **2026-04-25 (v3, continuous-tracking model):** Architecture rewritten. Drag is now strictly 1:1 with finger; visual properties are continuous functions of fractional distance from centre; spring runs *only* at drag-end. `rowHeight` reduced from 68 → 60 pt. Sizes 84 → 36 (linear), opacity quadratic ease-out, blur quadratic ease-in. This is the architecture that gives the native-picker feel.
- **2026-04-26 (current):** Split `rowHeight` into two tokens — `rowHeight = 60` for drag sensitivity (unchanged), `rowSpacing = 70` for visual row gap. Adds ~17% vertical breathing room between numbers without affecting how fast the wheel scrolls.

---
