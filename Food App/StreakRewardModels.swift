import Foundation

struct StreakBadge: Identifiable, Equatable {
    enum Tier: String {
        case bronze
        case silver
        case gold
        case platinum
    }

    let id: String
    let title: String
    let requiredDays: Int
    let subtitle: String
    let systemImage: String
    let tier: Tier
}

struct StreakBadgeProgress: Equatable {
    let previousThreshold: Int
    let targetThreshold: Int
    let completedDays: Int
    let daysRemaining: Int
    let fraction: Double
}

enum StreakBadges {
    static let badges: [StreakBadge] = [
        StreakBadge(
            id: "first_spark",
            title: "First Spark",
            requiredDays: 1,
            subtitle: "Your first logged day.",
            systemImage: "sparkle",
            tier: .bronze
        ),
        StreakBadge(
            id: "getting_warm",
            title: "Getting Warm",
            requiredDays: 3,
            subtitle: "Three days of showing up.",
            systemImage: "flame.fill",
            tier: .bronze
        ),
        StreakBadge(
            id: "weekly_flame",
            title: "Weekly Flame",
            requiredDays: 7,
            subtitle: "A full week of logging.",
            systemImage: "flame.circle.fill",
            tier: .silver
        ),
        StreakBadge(
            id: "momentum_maker",
            title: "Momentum Maker",
            requiredDays: 14,
            subtitle: "Two weeks of momentum.",
            systemImage: "forward.circle.fill",
            tier: .silver
        ),
        StreakBadge(
            id: "locked_in",
            title: "Locked In",
            requiredDays: 30,
            subtitle: "Thirty days of consistency.",
            systemImage: "lock.circle.fill",
            tier: .gold
        ),
        StreakBadge(
            id: "ritual_builder",
            title: "Ritual Builder",
            requiredDays: 60,
            subtitle: "Logging has become a ritual.",
            systemImage: "calendar.badge.checkmark",
            tier: .gold
        ),
        StreakBadge(
            id: "century_club",
            title: "Century Club",
            requiredDays: 100,
            subtitle: "One hundred days of follow-through.",
            systemImage: "100.circle.fill",
            tier: .platinum
        ),
        StreakBadge(
            id: "unbroken_year",
            title: "Unbroken Year",
            requiredDays: 365,
            subtitle: "A full year of logging.",
            systemImage: "trophy.circle.fill",
            tier: .platinum
        )
    ]

    static func currentBadge(for currentDays: Int) -> StreakBadge? {
        badges.last { currentDays >= $0.requiredDays }
    }

    static func nextBadge(for currentDays: Int) -> StreakBadge? {
        badges.first { currentDays < $0.requiredDays }
    }

    static func earnedBadges(for currentDays: Int) -> [StreakBadge] {
        badges.filter { currentDays >= $0.requiredDays }
    }

    static func lockedBadges(for currentDays: Int) -> [StreakBadge] {
        badges.filter { currentDays < $0.requiredDays }
    }

    static func progressToNext(for currentDays: Int) -> StreakBadgeProgress? {
        guard let next = nextBadge(for: currentDays) else { return nil }
        let previousThreshold = currentBadge(for: currentDays)?.requiredDays ?? 0
        let span = max(1, next.requiredDays - previousThreshold)
        let completed = min(max(0, currentDays - previousThreshold), span)
        let remaining = max(0, next.requiredDays - currentDays)
        return StreakBadgeProgress(
            previousThreshold: previousThreshold,
            targetThreshold: next.requiredDays,
            completedDays: completed,
            daysRemaining: remaining,
            fraction: Double(completed) / Double(span)
        )
    }
}

enum StreakBadgeCelebrationState {
    private static let celebratedIdsKey = "celebratedStreakBadgeIds"
    private static let bootstrappedKey = "hasBootstrappedStreakCelebrations"

    static func badgeToCelebrate(previousDays: Int?, currentDays: Int, defaults: UserDefaults = .standard) -> StreakBadge? {
        let earnedNow = StreakBadges.badges.filter { currentDays >= $0.requiredDays }
        let earnedNowIds = Set(earnedNow.map(\.id))
        let alreadyCelebrated = celebratedIds(defaults: defaults)

        defer {
            defaults.set(earnedNowIds.sorted().joined(separator: ","), forKey: celebratedIdsKey)
            defaults.set(true, forKey: bootstrappedKey)
        }

        if let previousDays, currentDays > previousDays {
            let crossedNow = earnedNow.filter { badge in
                previousDays < badge.requiredDays &&
                currentDays >= badge.requiredDays &&
                !alreadyCelebrated.contains(badge.id)
            }
            return crossedNow.max(by: { $0.requiredDays < $1.requiredDays })
        }

        guard defaults.bool(forKey: bootstrappedKey) else {
            return nil
        }

        let newlyEarned = earnedNow.filter { !alreadyCelebrated.contains($0.id) }
        return newlyEarned.max(by: { $0.requiredDays < $1.requiredDays })
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: celebratedIdsKey)
        defaults.removeObject(forKey: bootstrappedKey)
    }

    private static func celebratedIds(defaults: UserDefaults) -> Set<String> {
        Set(
            (defaults.string(forKey: celebratedIdsKey) ?? "")
                .split(separator: ",")
                .map(String.init)
        )
    }
}
