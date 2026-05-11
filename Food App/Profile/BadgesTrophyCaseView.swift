import SwiftUI
import UIKit

struct BadgesTrophyCaseView: View {
    let currentStreakDays: Int

    @EnvironmentObject private var appStore: AppStore
    @State private var summary: BadgesSummaryResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShareSheetPresented = false
    @State private var shareItems: [Any] = []

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
        BadgeCatalog.statesByCategory(totals: totals, currentStreakDays: currentStreakDays)
    }

    private var earnedCount: Int {
        BadgeCatalog.earnedCount(totals: totals, currentStreakDays: currentStreakDays)
    }

    private var heroData: BadgeHeroData {
        let next = StreakBadges.nextBadge(for: currentStreakDays)
        let current = StreakBadges.currentBadge(for: currentStreakDays)
        let featured = next ?? current
        let target = featured?.requiredDays ?? 1
        let title = featured?.title ?? "First Spark"
        let subtitle: String
        if next != nil {
            subtitle = "Earn \(min(currentStreakDays, target))/\(target)"
        } else {
            subtitle = "Every streak badge unlocked"
        }

        return BadgeHeroData(
            title: title,
            subtitle: subtitle,
            systemImage: featured?.systemImage ?? "sparkle",
            currentValue: min(currentStreakDays, target),
            targetValue: target,
            earnedCount: earnedCount,
            totalCount: BadgeCatalog.totalCount,
            streakDays: currentStreakDays
        )
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
        .background(BadgeTokens.canvas.ignoresSafeArea())
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadBadges()
        }
        .refreshable {
            await loadBadges()
        }
        .sheet(isPresented: $isShareSheetPresented) {
            BadgeActivityView(activityItems: shareItems)
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
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    BadgeCard(state: badge, isLoading: isLoading)
                }
            }
        }
    }

    @MainActor
    private func loadBadges() async {
        isLoading = true
        errorMessage = nil
        do {
            summary = try await appStore.apiClient.getBadgesSummary(timezone: TimeZone.current.identifier)
        } catch is CancellationError {
        } catch {
            errorMessage = "Couldn't load badges yet."
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(BadgeTokens.goldGradient)
                    Image(systemName: data.systemImage)
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 72, height: 72)
                .shadow(color: BadgeTokens.amber.opacity(0.25), radius: 18, y: 8)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Badges")
                        .font(.custom("InstrumentSerif-Regular", size: 34))
                        .foregroundStyle(BadgeTokens.ink)
                    Text(data.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(BadgeTokens.ink)
                    Text(data.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BadgeTokens.muted)
                }
                Spacer(minLength: 0)

                if showsShareButton {
                    Button {
                        onShare?()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(BadgeTokens.orange)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.72), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share badge")
                }
            }

            HStack(spacing: 10) {
                heroStat(value: "\(data.earnedCount)", label: "earned")
                heroStat(value: "\(data.totalCount)", label: "total")
                heroStat(value: "\(data.streakDays)", label: "day streak")
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
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private var definition: BadgeDefinition { state.definition }

    var body: some View {
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
                .stroke(state.isEarned ? BadgeTokens.amber.opacity(0.28) : Color.white.opacity(0.72), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(state.isEarned ? 0.045 : 0.025), radius: 10, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
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

    private var cardFill: Color {
        state.isEarned ? Color.white.opacity(0.86) : Color.white.opacity(0.56)
    }

    private var statusFill: Color {
        state.isEarned ? BadgeTokens.amber.opacity(0.13) : BadgeTokens.gray200.opacity(0.7)
    }

    private var accessibilityLabel: String {
        if state.isEarned {
            return "\(definition.title), earned badge. \(definition.subtitle)"
        }
        return "\(definition.title), locked badge. \(state.remaining) more needed. \(definition.subtitle)"
    }
}

private enum BadgeTokens {
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
        BadgesTrophyCaseView(currentStreakDays: 9)
            .environmentObject(AppStore())
    }
}
