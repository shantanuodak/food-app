//
//  AppColor.swift
//  Food App
//
//  Single source of truth for app colors. All tokens are adaptive
//  via UIColor dynamic providers — call sites get a `Color` that
//  resolves to the right value for the current `userInterfaceStyle`
//  with no `colorScheme == .dark ? ... : ...` ternaries.
//
//  Adding a token: keep it semantic (`surfaceWarm`, not `cream`).
//  Pick a fresh dark value or fall back to the iOS system equivalent
//  (`.label`, `.systemGroupedBackground`, etc.) where Apple has
//  already done the work.
//
//  Migrating call sites: prefer `Color.app.textPrimary` over
//  `Color.primary` for anything that previously had a hardcoded
//  RGB — it documents intent and keeps the migration grep-able.
//

import SwiftUI
import UIKit

extension Color {
    static let app = AppColor.self
}

enum AppColor {

    // MARK: - App shell background

    /// Top stop of `shellBackground`. Pure systemBackground in light
    /// (effectively no gradient — the gradient reads as a solid surface),
    /// slightly lifted near-black in dark to give the shell some depth
    /// without competing with content.
    static let shellBackgroundTop = dynamic(
        light: UIColor.systemBackground,
        dark:  UIColor(white: 0.08, alpha: 1.0)
    )

    /// Bottom stop of `shellBackground` — same as top in light, fades to
    /// pure black at the bottom in dark.
    static let shellBackgroundBottom = dynamic(
        light: UIColor.systemBackground,
        dark:  UIColor.black
    )

    /// Backdrop for the home shell + onboarding static-background screens.
    /// In dark mode this renders as a subtle top-to-bottom darkening so the
    /// shell doesn't feel like a flat OLED void. In light mode both stops
    /// resolve to `systemBackground`, so the gradient is a no-op.
    /// Apply via `.background(AppColor.shellBackground.ignoresSafeArea())`.
    static let shellBackground = LinearGradient(
        colors: [shellBackgroundTop, shellBackgroundBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Surfaces

    /// Outermost screen background — equivalent to a Form's grouped bg.
    static let background = Color(uiColor: .systemGroupedBackground)

    /// Card / row surface that sits on top of `background`.
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)

    /// Warm cream tile (bento dashboard, saved meals chrome). In dark mode
    /// we drop the warm tint and use neutral near-black — the warm-brown
    /// variant clashed with the orange brand accents (per 2026-05-24 walkthrough).
    static let surfaceWarm = dynamic(
        light: rgb(0.998, 0.985, 0.965),
        dark:  rgb(0.110, 0.110, 0.110)
    )

    /// Subtle chip / pill (saved-meal chips). Cream in light, one step
    /// lighter than `surfaceWarm` in dark so the chip lifts off the tile.
    static let surfaceChip = dynamic(
        light: rgb(1.0, 0.974, 0.946),
        dark:  rgb(0.157, 0.157, 0.157)
    )

    /// Soft warning surface (e.g. low-data prompts in bento).
    static let surfaceWarning = dynamic(
        light: rgb(1.0, 0.954, 0.915),
        dark:  rgb(0.196, 0.157, 0.094)
    )

    // MARK: - Borders / strokes

    /// Default 1pt border on cards/tiles. Warm tone in light, neutral
    /// white-on-dark in dark mode.
    static let borderSubtle = dynamic(
        light: UIColor(red: 0.278, green: 0.176, blue: 0.098, alpha: 0.10),
        dark:  UIColor(white: 1.0, alpha: 0.08)
    )

    /// Lighter hairline, used for inner dividers and row separators.
    static let borderHairline = dynamic(
        light: rgb(0.925, 0.855, 0.792),
        dark:  UIColor(white: 1.0, alpha: 0.06)
    )

    // MARK: - Text

    static let textPrimary   = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let textMuted     = Color(uiColor: .tertiaryLabel)

    /// Text that sits on top of brand-color buttons (always white).
    static let textInverse = Color.white

    // MARK: - Brand (orange family)

    /// Primary brand orange. Same hex in both modes for brand identity.
    static let brandOrange = rgbColor(1.00, 0.624, 0.200)

    /// Deep orange — used for selected states and CTA bottoms.
    static let brandOrangeDeep = rgbColor(0.902, 0.361, 0.102)

    /// Soft orange wash — used for tinted backgrounds behind orange content.
    /// Dark mode: a low-saturation orange tint rather than light cream.
    static let brandOrangeSoft = dynamic(
        light: rgb(1.0, 0.941, 0.878),
        dark:  rgb(0.235, 0.157, 0.071)
    )

    // MARK: - Macros (charts, nutrition pills)

    /// Protein blue. Slightly lifted in dark for legibility on dark surfaces.
    static let macroProtein = dynamic(
        light: rgb(0.227, 0.659, 0.969),
        dark:  rgb(0.388, 0.737, 0.988)
    )

    /// Carbs amber.
    static let macroCarbs = dynamic(
        light: rgb(0.961, 0.647, 0.141),
        dark:  rgb(0.988, 0.737, 0.298)
    )

    /// Fat purple/lilac. 2026-05-24: was red, which read as "warning"
    /// next to nutrition values. Switched to a vibrant purple — matches
    /// the Apple Health convention and stays clearly distinct from
    /// `macroProtein` (blue) and `macroCarbs` (amber).
    static let macroFat = dynamic(
        light: rgb(0.647, 0.396, 0.918),
        dark:  rgb(0.776, 0.620, 1.000)
    )

    // MARK: - Semantic

    static let success = dynamic(
        light: rgb(0.227, 0.812, 0.416),
        dark:  rgb(0.349, 0.847, 0.498)
    )

    static let warning = dynamic(
        light: rgb(0.961, 0.647, 0.141),
        dark:  rgb(0.988, 0.737, 0.298)
    )

    static let danger = Color(uiColor: .systemRed)

    // MARK: - Shadows / overlays

    /// Subtle drop shadow tint. Heavier in dark because shadows on dark
    /// surfaces need more opacity to register as depth.
    static let shadow = dynamic(
        light: UIColor.black.withAlphaComponent(0.055),
        dark:  UIColor.black.withAlphaComponent(0.30)
    )

    // MARK: - Gray scale (use sparingly — prefer semantic tokens above)

    /// 100–900 grays. Dark mode inverts the scale so `gray100` is still the
    /// "lightest" surface tone relative to the current background.
    static let gray100 = dynamic(light: rgb(0.945, 0.953, 0.961), dark: rgb(0.118, 0.122, 0.129))
    static let gray200 = dynamic(light: rgb(0.914, 0.925, 0.937), dark: rgb(0.157, 0.161, 0.169))
    static let gray400 = dynamic(light: rgb(0.678, 0.710, 0.741), dark: rgb(0.439, 0.451, 0.471))
    static let gray500 = Color(uiColor: .secondaryLabel)
    static let gray700 = dynamic(light: rgb(0.286, 0.314, 0.341), dark: rgb(0.804, 0.812, 0.831))
    static let gray900 = Color(uiColor: .label)

    // MARK: - Helpers

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }

    private static func rgbColor(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1.0) -> Color {
        Color(red: r, green: g, blue: b, opacity: a)
    }
}
