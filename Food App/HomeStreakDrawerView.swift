import SwiftUI

struct HomeStreakDrawerView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var response: StreakResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// Newly-earned badge to celebrate via the full-screen popup. When non-nil,
    /// the popup is presented and the user taps (or waits) to dismiss.
    @State private var triggeredAchievement: StreakBadge?
    @State private var lastLoadedStreakDays: Int?

    var body: some View {
        VStack(spacing: 0) {
            drawerHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !appStore.configuration.progressFeatureEnabled {
                        disabledCard
                    } else if isLoading && response == nil {
                        loadingCard
                    } else if let response {
                        badgeHero(for: response)
                        upcomingBadgesCarousel(for: response.currentDays)
                        exploreAllBadgesLink
                    } else if let errorMessage {
                        errorCard(errorMessage)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 28)
                .animation(.easeInOut(duration: 0.28), value: response?.range)
            }
        }
        .background(AppDrawerSurface.gradient)
        .presentationBackground(AppDrawerSurface.gradient)
        .task {
            applyCachedStreaksIfAvailable()
            await loadStreaks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionProgressDidChange)) { _ in
            applyCachedStreaksIfAvailable()
            Task { await loadStreaks() }
        }
        .refreshable {
            await loadStreaks()
        }
        .fullScreenCover(item: $triggeredAchievement) { badge in
            StreakAchievementPopup(badge: badge) {
                triggeredAchievement = nil
            }
            .presentationBackground(.clear)
        }
    }

    private var drawerHeader: some View {
        AppDrawerHeader(onClose: { dismiss() }) {
            drawerTitle
        }
    }

    private var drawerTitle: some View {
        VStack(alignment: .center, spacing: 0) {
            Text("Badge progress")
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
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func badgeHero(for response: StreakResponse) -> some View {
        let currentDays = response.currentDays
        let currentBadge = StreakBadges.currentBadge(for: currentDays)
        let nextBadge = StreakBadges.nextBadge(for: currentDays)
        let featuredBadge = currentBadge ?? nextBadge

        return VStack(alignment: .center, spacing: 16) {
            RevolvingStreakBadgeMedallion(
                badge: featuredBadge,
                isEarned: currentBadge != nil,
                size: 152
            )
            .padding(.top, 4)
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(featuredBadge?.title ?? "Start your first streak badge today")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(heroTagline(currentBadge: currentBadge, nextBadge: nextBadge))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)

            Text("\(currentDays) day\(currentDays == 1 ? "" : "s") streak")
                .font(.system(size: 18, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(streakGoldGradient)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.62), lineWidth: 1)
                }

            Text("Longest \(response.longestDays) \(response.longestDays == 1 ? "day" : "days") • \(statusCopy(for: response))")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary.opacity(0.64))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(heroBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibilityLabel(for: response, badge: currentBadge))
    }

    /// Horizontal paging carousel of the next 3 unearned streak badges. Each card
    /// shows the medallion, badge title, days-remaining count, an estimated
    /// earn-by date (today + daysRemaining since streaks are 1:1 with days),
    /// and a mini progress bar.
    ///
    /// Falls back to a single "all unlocked" card when the user has earned
    /// every defined badge.
    private func upcomingBadgesCarousel(for currentDays: Int) -> some View {
        let upcoming = StreakBadges.badges
            .filter { currentDays < $0.requiredDays }
            .prefix(3)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upcoming streak badges")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if upcoming.count > 1 {
                    Text("Swipe →")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            if upcoming.isEmpty {
                allBadgesUnlockedCard
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(upcoming)) { badge in
                            upcomingBadgeCard(badge: badge, currentDays: currentDays)
                                .containerRelativeFrame(.horizontal)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollClipDisabled(false)
            }
        }
    }

    private func upcomingBadgeCard(badge: StreakBadge, currentDays: Int) -> some View {
        let daysRemaining = max(0, badge.requiredDays - currentDays)
        let fraction = badge.requiredDays > 0
            ? min(1.0, max(0.0, Double(currentDays) / Double(badge.requiredDays)))
            : 0
        let earnByDate = Calendar.current.date(byAdding: .day, value: daysRemaining, to: Date())

        return HStack(alignment: .top, spacing: 14) {
            StreakBadgeMedallion(badge: badge, isEarned: false, size: 64)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(badge.title)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(daysRemaining)")
                        .font(.system(size: 22, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(streakGoldGradient)

                    Text(daysRemaining == 1 ? "day to go" : "days to go")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                if let earnByDate {
                    Text("Earn by \(earnByDate.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.85))
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(streakGoldGradient)
                            .frame(width: fraction <= 0 ? 0 : max(6, proxy.size.width * fraction))
                    }
                }
                .frame(height: 6)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 2026-05-23: white card lifts off the cream AppDrawerSurface.
        // 2026-05-24: routed through AppColor tokens so the card adapts
        // to dark mode — was a hardcoded white slab on a dark drawer.
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColor.surfaceChip)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        }
        .shadow(color: AppColor.shadow, radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(badge.title), \(daysRemaining) days remaining, \(badge.subtitle)")
        )
    }

    private var allBadgesUnlockedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("All badges unlocked", systemImage: "checkmark.seal.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)

            Text("You have reached the top of this badge ladder.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var exploreAllBadgesLink: some View {
        Button {
            NotificationCenter.default.post(
                name: .openBadgesFromStreakDrawer,
                object: nil,
                userInfo: ["currentStreakDays": response?.currentDays ?? lastLoadedStreakDays ?? 0]
            )
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(streakGoldGradient)
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Explore all badges")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Explore all \(BadgeCatalog.totalCount) badges")
    }

    private var streakGoldGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.72, blue: 0.18),
                Color(red: 0.93, green: 0.42, blue: 0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var heroBackground: LinearGradient {
        // 2026-05-24: was a literal white-to-white gradient. Forwarded to
        // AppColor.surfaceChip so the hero adapts (cream/white in light,
        // mid-charcoal in dark) instead of slabbing white over a dark drawer.
        LinearGradient(
            colors: [AppColor.surfaceChip, AppColor.surfaceChip],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func heroTagline(currentBadge: StreakBadge?, nextBadge: StreakBadge?) -> String {
        if let currentBadge {
            return currentBadge.subtitle
        }
        if let nextBadge {
            return "\(nextBadge.requiredDays) logged day earns \(nextBadge.title)."
        }
        return "Every streak badge is unlocked."
    }

    private func statusCopy(for response: StreakResponse) -> String {
        switch response.status {
        case "completed_today":
            return "Logged today"
        case "at_risk_today":
            return "Today is open"
        default:
            return response.currentDays > 0 ? "Keep building" : "Ready to begin"
        }
    }

    private func heroAccessibilityLabel(for response: StreakResponse, badge: StreakBadge?) -> String {
        let streak = response.currentDays == 1 ? "1 day streak" : "\(response.currentDays) day streak"
        if let badge {
            return "\(badge.title), earned at \(badge.requiredDays) days, \(streak), longest \(response.longestDays) days"
        }
        return "No streak badge earned yet, \(streak), first badge at 1 day"
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading badge history...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var disabledCard: some View {
        Text("Badges are temporarily unavailable.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)

            Button("Retry") {
                Task { await loadStreaks() }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    @MainActor
    private func applyCachedStreaksIfAvailable() {
        let timezone = TimeZone.current.identifier
        let toDate = Self.dateKey(for: Date(), timezoneID: timezone)
        guard let snapshot = appStore.profileDashboardSnapshot,
              snapshot.isUsable(for: toDate, timezone: timezone, maxAge: 10 * 60),
              let cachedStreaks = snapshot.streaks else {
            return
        }

        response = cachedStreaks
        lastLoadedStreakDays = cachedStreaks.currentDays
        isLoading = false
        errorMessage = nil
    }

    @MainActor
    private func loadStreaks() async {
        guard appStore.configuration.progressFeatureEnabled else { return }

        isLoading = response == nil
        errorMessage = nil
        defer { isLoading = false }

        do {
            let timezone = TimeZone.current.identifier
            let toDate = Self.dateKey(for: Date(), timezoneID: timezone)
            let result = try await appStore.apiClient.getStreaks(
                range: 30,
                to: toDate,
                timezone: timezone
            )
            withAnimation(.easeInOut(duration: 0.28)) {
                response = result
            }
            detectNewlyEarnedBadges(previousDays: lastLoadedStreakDays, currentDays: result.currentDays)
            lastLoadedStreakDays = result.currentDays
        } catch let apiError as APIClientError {
            // Only surface the error card on a true cold-load failure. If
            // we already have a response from cache or a previous fetch,
            // keep showing it — a flaky refresh shouldn't make the screen
            // look broken.
            if response == nil {
                errorMessage = apiError.errorDescription ?? "Could not load badges."
            }
        } catch {
            if response == nil {
                errorMessage = "Could not load badges."
            }
        }
    }

    @MainActor
    private func detectNewlyEarnedBadges(previousDays: Int?, currentDays: Int) {
        if let badge = StreakBadgeCelebrationState.badgeToCelebrate(
            previousDays: previousDays,
            currentDays: currentDays
        ) {
            triggeredAchievement = badge
        }
    }

    static func dateKey(for date: Date, timezoneID: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezoneID) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct StreakBadgeMedallion: View {
    let badge: StreakBadge?
    let isEarned: Bool
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isEarned {
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                .white.opacity(0.95),
                                glowColor.opacity(0.40),
                                .white.opacity(0.30),
                                glowColor.opacity(0.70),
                                .white.opacity(0.95)
                            ],
                            center: .center
                        ),
                        lineWidth: max(2, size * 0.045)
                    )
                    .frame(width: size * 1.16, height: size * 1.16)
                    .shadow(color: glowColor.opacity(0.22), radius: size * 0.18)
            }

            Circle()
                .fill(backgroundGradient)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(isEarned ? 0.82 : 0.48), lineWidth: 1)
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.black.opacity(isEarned ? 0.10 : 0.04), lineWidth: max(1, size * 0.018))
                        .padding(size * 0.055)
                }
                .shadow(color: glowColor.opacity(isEarned ? 0.26 : 0.08), radius: 14, y: 7)

            // Static gloss highlight (top-left) — present on both earned + locked,
            // stronger when earned.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(isEarned ? 0.46 : 0.22), .white.opacity(0.10), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .padding(size * 0.08)

            // Animated shimmer band — only on earned medallions. A diagonal
            // light streak that travels from upper-left to lower-right every
            // ~3.6s, masked to the circle so it stays inside the medal rim.
            if isEarned && !reduceMotion {
                shimmerOverlay
                    .clipShape(Circle())
            }

            Image(systemName: badge?.systemImage ?? "trophy.fill")
                .font(.system(size: size * 0.40, weight: .heavy))
                .foregroundStyle(isEarned ? .white : Color.primary.opacity(0.38))
                .shadow(color: glowColor.opacity(isEarned ? 0.24 : 0), radius: 3, y: 1)

            if !isEarned {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(size * 0.12)
                    .background(.regularMaterial, in: Circle())
                    .offset(x: size * 0.30, y: size * 0.30)
            }
        }
        .frame(width: size * 1.16, height: size * 1.16)
    }

    /// Diagonal light streak that loops across the medal. Implemented via
    /// TimelineView so it runs without binding to any state and respects the
    /// system's animation rate. The streak fades in/out within each loop so
    /// it doesn't pop hard at the edges.
    private var shimmerOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            // Loop length 3.6s. Phase 0…1 = streak position from off-left to
            // off-right. Idle gap baked in by extending the loop past 1.
            let loop: TimeInterval = 3.6
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: loop) / loop
            let streakProgress = min(1.0, phase * 1.4) // streak finishes at ~71% of loop
            let visibility = sin(streakProgress * .pi) // 0 at edges, 1 at midpoint

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0),
                            .white.opacity(0.55),
                            .white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size * 0.45, height: size * 1.6)
                .rotationEffect(.degrees(28))
                .offset(x: -size + (size * 2 * streakProgress), y: 0)
                .opacity(visibility * 0.85)
                .blendMode(.plusLighter)
        }
    }

    private var backgroundGradient: LinearGradient {
        guard isEarned, let badge else {
            return LinearGradient(
                colors: [Color(.systemGray5), Color(.systemGray4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        switch badge.tier {
        case .bronze:
            return LinearGradient(
                colors: [Color(red: 0.98, green: 0.66, blue: 0.36), Color(red: 0.74, green: 0.36, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .silver:
            return LinearGradient(
                colors: [Color(red: 0.89, green: 0.91, blue: 0.94), Color(red: 0.50, green: 0.57, blue: 0.66)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .gold:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.80, blue: 0.24), Color(red: 0.91, green: 0.44, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .platinum:
            return LinearGradient(
                colors: [Color(red: 0.23, green: 0.24, blue: 0.30), Color(red: 0.04, green: 0.05, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var glowColor: Color {
        guard let badge else { return .secondary }
        switch badge.tier {
        case .bronze:
            return Color(red: 0.85, green: 0.39, blue: 0.14)
        case .silver:
            return Color(red: 0.54, green: 0.59, blue: 0.68)
        case .gold:
            return Color.orange
        case .platinum:
            return Color.black
        }
    }
}

private struct RevolvingStreakBadgeMedallion: View {
    let badge: StreakBadge?
    let isEarned: Bool
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let angle = reduceMotion ? -8 : rotationAngle(for: context.date)
            let radians = angle * .pi / 180
            let frontness = abs(cos(radians))
            let edgeVisibility = min(0.35, 1 - frontness)
            let depth = 0.98 + 0.02 * frontness
            let lift = -10 + 2 * sin(radians)
            let shadowX = CGFloat(sin(radians)) * size * 0.05
            let contactWidth = size * (0.72 + 0.18 * frontness)
            let ambientWidth = size * (1.05 + 0.18 * frontness)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                glowColor.opacity(isEarned ? 0.12 : 0.06),
                                glowColor.opacity(0.03),
                                .clear
                            ],
                            center: .center,
                            startRadius: 28,
                            endRadius: size * 0.95
                        )
                    )
                    .frame(width: size * 1.75, height: size * 1.75)
                    .blur(radius: 12)
                    .offset(y: 8)

                Ellipse()
                    .fill(glowColor.opacity(isEarned ? 0.08 : 0.04))
                    .frame(width: ambientWidth, height: size * 0.25)
                    .blur(radius: 22)
                    .offset(x: shadowX, y: size * 0.63)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(isEarned ? 0.24 : 0.12),
                                Color.black.opacity(isEarned ? 0.08 : 0.04)
                            ],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: contactWidth, height: size * (0.11 + 0.05 * frontness))
                    .blur(radius: 9 + 7 * edgeVisibility)
                    .offset(x: shadowX * 0.65, y: size * 0.61)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(isEarned ? 0.60 : 0.22),
                                glowColor.opacity(isEarned ? 0.32 : 0.12),
                                Color.black.opacity(isEarned ? 0.16 : 0.08)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: size * (0.025 + 0.045 * edgeVisibility), height: size * 1.02)
                    .blur(radius: 0.35)
                    .opacity(edgeVisibility * (isEarned ? 0.72 : 0.32))
                    .offset(x: CGFloat(sin(radians)) * size * 0.035, y: lift)

                StreakBadgeMedallion(badge: badge, isEarned: isEarned, size: size)
                    .rotation3DEffect(
                        .degrees(angle),
                        axis: (x: 0.10, y: 1.0, z: 0.025),
                        anchor: .center,
                        perspective: 0.78
                    )
                    .scaleEffect(depth)
                    .offset(y: lift)
                    .shadow(color: Color.black.opacity(isEarned ? 0.18 : 0.08), radius: 22, x: shadowX * 0.20, y: 18)
                    .shadow(color: glowColor.opacity(isEarned ? 0.28 : 0.10), radius: 28, x: -shadowX * 0.10, y: 10)
            }
            .frame(width: size * 1.75, height: size * 1.65)
            .compositingGroup()
        }
    }

    private func rotationAngle(for date: Date) -> Double {
        let loop: TimeInterval = 4.8
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: loop) / loop
        return -8 + sin(progress * 2 * .pi) * 7
    }

    private var glowColor: Color {
        guard let badge else { return .orange }
        switch badge.tier {
        case .bronze:
            return Color(red: 0.85, green: 0.39, blue: 0.14)
        case .silver:
            return Color(red: 0.54, green: 0.59, blue: 0.68)
        case .gold:
            return Color.orange
        case .platinum:
            return Color(red: 0.22, green: 0.24, blue: 0.32)
        }
    }
}
