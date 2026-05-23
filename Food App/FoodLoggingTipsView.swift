import SwiftUI

struct FoodLoggingTipsView: View {
    enum PresentationStyle {
        case pushed
        case sheet(onClose: () -> Void)
    }

    let presentationStyle: PresentationStyle

    init(presentationStyle: PresentationStyle = .pushed) {
        self.presentationStyle = presentationStyle
    }

    var body: some View {
        Group {
            switch presentationStyle {
            case .pushed:
                content
                    .navigationTitle("Logging tips")
                    .navigationBarTitleDisplayMode(.inline)
            case .sheet(let onClose):
                VStack(spacing: 0) {
                    AppDrawerHeader(onClose: onClose) {
                        Text("Logging tips")
                            .font(OnboardingTypography.instrumentSerif(style: .regular, size: 31))
                            .foregroundStyle(FoodLoggingTipsTokens.brandGradient)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    content
                }
            }
        }
        .background(AppDrawerSurface.gradient.ignoresSafeArea())
        .presentationBackground(AppDrawerSurface.gradient)
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                hero
                FoodLoggingTipsMarqueeView(clues: FoodLoggingTipClue.defaultClues)
                featuredExample
                exampleList
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .background(FoodLoggingTipsTokens.screenBackground)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Give the app ")
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 42))
                + Text("one good clue.")
                    .font(OnboardingTypography.instrumentSerif(style: .italic, size: 42))
                    .foregroundStyle(FoodLoggingTipsTokens.orangeDeep)
            }
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(-4)
            .foregroundStyle(FoodLoggingTipsTokens.ink)

            Text("You do not need a perfect food diary. A portion, brand, count, or place is usually enough for a better estimate.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(FoodLoggingTipsTokens.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featuredExample: some View {
        HStack(alignment: .top, spacing: 8) {
            FoodLoggingTipsFeaturedCard(
                style: .needsClue,
                title: "Needs a clue",
                text: "cold coffee",
                note: "Add size and milk/sugar context."
            )

            FoodLoggingTipsBridge()
                .frame(width: 42, height: 146)

            FoodLoggingTipsFeaturedCard(
                style: .withClue,
                title: "With one clue",
                text: "8 oz cold coffee with milk",
                note: "Size + ingredient gives a better estimate."
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.white.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(FoodLoggingTipsTokens.border, lineWidth: 1)
                }
                .shadow(color: FoodLoggingTipsTokens.shadow, radius: 32, y: 18)
        )
    }

    private var exampleList: some View {
        VStack(spacing: 10) {
            ForEach(FoodLoggingTipExample.examples) { example in
                FoodLoggingTipExampleRow(example: example)
            }
        }
    }
}

private enum FoodLoggingTipsTokens {
    static let ink = Color(red: 0.141, green: 0.098, blue: 0.078)
    static let muted = Color(red: 0.467, green: 0.416, blue: 0.380)
    static let orange = Color(red: 0.941, green: 0.482, blue: 0.133)
    static let orangeDeep = Color(red: 0.725, green: 0.306, blue: 0.071)
    static let green = Color(red: 0.122, green: 0.561, blue: 0.384)
    static let red = Color(red: 0.812, green: 0.286, blue: 0.247)
    static let border = Color(red: 0.278, green: 0.176, blue: 0.098).opacity(0.11)
    static let shadow = Color(red: 0.376, green: 0.212, blue: 0.078).opacity(0.13)

    static let brandGradient = LinearGradient(
        colors: [Color(red: 1.00, green: 0.62, blue: 0.20), Color(red: 0.90, green: 0.36, blue: 0.10)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let screenBackground = LinearGradient(
        colors: [
            Color(red: 0.965, green: 0.886, blue: 0.792),
            Color(red: 1.000, green: 0.976, blue: 0.941),
            Color(red: 0.957, green: 0.918, blue: 0.875)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let needsClueBackground = LinearGradient(
        colors: [Color(red: 1.000, green: 0.941, blue: 0.925).opacity(0.86), .white.opacity(0.76)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let withClueBackground = LinearGradient(
        colors: [Color(red: 0.914, green: 0.973, blue: 0.933).opacity(0.88), .white.opacity(0.76)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct FoodLoggingTipClue: Identifiable {
    let id = UUID()
    let title: String

    static let defaultClues = [
        FoodLoggingTipClue(title: "Mention amount"),
        FoodLoggingTipClue(title: "Mention brand"),
        FoodLoggingTipClue(title: "Mention count"),
        FoodLoggingTipClue(title: "Mention restaurant"),
        FoodLoggingTipClue(title: "Mention main ingredients"),
        FoodLoggingTipClue(title: "Mention portion size"),
        FoodLoggingTipClue(title: "Mention sauce"),
        FoodLoggingTipClue(title: "Mention prep style")
    ]
}

private struct FoodLoggingTipsMarqueeView: View {
    let clues: [FoodLoggingTipClue]
    @State private var animate = false
    @State private var contentWidth: CGFloat = 1

    private var doubledClues: [FoodLoggingTipClue] { clues + clues }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 8) {
                ForEach(Array(doubledClues.enumerated()), id: \.offset) { _, clue in
                    Text(clue.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.384, green: 0.267, blue: 0.212))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.70), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(FoodLoggingTipsTokens.border, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.045), radius: 12, y: 5)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { contentProxy in
                    Color.clear
                        .preference(key: FoodLoggingTipsWidthPreferenceKey.self, value: contentProxy.size.width)
                }
            )
            .offset(x: animate ? -contentWidth / 2 : 0)
            .onPreferenceChange(FoodLoggingTipsWidthPreferenceKey.self) { width in
                guard width > 0 else { return }
                contentWidth = width
            }
            .onAppear {
                animate = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) {
                        animate = true
                    }
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .frame(height: 38)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Helpful clues: mention amount, brand, count, restaurant, ingredients, portion size, sauce, or prep style.")
    }
}

private struct FoodLoggingTipsWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FoodLoggingTipsFeaturedCard: View {
    enum Style {
        case needsClue
        case withClue
    }

    let style: Style
    let title: String
    let text: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black))
                .tracking(1.2)
                .foregroundStyle(FoodLoggingTipsTokens.ink.opacity(0.45))

            statusIcon

            Spacer(minLength: 6)

            Text(text)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(style == .withClue ? Color(red: 0.078, green: 0.165, blue: 0.114) : FoodLoggingTipsTokens.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.84)
                .fixedSize(horizontal: false, vertical: true)

            Text(note)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FoodLoggingTipsTokens.ink.opacity(0.62))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 146, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
    }

    private var statusIcon: some View {
        Image(systemName: style == .withClue ? "checkmark" : "xmark")
            .font(.system(size: 15, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(style == .withClue ? FoodLoggingTipsTokens.green : FoodLoggingTipsTokens.red, in: Circle())
            .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
    }

    private var background: LinearGradient {
        style == .withClue ? FoodLoggingTipsTokens.withClueBackground : FoodLoggingTipsTokens.needsClueBackground
    }

    private var borderColor: Color {
        style == .withClue ? FoodLoggingTipsTokens.green.opacity(0.18) : FoodLoggingTipsTokens.red.opacity(0.18)
    }
}

private struct FoodLoggingTipsBridge: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(FoodLoggingTipsTokens.orange.opacity(0.20))
                    .frame(width: pulse ? 38 : 22, height: pulse ? 38 : 22)
                    .opacity(pulse ? 0 : 0.8)

                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(FoodLoggingTipsTokens.brandGradient)
                    .frame(width: 27, height: 27)
                    .shadow(color: FoodLoggingTipsTokens.orange.opacity(0.32), radius: 10, y: 7)
                    .overlay {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.white)
                    }
                    .rotationEffect(.degrees(pulse ? 5 : -5))
            }

            Text("CLUE")
                .font(.system(size: 9, weight: .black))
                .tracking(1.1)
                .foregroundStyle(FoodLoggingTipsTokens.ink.opacity(0.50))
                .rotationEffect(.degrees(90))
                .frame(height: 36)
        }
        .frame(maxHeight: .infinity)
        .background(.white.opacity(0.52), in: Capsule())
        .overlay {
            Capsule()
                .stroke(FoodLoggingTipsTokens.border, lineWidth: 1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityHidden(true)
    }
}

private struct FoodLoggingTipExample: Identifiable {
    let id = UUID()
    let vague: String
    let clearer: String

    static let examples = [
        FoodLoggingTipExample(vague: "sandwich", clearer: "turkey sandwich, 2 slices wheat bread"),
        FoodLoggingTipExample(vague: "poha", clearer: "1 bowl poha with sev and onion"),
        FoodLoggingTipExample(vague: "pizza", clearer: "2 slices Margherita pizza"),
        FoodLoggingTipExample(vague: "protein bar", clearer: "Kirkland chocolate brownie protein bar, 1 bar"),
        FoodLoggingTipExample(vague: "dal rice", clearer: "1 cup dal + 1 cup cooked rice"),
        FoodLoggingTipExample(vague: "chips", clearer: "1 small bag Lay's chips"),
        FoodLoggingTipExample(vague: "omelette", clearer: "4 medium egg omelette with cheese"),
        FoodLoggingTipExample(vague: "coke", clearer: "Coke Zero, 12 oz can"),
        FoodLoggingTipExample(vague: "salad", clearer: "Chipotle salad bowl with chicken, no rice"),
        FoodLoggingTipExample(vague: "pasta", clearer: "1.5 cups pasta with tomato sauce")
    ]
}

private struct FoodLoggingTipExampleRow: View {
    let example: FoodLoggingTipExample

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            miniCard(
                title: "Needs clue",
                text: example.vague,
                systemImage: "xmark",
                tint: FoodLoggingTipsTokens.red,
                background: FoodLoggingTipsTokens.needsClueBackground
            )

            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 25, height: 25)
                .background(FoodLoggingTipsTokens.brandGradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .frame(width: 36)
                .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 17, style: .continuous))

            miniCard(
                title: "With clue",
                text: example.clearer,
                systemImage: "checkmark",
                tint: FoodLoggingTipsTokens.green,
                background: FoodLoggingTipsTokens.withClueBackground
            )
        }
        .padding(8)
        .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(FoodLoggingTipsTokens.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.045), radius: 16, y: 8)
    }

    private func miniCard(
        title: String,
        text: String,
        systemImage: String,
        tint: Color,
        background: LinearGradient
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(tint, in: Circle())

                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(FoodLoggingTipsTokens.ink.opacity(0.44))
                    .lineLimit(1)
            }

            Text(text)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(FoodLoggingTipsTokens.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview("Logging tips") {
    NavigationStack {
        FoodLoggingTipsView()
    }
}

// MARK: - Compact prompt sheet (Item 4, 2026-05-22)
//
// Surfaces a short popup after a vague entry to ask whether the user wants
// to see Logging Tips. Replaces the inline-row treatment the user found
// awkward. Two actions: "Show me tips" opens the full FoodLoggingTipsView,
// "Skip for now" dismisses and honors a 24-hour cooldown stored in
// UserDefaults under `loggingTipsPromptSkippedUntilKey`.

struct LoggingTipsPromptSheet: View {
    let onShowTips: () -> Void
    let onSkip: () -> Void

    static let skipCooldownKey = "loggingTipsPromptSkippedUntil.v1"

    // 2026-05-23: cooldown removed — popup now fires on every vague entry.
    // Helpers kept as no-ops so the call sites that still invoke them
    // (MainLoggingShellBody) don't have to change.
    static func skipForCooldown(defaults: UserDefaults = .standard) {
        // Intentional no-op. Skip just dismisses for this entry.
    }

    static func isWithinSkipCooldown(defaults: UserDefaults = .standard) -> Bool {
        false
    }

    @State private var example: LoggingTipsPromptExample = LoggingTipsPromptExample.random()
    @State private var arrowPulse: Bool = false
    @State private var hasAppeared: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 22)

            exampleCard
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Spacer(minLength: 14)

            actionStack
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .background(FoodLoggingTipsPromptTokens.surface.ignoresSafeArea())
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            example = LoggingTipsPromptExample.random()
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                arrowPulse = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clue tip")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(FoodLoggingTipsPromptTokens.orangeDeep)
                .textCase(.uppercase)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.72), in: Capsule())
                .overlay(
                    Capsule().stroke(FoodLoggingTipsPromptTokens.border, lineWidth: 1)
                )

            (
                Text("Give the app ")
                    .font(.custom("InstrumentSerif-Regular", size: 30))
                + Text("one good clue.")
                    .font(.custom("InstrumentSerif-Italic", size: 30))
                    .foregroundStyle(FoodLoggingTipsPromptTokens.orangeDeep)
            )
            .foregroundStyle(FoodLoggingTipsPromptTokens.ink)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exampleCard: some View {
        HStack(alignment: .center, spacing: 0) {
            exampleSide(
                tagText: "Needs clue",
                tagInk: FoodLoggingTipsPromptTokens.redInk,
                glyph: "xmark",
                text: example.vague,
                surface: FoodLoggingTipsPromptTokens.needsClueSurface,
                surfaceBorder: FoodLoggingTipsPromptTokens.redInk.opacity(0.18)
            )

            arrowBridge
                .frame(width: 36)

            exampleSide(
                tagText: "With clue",
                tagInk: FoodLoggingTipsPromptTokens.greenInk,
                glyph: "checkmark",
                text: example.withClue,
                surface: FoodLoggingTipsPromptTokens.withClueSurface,
                surfaceBorder: FoodLoggingTipsPromptTokens.greenInk.opacity(0.18)
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(FoodLoggingTipsPromptTokens.border, lineWidth: 1)
                )
                .shadow(color: FoodLoggingTipsPromptTokens.shadow, radius: 20, y: 10)
        )
    }

    @ViewBuilder
    private func exampleSide(
        tagText: String,
        tagInk: Color,
        glyph: String,
        text: String,
        surface: LinearGradient,
        surfaceBorder: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: glyph)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(tagInk, in: Circle())
                Text(tagText.uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(tagInk.opacity(0.82))
                    .lineLimit(1)
            }

            Text(text)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(FoodLoggingTipsPromptTokens.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(surfaceBorder, lineWidth: 1)
        )
    }

    private var arrowBridge: some View {
        ZStack {
            Circle()
                .fill(FoodLoggingTipsPromptTokens.orangeDeep.opacity(arrowPulse ? 0.0 : 0.18))
                .frame(width: arrowPulse ? 34 : 22, height: arrowPulse ? 34 : 22)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FoodLoggingTipsPromptTokens.brandGradient)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                )
                .shadow(color: FoodLoggingTipsPromptTokens.orangeDeep.opacity(0.32), radius: 8, y: 5)
        }
        .accessibilityHidden(true)
    }

    private var actionStack: some View {
        VStack(spacing: 10) {
            Button(action: onShowTips) {
                HStack(spacing: 6) {
                    Text("See more clues")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .black))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(FoodLoggingTipsPromptTokens.brandGradient)
                )
                .shadow(color: FoodLoggingTipsPromptTokens.orangeDeep.opacity(0.28), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("See more logging clues"))

            Button(action: onSkip) {
                Text("Got it")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(FoodLoggingTipsPromptTokens.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss the clue tip"))
        }
    }
}

struct LoggingTipsPromptExample {
    let vague: String
    let withClue: String

    static func random() -> LoggingTipsPromptExample {
        all.randomElement() ?? all[0]
    }

    static let all: [LoggingTipsPromptExample] = [
        LoggingTipsPromptExample(vague: "sandwich", withClue: "turkey sandwich, 2 slices wheat"),
        LoggingTipsPromptExample(vague: "coffee", withClue: "8 oz cold coffee with milk"),
        LoggingTipsPromptExample(vague: "salad", withClue: "Chipotle salad bowl, chicken, no rice"),
        LoggingTipsPromptExample(vague: "pizza", withClue: "2 slices Margherita pizza"),
        LoggingTipsPromptExample(vague: "protein bar", withClue: "1 Kirkland chocolate brownie bar"),
        LoggingTipsPromptExample(vague: "dal rice", withClue: "1 cup dal + 1 cup rice"),
        LoggingTipsPromptExample(vague: "chips", withClue: "1 small bag Lay's classic chips"),
        LoggingTipsPromptExample(vague: "omelette", withClue: "4-egg omelette with cheese"),
        LoggingTipsPromptExample(vague: "coke", withClue: "Coke Zero, 12 oz can"),
        LoggingTipsPromptExample(vague: "pasta", withClue: "1.5 cups pasta, tomato sauce")
    ]
}

private enum FoodLoggingTipsPromptTokens {
    static let ink = Color(red: 0.141, green: 0.098, blue: 0.078)
    static let muted = Color(red: 0.467, green: 0.416, blue: 0.380)
    static let orangeDeep = Color(red: 0.725, green: 0.306, blue: 0.071)
    static let redInk = Color(red: 0.812, green: 0.286, blue: 0.247)
    static let greenInk = Color(red: 0.122, green: 0.561, blue: 0.384)
    static let border = Color(red: 0.278, green: 0.176, blue: 0.098).opacity(0.11)
    static let shadow = Color(red: 0.376, green: 0.212, blue: 0.078).opacity(0.14)

    static let brandGradient = LinearGradient(
        colors: [Color(red: 1.00, green: 0.62, blue: 0.20), Color(red: 0.90, green: 0.36, blue: 0.10)],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let surface = LinearGradient(
        colors: [
            Color(red: 0.984, green: 0.917, blue: 0.835),
            Color(red: 1.000, green: 0.976, blue: 0.941)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let needsClueSurface = LinearGradient(
        colors: [Color(red: 1.000, green: 0.941, blue: 0.925).opacity(0.92), .white.opacity(0.80)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let withClueSurface = LinearGradient(
        colors: [Color(red: 0.914, green: 0.973, blue: 0.933).opacity(0.94), .white.opacity(0.80)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
