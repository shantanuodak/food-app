import SwiftUI
import UIKit

struct BadgesTrophyCaseView: View {
    let currentStreakDays: Int
    private let autoLoadsRemoteProgress: Bool

    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var summary: BadgesSummaryResponse?
    @State private var isLoading: Bool
    @State private var errorMessage: String?
    @State private var isShareSheetPresented = false
    @State private var shareItems: [Any] = []
    @State private var replayedBadge: BadgeDefinition?
    @State private var refreshedStreakDays: Int?

    init(currentStreakDays: Int, autoLoadsRemoteProgress: Bool = true) {
        self.currentStreakDays = currentStreakDays
        self.autoLoadsRemoteProgress = autoLoadsRemoteProgress
        _isLoading = State(initialValue: autoLoadsRemoteProgress)
    }

    private var totals: BadgesTotals {
        summary?.totals ?? BadgesTotals(
            logs: 0,
            foodItems: 0,
            uniqueFoods: 0,
            textLogs: 0,
            voiceLogs: 0,
            imageLogs: 0,
            manualLogs: 0,
            manualOverrideItems: 0,
            highConfidenceLogs: 0,
            highConfidenceItems: 0,
            healthActiveDays: 0,
            healthStepDays10k: 0
        )
    }

    private var groupedBadges: [(BadgeDefinition.Category, [BadgeState])] {
        BadgeCatalog.statesByCategory(totals: totals, currentStreakDays: effectiveCurrentStreakDays)
    }

    private var earnedCount: Int {
        BadgeCatalog.earnedCount(totals: totals, currentStreakDays: effectiveCurrentStreakDays)
    }

    private var effectiveCurrentStreakDays: Int {
        refreshedStreakDays ?? currentStreakDays
    }

    private var heroData: BadgeHeroData {
        let streakDays = effectiveCurrentStreakDays
        let next = StreakBadges.nextBadge(for: streakDays)
        let current = StreakBadges.currentBadge(for: streakDays)
        let featured = next ?? current
        let target = featured?.requiredDays ?? 1
        let title = featured?.title ?? "First Spark"
        let subtitle: String
        if next != nil {
            subtitle = "Earn \(min(streakDays, target))/\(target)"
        } else {
            subtitle = "Every streak badge unlocked"
        }

        let featuredIsEarned: Bool
        if let featured {
            featuredIsEarned = streakDays >= featured.requiredDays
        } else {
            featuredIsEarned = false
        }

        return BadgeHeroData(
            title: title,
            subtitle: subtitle,
            systemImage: featured?.systemImage ?? "sparkle",
            currentValue: min(streakDays, target),
            targetValue: target,
            earnedCount: earnedCount,
            totalCount: BadgeCatalog.totalCount,
            streakDays: streakDays,
            badge: featured,
            isEarned: featuredIsEarned
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            AppDrawerHeader(onClose: { dismiss() }) {
                Text("Your badges")
                    .font(.custom("InstrumentSerif-Regular", size: 31))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.988, green: 0.545, blue: 0.196),
                                Color(red: 0.902, green: 0.361, blue: 0.102)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    if let errorMessage {
                        errorBanner(errorMessage)
                    }
                    ForEach(groupedBadges, id: \.0.id) { category, badges in
                        badgeSection(category: category, badges: badges)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .background(AppDrawerSurface.gradient.ignoresSafeArea())
        .presentationBackground(AppDrawerSurface.gradient)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard autoLoadsRemoteProgress else { return }
            await loadBadges()
        }
        .refreshable {
            await loadBadges()
        }
        .sheet(isPresented: $isShareSheetPresented) {
            BadgeActivityView(activityItems: shareItems)
        }
        .fullScreenCover(item: $replayedBadge) { badge in
            BadgeCelebrationPopup(badge: badge) {
                replayedBadge = nil
            }
            .presentationBackground(.clear)
        }
    }

    private var heroCard: some View {
        BadgeHeroCard(data: heroData, showsShareButton: true) {
            shareHeroCard()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BadgeTokens.amber)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BadgeTokens.ink)
            Spacer()
            Button("Retry") {
                Task { await loadBadges() }
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(BadgeTokens.orange)
        }
        .padding(12)
        .background(AppColor.surfaceChip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func badgeSection(category: BadgeDefinition.Category, badges: [BadgeState]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category.rawValue.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(BadgeTokens.muted)
                .padding(.horizontal, 2)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(badges) { badge in
                    BadgeCard(
                        state: badge,
                        isLoading: isLoading,
                        onReplay: badge.isEarned ? { replayedBadge = badge.definition } : nil
                    )
                }
            }
        }
    }

    @MainActor
    private func loadBadges() async {
        isLoading = true
        errorMessage = nil
        let timezone = TimeZone.current.identifier
        async let summaryTask = appStore.apiClient.getBadgesSummary(timezone: timezone)
        async let streakTask = appStore.apiClient.getStreaks(range: 365, timezone: timezone)
        var summaryFailed = false
        var streakFailed = false

        do {
            summary = try await summaryTask
        } catch is CancellationError {
            summaryFailed = true
        } catch {
            summaryFailed = true
        }

        do {
            let streak = try await streakTask
            refreshedStreakDays = streak.currentDays
        } catch is CancellationError {
            streakFailed = true
        } catch {
            streakFailed = true
        }

        // Only surface the banner when there is genuinely nothing to show.
        // Partial failures (e.g., streak fetch flaked while summary loaded)
        // were previously firing the banner on every refresh, which made
        // the rewards screen feel broken even when the badges still
        // rendered. Stay quiet if any cached data is available.
        if summaryFailed && streakFailed && summary == nil {
            errorMessage = "Couldn't load badge progress. Check your connection."
        }
        isLoading = false
    }

    @MainActor
    private func shareHeroCard() {
        let shareCard = BadgeHeroCard(data: heroData, showsShareButton: false)
            .frame(width: 360)
            .padding(18)
            .background(BadgeTokens.canvas)
        let renderer = ImageRenderer(content: shareCard)
        renderer.scale = UIScreen.main.scale

        if let image = renderer.uiImage {
            shareItems = [image, heroData.shareText]
        } else {
            shareItems = [heroData.shareText]
        }
        isShareSheetPresented = true
    }
}

private struct BadgeHeroData {
    let title: String
    let subtitle: String
    let systemImage: String
    let currentValue: Int
    let targetValue: Int
    let earnedCount: Int
    let totalCount: Int
    let streakDays: Int
    /// The StreakBadge instance the medallion should render. When nil the
    /// hero falls back to the system-image rendering (used for the share
    /// snapshot, where we want a flat single-color glyph).
    let badge: StreakBadge?
    /// Whether the user has already earned `badge`. Drives the medallion's
    /// earned-vs-locked styling.
    let isEarned: Bool

    var shareText: String {
        "I am working on \(title): \(subtitle) in Food App."
    }
}

private struct BadgeHeroCard: View {
    let data: BadgeHeroData
    let showsShareButton: Bool
    let onShare: (() -> Void)?

    init(data: BadgeHeroData, showsShareButton: Bool, onShare: (() -> Void)? = nil) {
        self.data = data
        self.showsShareButton = showsShareButton
        self.onShare = onShare
    }

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            // Share button sits in a top-trailing slot so the medallion can
            // be the visual centerpiece of the card. Earlier layout pushed
            // the medallion to the left of the title — that made the icon
            // feel like an afterthought next to the serif headline.
            if showsShareButton {
                HStack {
                    Spacer()
                    Button {
                        onShare?()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(BadgeTokens.orange)
                            .frame(width: 36, height: 36)
                            .background(AppColor.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share badge")
                }
                .frame(maxWidth: .infinity)
            }

            // 2026-05-23: the previous medallion was a plain orange
            // gradient circle with a white SF Symbol on top. On the
            // Century Club tier the `100.circle.fill` glyph rendered as a
            // near-invisible white blob (filled circle + filled text both
            // white). Swapped to the richer StreakBadgeMedallion that's
            // already used elsewhere — it handles tier colors, gloss, and
            // the locked-vs-earned state explicitly. Also centered for
            // visual gravity.
            Group {
                if let badge = data.badge {
                    StreakBadgeMedallion(badge: badge, isEarned: data.isEarned, size: 88)
                } else {
                    ZStack {
                        Circle()
                            .fill(BadgeTokens.goldGradient)
                        Image(systemName: data.systemImage)
                            .font(.system(size: 36, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 96, height: 96)
                    .shadow(color: BadgeTokens.amber.opacity(0.25), radius: 18, y: 8)
                }
            }
            .accessibilityHidden(true)
            .padding(.top, showsShareButton ? -8 : 4)

            VStack(spacing: 6) {
                Text(data.title)
                    .font(.custom("InstrumentSerif-Regular", size: 34))
                    .foregroundStyle(BadgeTokens.ink)
                    .multilineTextAlignment(.center)
                Text(data.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BadgeTokens.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                heroStat(value: "\(data.earnedCount)", label: "earned")
                heroStat(value: "\(data.totalCount)", label: "total")
                heroStat(value: "\(data.streakDays)", label: "day streak")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppColor.surfaceChip)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .shadow(color: AppColor.shadow, radius: 18, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Badges. \(data.earnedCount) of \(data.totalCount) badges earned. \(data.title). \(data.subtitle).")
    }

    private func heroStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(BadgeTokens.ink)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(BadgeTokens.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct BadgeActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct BadgeCard: View {
    let state: BadgeState
    let isLoading: Bool
    let onReplay: (() -> Void)?

    private var definition: BadgeDefinition { state.definition }

    init(state: BadgeState, isLoading: Bool, onReplay: (() -> Void)? = nil) {
        self.state = state
        self.isLoading = isLoading
        self.onReplay = onReplay
    }

    @ViewBuilder
    var body: some View {
        if let onReplay, state.isEarned {
            Button(action: onReplay) {
                cardContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Replays the badge celebration.")
        } else {
            cardContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(iconFill)
                    Image(systemName: state.isEarned ? definition.systemImage : "lock.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(state.isEarned ? .white : BadgeTokens.muted)
                }
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

                Spacer()

                Text(state.isEarned ? "Earned" : "\(state.remaining) left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(state.isEarned ? BadgeTokens.orange : BadgeTokens.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(statusFill, in: Capsule())
            }

            Text(definition.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(state.isEarned ? BadgeTokens.ink : BadgeTokens.muted)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(definition.subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BadgeTokens.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: isLoading ? 0 : state.progress)
                .tint(state.isEarned ? BadgeTokens.amber : BadgeTokens.muted.opacity(0.45))
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(state.isEarned ? 0.045 : 0.04), radius: 13, y: 7)
        .shadow(color: BadgeTokens.amber.opacity(state.isEarned ? 0.035 : 0.025), radius: 18, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var iconFill: LinearGradient {
        if state.isEarned {
            switch definition.rarity {
            case .bronze:
                return BadgeTokens.bronzeGradient
            case .silver:
                return BadgeTokens.silverGradient
            case .gold:
                return BadgeTokens.goldGradient
            case .platinum:
                return BadgeTokens.platinumGradient
            }
        }
        return LinearGradient(colors: [BadgeTokens.gray200, BadgeTokens.gray100], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var cardFill: AnyShapeStyle {
        // 2026-05-24: earned and locked both render on AppColor.surfaceChip
        // so the grid stays consistent with the hero card in dark mode.
        // Light-mode gradient look is gone — kept the design hierarchy via
        // stroke + statusFill instead.
        AnyShapeStyle(AppColor.surfaceChip)
    }

    private var cardStroke: AnyShapeStyle {
        if state.isEarned {
            return AnyShapeStyle(BadgeTokens.amber.opacity(0.28))
        }
        return AnyShapeStyle(AppColor.borderSubtle)
    }

    private var statusFill: Color {
        state.isEarned ? BadgeTokens.amber.opacity(0.13) : BadgeTokens.gray200.opacity(0.7)
    }

    private var accessibilityLabel: String {
        if state.isEarned {
            return "\(definition.title), earned badge. \(definition.subtitle). Double tap to replay the celebration."
        }
        return "\(definition.title), locked badge. \(state.remaining) more needed. \(definition.subtitle)"
    }
}

private struct BadgeCelebrationPopup: View {
    let badge: BadgeDefinition
    let onDismiss: () -> Void

    private static let medallionSize: CGFloat = 156

    @State private var hasAppeared = false
    @State private var medalScale: CGFloat = 0.62
    @State private var medalRotation: Double = -14
    @State private var raysOpacity: Double = 0
    @State private var titleOffset: CGFloat = 24
    @State private var titleOpacity: Double = 0
    @State private var dismissTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 26) {
                Spacer(minLength: 0)

                Text("BADGE EARNED")
                    .font(.system(size: 13, weight: .black))
                    .tracking(3.0)
                    .foregroundStyle(.white.opacity(0.78))
                    .opacity(titleOpacity)
                    .offset(y: titleOffset * 0.5)

                medalStack

                VStack(spacing: 8) {
                    Text(badge.title)
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(badge.subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(titleOpacity)
                .offset(y: titleOffset)

                Text(requirementCopy.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .opacity(titleOpacity)

                Spacer(minLength: 0)

                Button(action: dismissNow) {
                    Text("Let's go")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.141, green: 0.098, blue: 0.078))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white)
                        )
                        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Let's go"))
                .accessibilityHint(Text("Dismiss this celebration"))
                .opacity(titleOpacity)
                .padding(.horizontal, 32)
                .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { dismissNow() }
        .onAppear { runEntranceAnimation() }
        .onDisappear { dismissTask?.cancel() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Badge earned: \(badge.title). \(badge.subtitle)"))
        .accessibilityAddTraits(.isModal)
    }

    private var backdrop: some View {
        ZStack {
            RadialGradient(
                colors: [
                    tierGlowColor.opacity(0.12),
                    Color.black.opacity(0.94),
                    Color.black
                ],
                center: .center,
                startRadius: 42,
                endRadius: 500
            )

            tierGlowColor.opacity(0.06)
        }
    }

    private var medalStack: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tierGlowColor.opacity(0.12), .clear],
                        center: .center,
                        startRadius: Self.medallionSize * 0.16,
                        endRadius: Self.medallionSize * 0.52
                    )
                )
                .frame(width: Self.medallionSize, height: Self.medallionSize)
                .clipShape(Circle())
                .opacity(raysOpacity * 0.55)

            if !reduceMotion {
                BadgeConfettiBurst(seed: badge.id)
                    .frame(width: 320, height: 320)
                    .opacity(raysOpacity)
            }

            BadgeCelebrationMedallion(badge: badge, size: Self.medallionSize)
                .scaleEffect(medalScale)
                .rotationEffect(.degrees(medalRotation))
                .shadow(color: tierGlowColor.opacity(0.16), radius: 18, y: 6)
        }
        .frame(width: 320, height: 320)
    }

    private func runEntranceAnimation() {
        guard !hasAppeared else { return }
        hasAppeared = true

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)

        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.55, dampingFraction: 0.55, blendDuration: 0)) {
            medalScale = 1.0
            medalRotation = 0
        }

        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .easeOut(duration: 0.6).delay(0.05)) {
            raysOpacity = 1.0
        }

        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .easeOut(duration: 0.45).delay(0.18)) {
            titleOpacity = 1.0
            titleOffset = 0
        }

        // No auto-dismiss — user dismisses via the Let's go button or
        // tap-anywhere fallback. Matches the celebration popup in
        // StreakAchievementPopup.swift.
    }

    private func dismissNow() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.22)) {
            titleOpacity = 0
            raysOpacity = 0
            medalScale = 0.85
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onDismiss()
        }
    }

    private var requirementCopy: String {
        switch badge.category {
        case .streaks:
            return "\(badge.requiredValue) day\(badge.requiredValue == 1 ? "" : "s") of consistency"
        case .logging:
            return "\(badge.requiredValue) logged meal\(badge.requiredValue == 1 ? "" : "s")"
        case .input:
            return "Unlocked by using \(badge.title.lowercased())"
        case .variety:
            return "\(badge.requiredValue) unique food\(badge.requiredValue == 1 ? "" : "s")"
        case .accuracy:
            return "\(badge.requiredValue) trusted nutrition moment\(badge.requiredValue == 1 ? "" : "s")"
        case .hydration:
            return "\(badge.requiredValue) water milestone\(badge.requiredValue == 1 ? "" : "s")"
        case .health:
            return "\(badge.requiredValue) synced Health day\(badge.requiredValue == 1 ? "" : "s")"
        }
    }

    private var tierGlowColor: Color {
        switch badge.rarity {
        case .bronze:
            return Color(red: 0.96, green: 0.50, blue: 0.18)
        case .silver:
            return Color(red: 0.74, green: 0.79, blue: 0.86)
        case .gold:
            return Color(red: 1.0, green: 0.74, blue: 0.20)
        case .platinum:
            return Color(red: 0.62, green: 0.66, blue: 0.74)
        }
    }
}

private struct BadgeCelebrationMedallion: View {
    let badge: BadgeDefinition
    let size: CGFloat

    var body: some View {
        badgeFace
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                .white.opacity(0.72),
                                tierColor.opacity(0.26),
                                Color.black.opacity(0.18),
                                .white.opacity(0.44),
                                .white.opacity(0.72)
                            ],
                            center: .center
                        ),
                        lineWidth: size * 0.025
                    )
            )
            .compositingGroup()
            .accessibilityHidden(true)
    }

    private var badgeFace: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.92),
                            tierColor.opacity(0.18),
                            Color.black.opacity(0.08),
                            tierColor.opacity(0.26),
                            .white.opacity(0.92)
                        ],
                        center: .center
                    )
                )

            Circle()
                .inset(by: size * 0.065)
                .fill(medallionFill)
                .overlay(
                    Circle()
                        .inset(by: size * 0.055)
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(0.40),
                                    .white.opacity(0.08),
                                    Color.black.opacity(0.18)
                                ],
                                center: UnitPoint(x: 0.34, y: 0.24),
                                startRadius: size * 0.04,
                                endRadius: size * 0.62
                            )
                        )
                        .blendMode(.softLight)
                )
                .overlay(
                    Circle()
                        .inset(by: size * 0.09)
                        .stroke(.white.opacity(0.30), lineWidth: 1)
                )

            Circle()
                .inset(by: size * 0.18)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.20), .clear],
                        startPoint: .bottomTrailing,
                        endPoint: .topLeading
                    )
                )
                .blendMode(.multiply)

            Circle()
                .inset(by: size * 0.11)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.48), .white.opacity(0.10), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .blendMode(.screen)

            Image(systemName: badge.systemImage)
                .font(.system(size: size * 0.36, weight: .black))
                .foregroundStyle(tierColor)
                .padding(size * 0.13)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .overlay(
                            Circle()
                                .stroke(tierColor.opacity(0.16), lineWidth: 1)
                        )
                )
                .shadow(color: .white.opacity(0.18), radius: 1, x: -1, y: -1)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        }
        .frame(width: size, height: size)
    }

    private var medallionFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.96),
                tierColor.opacity(0.16),
                Color.white.opacity(0.78)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var tierColor: Color {
        switch badge.rarity {
        case .bronze:
            return Color(red: 0.92, green: 0.45, blue: 0.18)
        case .silver:
            return Color(red: 0.76, green: 0.81, blue: 0.88)
        case .gold:
            return BadgeTokens.amber
        case .platinum:
            return Color(red: 0.64, green: 0.67, blue: 0.74)
        }
    }
}

private struct BadgeConfettiBurst: View {
    let seed: String

    private static let particleCount = 30
    private static let palette: [Color] = [
        Color(red: 1.0, green: 0.82, blue: 0.32),
        Color(red: 1.0, green: 0.54, blue: 0.18),
        Color(red: 0.96, green: 0.36, blue: 0.50),
        Color(red: 0.42, green: 0.74, blue: 0.96),
        Color(red: 0.62, green: 0.86, blue: 0.46)
    ]

    var body: some View {
        let particles = makeParticles()

        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 4)
            ZStack {
                ForEach(particles) { particle in
                    let progress = min(1.0, elapsed / particle.duration)
                    let distance = particle.travel * progress
                    let opacity = max(0, 1 - progress * 1.4)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(particle.color)
                        .frame(width: particle.width, height: particle.height)
                        .rotationEffect(.radians(particle.angle + progress * .pi))
                        .offset(
                            x: cos(particle.angle) * distance,
                            y: sin(particle.angle) * distance
                        )
                        .opacity(opacity)
                        .scaleEffect(0.6 + progress * 0.6)
                }
            }
        }
    }

    private struct Particle: Identifiable {
        let id = UUID()
        let angle: Double
        let travel: Double
        let duration: Double
        let width: CGFloat
        let height: CGFloat
        let color: Color
    }

    private func makeParticles() -> [Particle] {
        var rng = BadgeCelebrationSeededRandomGenerator(seed: UInt64(abs(seed.hashValue)))
        return (0..<Self.particleCount).map { _ in
            Particle(
                angle: Double.random(in: 0...(2 * .pi), using: &rng),
                travel: Double.random(in: 86...168, using: &rng),
                duration: Double.random(in: 1.5...2.7, using: &rng),
                width: CGFloat.random(in: 4...8, using: &rng),
                height: CGFloat.random(in: 7...14, using: &rng),
                color: Self.palette.randomElement(using: &rng) ?? .orange
            )
        }
    }
}

private struct BadgeCelebrationSeededRandomGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEADBEEF : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

private enum BadgeTokens {
    // 2026-05-24: forwarded to AppColor so the trophy case adapts to
    // dark mode like the rest of the app. Tier gradients below stay
    // hardcoded — they're brand-medal colors and should look the same
    // in both modes.
    static let canvas = AppColor.background
    static let ink = AppColor.textPrimary
    static let muted = AppColor.textSecondary
    static let gray100 = AppColor.gray100
    static let gray200 = AppColor.gray200
    static let amber = AppColor.warning
    static let orange = AppColor.brandOrangeDeep

    static let bronzeGradient = LinearGradient(colors: [Color(red: 0.86, green: 0.50, blue: 0.27), Color(red: 0.62, green: 0.32, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let silverGradient = LinearGradient(colors: [Color(red: 0.82, green: 0.87, blue: 0.91), Color(red: 0.48, green: 0.55, blue: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let goldGradient = LinearGradient(colors: [Color(red: 1.00, green: 0.76, blue: 0.22), Color(red: 0.91, green: 0.39, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let platinumGradient = LinearGradient(colors: [Color(red: 0.15, green: 0.16, blue: 0.19), Color(red: 0.56, green: 0.58, blue: 0.64)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

#Preview {
    NavigationStack {
        BadgesTrophyCaseView(currentStreakDays: 9)
            .environmentObject(AppStore())
    }
}
