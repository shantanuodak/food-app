import SwiftUI

struct HomeStreakDrawerView: View {
    @EnvironmentObject private var appStore: AppStore

    @State private var response: StreakResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// Newly-earned badge to celebrate via the full-screen popup. When non-nil,
    /// the popup is presented and the user taps (or waits) to dismiss.
    @State private var triggeredAchievement: StreakBadge?

    /// Persisted comma-separated list of badge IDs we've already shown the
    /// celebration popup for. Survives launches so we don't replay every time.
    /// Bootstrapped on first-ever load with the user's currently-earned set so
    /// existing streak holders don't see retroactive popups for old badges.
    @AppStorage("celebratedStreakBadgeIds") private var celebratedIdsRaw: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                drawerTitle

                if !appStore.configuration.progressFeatureEnabled {
                    disabledCard
                } else if isLoading && response == nil {
                    loadingCard
                } else if let response {
                    badgeHero(for: response)
                    upcomingRewardsCarousel(for: response.currentDays)
                    badgeCollection(for: response.currentDays)
                    #if DEBUG
                    debugPopupPreviewMenu
                    #endif
                } else if let errorMessage {
                    errorCard(errorMessage)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .animation(.easeInOut(duration: 0.28), value: response?.range)
        }
        .background(Color(.systemBackground))
        .task {
            await loadStreaks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionProgressDidChange)) { _ in
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

    private var drawerTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your streak")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text("Badge progress")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.primary)
        }
    }

    private func badgeHero(for response: StreakResponse) -> some View {
        let currentDays = response.currentDays
        let currentBadge = StreakRewards.currentBadge(for: currentDays)
        let nextBadge = StreakRewards.nextBadge(for: currentDays)

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                StreakBadgeMedallion(
                    badge: currentBadge ?? nextBadge,
                    isEarned: currentBadge != nil,
                    size: 76
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(currentBadge?.title ?? "Start your first streak badge today")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(heroSubtitle(for: response, currentBadge: currentBadge, nextBadge: nextBadge))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(currentDays)")
                    .font(.system(size: 46, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(streakGoldGradient)

                Text("day streak")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Label(
                    "Longest \(response.longestDays) \(response.longestDays == 1 ? "day" : "days")",
                    systemImage: "trophy.fill"
                )
                .font(.system(size: 12, weight: .bold))

                Circle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 4, height: 4)

                Text(statusCopy(for: response))
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.primary.opacity(0.72))
            .lineLimit(2)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(heroBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
        }
        .shadow(color: Color.orange.opacity(0.14), radius: 20, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibilityLabel(for: response, badge: currentBadge))
    }

    /// Horizontal paging carousel of the next 3 unearned badges. Each card
    /// shows the medallion, badge title, days-remaining count, an estimated
    /// earn-by date (today + daysRemaining since streaks are 1:1 with days),
    /// and a mini progress bar.
    ///
    /// Falls back to a single "all unlocked" card when the user has earned
    /// every defined badge.
    private func upcomingRewardsCarousel(for currentDays: Int) -> some View {
        let upcoming = StreakRewards.badges
            .filter { currentDays < $0.requiredDays }
            .prefix(3)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upcoming")
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
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(badge.title), \(daysRemaining) days remaining, \(badge.subtitle)")
        )
    }

    private var allBadgesUnlockedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("All streak badges unlocked", systemImage: "checkmark.seal.fill")
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

    private func badgeCollection(for currentDays: Int) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return VStack(alignment: .leading, spacing: 12) {
            Text("Badge collection")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(StreakRewards.badges) { badge in
                    StreakBadgeCollectionCard(
                        badge: badge,
                        isEarned: currentDays >= badge.requiredDays
                    )
                }
            }
        }
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
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.97, blue: 0.91),
                Color(red: 1.0, green: 0.89, blue: 0.76)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func heroSubtitle(
        for response: StreakResponse,
        currentBadge: StreakBadge?,
        nextBadge: StreakBadge?
    ) -> String {
        if let currentBadge {
            return "\(currentBadge.subtitle) \(nextBadge.map { "Next: \($0.title)." } ?? "Every streak badge is unlocked.")"
        }
        return nextBadge.map { "\($0.requiredDays) logged day earns \($0.title)." } ?? "Every streak badge is unlocked."
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

    #if DEBUG
    /// Debug-only preview menu for the achievement popup. Lets QA fire the
    /// popup for any badge tier without having to cross the actual threshold.
    /// Excluded from release builds via the `#if DEBUG` guard above and here.
    @ViewBuilder
    private var debugPopupPreviewMenu: some View {
        Menu {
            ForEach(StreakRewards.badges) { badge in
                Button {
                    triggeredAchievement = badge
                } label: {
                    Label(
                        "\(badge.title) (\(badge.tier.rawValue.capitalized), \(badge.requiredDays)d)",
                        systemImage: badge.systemImage
                    )
                }
            }

            Divider()

            Button(role: .destructive) {
                celebratedIdsRaw = ""
            } label: {
                Label("Reset celebrated IDs", systemImage: "arrow.counterclockwise")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "ladybug.fill")
                Text("Preview popup (DEBUG)")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.yellow.opacity(0.10))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.yellow.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
    }
    #endif

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading streak history...")
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
        Text("Streaks are temporarily disabled.")
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
    private func loadStreaks() async {
        guard appStore.configuration.progressFeatureEnabled else { return }

        isLoading = true
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
            detectNewlyEarnedBadges(currentDays: result.currentDays)
        } catch let apiError as APIClientError {
            errorMessage = apiError.errorDescription ?? "Could not load streaks."
        } catch {
            errorMessage = "Could not load streaks."
        }
    }

    /// Compares the just-loaded current-streak-days against the persisted
    /// "celebrated" set. When a new badge has been crossed since the last
    /// load, fires the full-screen popup for the highest newly-earned badge.
    ///
    /// First-ever load is a bootstrap: we mark every currently-earned badge
    /// as already celebrated so longtime users don't see retroactive popups.
    @MainActor
    private func detectNewlyEarnedBadges(currentDays: Int) {
        let earnedNow = StreakRewards.badges.filter { currentDays >= $0.requiredDays }
        let earnedNowIds = Set(earnedNow.map(\.id))

        if celebratedIdsRaw.isEmpty {
            // Bootstrap: don't celebrate retroactively.
            celebratedIdsRaw = earnedNowIds.sorted().joined(separator: ",")
            return
        }

        let alreadyCelebrated = Set(
            celebratedIdsRaw
                .split(separator: ",")
                .map(String.init)
        )
        let newlyEarned = earnedNow.filter { !alreadyCelebrated.contains($0.id) }

        // If multiple thresholds were crossed at once (e.g. user comes back
        // after a long absence), celebrate only the highest — sequential
        // popups would be spammy.
        if let highest = newlyEarned.max(by: { $0.requiredDays < $1.requiredDays }) {
            triggeredAchievement = highest
        }

        // Mark every currently-earned badge as celebrated regardless, so
        // dismiss-then-reload doesn't re-trigger.
        celebratedIdsRaw = earnedNowIds.sorted().joined(separator: ",")
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

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundGradient)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(isEarned ? 0.74 : 0.48), lineWidth: 1)
                }
                .shadow(color: glowColor.opacity(isEarned ? 0.26 : 0.08), radius: 14, y: 7)

            // Static gloss highlight (top-left) — present on both earned + locked,
            // stronger when earned.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(isEarned ? 0.32 : 0.18), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .padding(size * 0.08)

            // Animated shimmer band — only on earned medallions. A diagonal
            // light streak that travels from upper-left to lower-right every
            // ~3.6s, masked to the circle so it stays inside the medal rim.
            if isEarned {
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
        .frame(width: size, height: size)
    }

    /// Diagonal light streak that loops across the medal. Implemented via
    /// TimelineView so it runs without binding to any state and respects the
    /// system's animation rate. The streak fades in/out within each loop so
    /// it doesn't pop hard at the edges.
    private var shimmerOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
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

private struct StreakBadgeCollectionCard: View {
    let badge: StreakBadge
    let isEarned: Bool

    var body: some View {
        HStack(spacing: 10) {
            StreakBadgeMedallion(badge: badge, isEarned: isEarned, size: 42)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(badge.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isEarned ? .primary : .secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(isEarned ? "Earned at \(badge.requiredDays)d" : "\(badge.requiredDays)d")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isEarned ? Color(.secondarySystemGroupedBackground) : Color(.systemGray6).opacity(0.72))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isEarned ? Color.orange.opacity(0.16) : Color.primary.opacity(0.06), lineWidth: 1)
        }
        .opacity(isEarned ? 1 : 0.72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        isEarned
            ? "\(badge.title), earned at \(badge.requiredDays) days"
            : "\(badge.title), locked, requires \(badge.requiredDays) days"
    }
}
