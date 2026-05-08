import SwiftUI

struct RewardsTrophyCaseView: View {
    let currentStreakDays: Int

    @EnvironmentObject private var appStore: AppStore
    @State private var summary: RewardsSummaryResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var totals: RewardsTotals {
        summary?.totals ?? RewardsTotals(
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

    private var groupedBadges: [(RewardBadgeDefinition.Category, [RewardBadgeState])] {
        RewardCatalog.statesByCategory(totals: totals, currentStreakDays: currentStreakDays)
    }

    private var earnedCount: Int {
        RewardCatalog.earnedCount(totals: totals, currentStreakDays: currentStreakDays)
    }

    var body: some View {
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
        .background(RewardTokens.canvas.ignoresSafeArea())
        .navigationTitle("Rewards")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadRewards()
        }
        .refreshable {
            await loadRewards()
        }
    }

    private var heroCard: some View {
        let current = StreakRewards.currentBadge(for: currentStreakDays)
        let title = current?.title ?? "First Spark awaits"
        let subtitle = current == nil ? "Start with one logged day." : "Current streak badge"

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(RewardTokens.goldGradient)
                    Image(systemName: current?.systemImage ?? "sparkle")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 72, height: 72)
                .shadow(color: RewardTokens.amber.opacity(0.25), radius: 18, y: 8)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Trophy case")
                        .font(.custom("InstrumentSerif-Regular", size: 34))
                        .foregroundStyle(RewardTokens.ink)
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(RewardTokens.ink)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(RewardTokens.muted)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                heroStat(value: "\(earnedCount)", label: "earned")
                heroStat(value: "\(RewardCatalog.totalCount)", label: "total")
                heroStat(value: "\(currentStreakDays)", label: "day streak")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color(red: 1.0, green: 0.965, blue: 0.885)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rewards trophy case. \(earnedCount) of \(RewardCatalog.totalCount) badges earned. Current streak badge: \(title).")
    }

    private func heroStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(RewardTokens.ink)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(RewardTokens.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(RewardTokens.amber)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(RewardTokens.ink)
            Spacer()
            Button("Retry") {
                Task { await loadRewards() }
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(RewardTokens.orange)
        }
        .padding(12)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func badgeSection(category: RewardBadgeDefinition.Category, badges: [RewardBadgeState]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category.rawValue.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(RewardTokens.muted)
                .padding(.horizontal, 2)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(badges) { badge in
                    RewardBadgeCard(state: badge, isLoading: isLoading)
                }
            }
        }
    }

    @MainActor
    private func loadRewards() async {
        isLoading = true
        errorMessage = nil
        do {
            summary = try await appStore.apiClient.getRewardsSummary(timezone: TimeZone.current.identifier)
        } catch is CancellationError {
        } catch {
            errorMessage = "Couldn't load rewards yet."
        }
        isLoading = false
    }
}

private struct RewardBadgeCard: View {
    let state: RewardBadgeState
    let isLoading: Bool

    private var definition: RewardBadgeDefinition { state.definition }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(iconFill)
                    Image(systemName: state.isEarned ? definition.systemImage : "lock.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(state.isEarned ? .white : RewardTokens.muted)
                }
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

                Spacer()

                Text(state.isEarned ? "Earned" : "\(state.remaining) left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(state.isEarned ? RewardTokens.orange : RewardTokens.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(statusFill, in: Capsule())
            }

            Text(definition.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(state.isEarned ? RewardTokens.ink : RewardTokens.muted)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(definition.subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(RewardTokens.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: isLoading ? 0 : state.progress)
                .tint(state.isEarned ? RewardTokens.amber : RewardTokens.muted.opacity(0.45))
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(state.isEarned ? RewardTokens.amber.opacity(0.28) : Color.white.opacity(0.72), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(state.isEarned ? 0.045 : 0.025), radius: 10, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconFill: LinearGradient {
        if state.isEarned {
            switch definition.rarity {
            case .bronze:
                return RewardTokens.bronzeGradient
            case .silver:
                return RewardTokens.silverGradient
            case .gold:
                return RewardTokens.goldGradient
            case .platinum:
                return RewardTokens.platinumGradient
            }
        }
        return LinearGradient(colors: [RewardTokens.gray200, RewardTokens.gray100], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var cardFill: Color {
        state.isEarned ? Color.white.opacity(0.86) : Color.white.opacity(0.56)
    }

    private var statusFill: Color {
        state.isEarned ? RewardTokens.amber.opacity(0.13) : RewardTokens.gray200.opacity(0.7)
    }

    private var accessibilityLabel: String {
        if state.isEarned {
            return "\(definition.title), earned badge. \(definition.subtitle)"
        }
        return "\(definition.title), locked badge. \(state.remaining) more needed. \(definition.subtitle)"
    }
}

private enum RewardTokens {
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let ink = Color(red: 0.129, green: 0.145, blue: 0.161)
    static let muted = Color(red: 0.525, green: 0.557, blue: 0.588)
    static let gray100 = Color(red: 0.945, green: 0.953, blue: 0.961)
    static let gray200 = Color(red: 0.914, green: 0.925, blue: 0.937)
    static let amber = Color(red: 0.961, green: 0.647, blue: 0.141)
    static let orange = Color(red: 0.902, green: 0.361, blue: 0.102)

    static let bronzeGradient = LinearGradient(colors: [Color(red: 0.86, green: 0.50, blue: 0.27), Color(red: 0.62, green: 0.32, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let silverGradient = LinearGradient(colors: [Color(red: 0.82, green: 0.87, blue: 0.91), Color(red: 0.48, green: 0.55, blue: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let goldGradient = LinearGradient(colors: [Color(red: 1.00, green: 0.76, blue: 0.22), Color(red: 0.91, green: 0.39, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let platinumGradient = LinearGradient(colors: [Color(red: 0.15, green: 0.16, blue: 0.19), Color(red: 0.56, green: 0.58, blue: 0.64)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

#Preview {
    NavigationStack {
        RewardsTrophyCaseView(currentStreakDays: 9)
            .environmentObject(AppStore())
    }
}
