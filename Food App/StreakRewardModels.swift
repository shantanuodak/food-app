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

    nonisolated init(
        id: String,
        title: String,
        requiredDays: Int,
        subtitle: String,
        systemImage: String,
        tier: Tier
    ) {
        self.id = id
        self.title = title
        self.requiredDays = requiredDays
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tier = tier
    }

    nonisolated init(definition: BadgeDefinition) {
        self.init(
            id: definition.id.replacingOccurrences(of: "streak_", with: ""),
            title: definition.title,
            requiredDays: definition.requiredValue,
            subtitle: definition.subtitle,
            systemImage: definition.systemImage,
            tier: Tier(rarity: definition.rarity)
        )
    }

    var badgeDefinitionId: String {
        "streak_\(id)"
    }
}

extension StreakBadge.Tier {
    nonisolated init(rarity: BadgeDefinition.Rarity) {
        switch rarity {
        case .bronze:
            self = .bronze
        case .silver:
            self = .silver
        case .gold:
            self = .gold
        case .platinum:
            self = .platinum
        }
    }
}

struct StreakBadgeProgress: Equatable {
    let previousThreshold: Int
    let targetThreshold: Int
    let completedDays: Int
    let daysRemaining: Int
    let fraction: Double
}

enum StreakBadges {
    static var badges: [StreakBadge] {
        BadgeCatalog.streakDefinitions.map(StreakBadge.init(definition:))
    }

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
