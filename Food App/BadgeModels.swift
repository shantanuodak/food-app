import Foundation

struct BadgeDefinition: Identifiable, Equatable {
    enum Category: String, CaseIterable, Identifiable {
        case streaks = "Streaks"
        case logging = "Logging"
        case input = "Input mastery"
        case variety = "Variety"
        case accuracy = "Accuracy"
        case health = "Health activity"

        var id: String { rawValue }
    }

    enum Rarity: String {
        case bronze
        case silver
        case gold
        case platinum
    }

    let id: String
    let category: Category
    let title: String
    let subtitle: String
    let systemImage: String
    let requiredValue: Int
    let rarity: Rarity
}

struct BadgeState: Identifiable, Equatable {
    let definition: BadgeDefinition
    let currentValue: Int

    var id: String { definition.id }
    var isEarned: Bool { currentValue >= definition.requiredValue }
    var remaining: Int { max(0, definition.requiredValue - currentValue) }
    var progress: Double {
        guard definition.requiredValue > 0 else { return isEarned ? 1 : 0 }
        return min(1, max(0, Double(currentValue) / Double(definition.requiredValue)))
    }
}

enum BadgeCatalog {
    static func states(totals: BadgesTotals, currentStreakDays: Int) -> [BadgeState] {
        definitions.map { definition in
            BadgeState(definition: definition, currentValue: value(for: definition, totals: totals, currentStreakDays: currentStreakDays))
        }
    }

    static func statesByCategory(totals: BadgesTotals, currentStreakDays: Int) -> [(BadgeDefinition.Category, [BadgeState])] {
        let states = states(totals: totals, currentStreakDays: currentStreakDays)
        return BadgeDefinition.Category.allCases.compactMap { category in
            let matches = states.filter { $0.definition.category == category }
            return matches.isEmpty ? nil : (category, matches)
        }
    }

    static func earnedCount(totals: BadgesTotals, currentStreakDays: Int) -> Int {
        states(totals: totals, currentStreakDays: currentStreakDays).filter(\.isEarned).count
    }

    static var totalCount: Int { definitions.count }

    private static func value(for definition: BadgeDefinition, totals: BadgesTotals, currentStreakDays: Int) -> Int {
        switch definition.id {
        case let id where id.hasPrefix("streak_"):
            return currentStreakDays
        case "meal_starter", "meal_regular", "logging_veteran":
            return totals.logs
        case "food_collector", "plate_curator", "food_archivist":
            return totals.foodItems
        case "text_logger":
            return totals.textLogs
        case "voice_logger":
            return totals.voiceLogs
        case "camera_logger":
            return totals.imageLogs
        case "hands_on_editor":
            return totals.manualLogs + totals.manualOverrideItems
        case "variety_explorer", "broad_palate", "flavor_atlas":
            return totals.uniqueFoods
        case "clean_parser":
            return totals.highConfidenceLogs
        case "trusted_matches":
            return totals.highConfidenceItems
        case "careful_reviewer":
            return totals.manualOverrideItems
        case "move_sync", "active_week":
            return totals.healthActiveDays
        case "ten_k_club":
            return totals.healthStepDays10k
        default:
            return 0
        }
    }

    private static let definitions: [BadgeDefinition] = [
        BadgeDefinition(id: "streak_first_spark", category: .streaks, title: "First Spark", subtitle: "Log your first day.", systemImage: "sparkle", requiredValue: 1, rarity: .bronze),
        BadgeDefinition(id: "streak_weekly_flame", category: .streaks, title: "Weekly Flame", subtitle: "Keep a 7-day streak.", systemImage: "flame.circle.fill", requiredValue: 7, rarity: .silver),
        BadgeDefinition(id: "streak_locked_in", category: .streaks, title: "Locked In", subtitle: "Keep a 30-day streak.", systemImage: "lock.circle.fill", requiredValue: 30, rarity: .gold),
        BadgeDefinition(id: "streak_century_club", category: .streaks, title: "Century Club", subtitle: "Keep a 100-day streak.", systemImage: "100.circle.fill", requiredValue: 100, rarity: .platinum),
        BadgeDefinition(id: "meal_starter", category: .logging, title: "Meal Starter", subtitle: "Log 10 meals.", systemImage: "fork.knife.circle.fill", requiredValue: 10, rarity: .bronze),
        BadgeDefinition(id: "meal_regular", category: .logging, title: "Meal Regular", subtitle: "Log 50 meals.", systemImage: "calendar.circle.fill", requiredValue: 50, rarity: .silver),
        BadgeDefinition(id: "logging_veteran", category: .logging, title: "Logging Veteran", subtitle: "Log 100 meals.", systemImage: "checkmark.seal.fill", requiredValue: 100, rarity: .gold),
        BadgeDefinition(id: "food_collector", category: .logging, title: "Food Collector", subtitle: "Record 100 food items.", systemImage: "square.grid.2x2.fill", requiredValue: 100, rarity: .bronze),
        BadgeDefinition(id: "plate_curator", category: .logging, title: "Plate Curator", subtitle: "Record 250 food items.", systemImage: "tray.full.fill", requiredValue: 250, rarity: .silver),
        BadgeDefinition(id: "food_archivist", category: .logging, title: "Food Archivist", subtitle: "Record 500 food items.", systemImage: "archivebox.circle.fill", requiredValue: 500, rarity: .gold),
        BadgeDefinition(id: "text_logger", category: .input, title: "Text Logger", subtitle: "Log with text.", systemImage: "keyboard.fill", requiredValue: 1, rarity: .bronze),
        BadgeDefinition(id: "voice_logger", category: .input, title: "Voice Logger", subtitle: "Log with voice.", systemImage: "mic.circle.fill", requiredValue: 1, rarity: .bronze),
        BadgeDefinition(id: "camera_logger", category: .input, title: "Camera Logger", subtitle: "Log with the camera.", systemImage: "camera.circle.fill", requiredValue: 1, rarity: .bronze),
        BadgeDefinition(id: "hands_on_editor", category: .input, title: "Hands-On Editor", subtitle: "Review or manually adjust a meal.", systemImage: "slider.horizontal.3", requiredValue: 1, rarity: .silver),
        BadgeDefinition(id: "variety_explorer", category: .variety, title: "Variety Explorer", subtitle: "Log 25 unique foods.", systemImage: "globe.americas.fill", requiredValue: 25, rarity: .bronze),
        BadgeDefinition(id: "broad_palate", category: .variety, title: "Broad Palate", subtitle: "Log 75 unique foods.", systemImage: "map.circle.fill", requiredValue: 75, rarity: .silver),
        BadgeDefinition(id: "flavor_atlas", category: .variety, title: "Flavor Atlas", subtitle: "Log 150 unique foods.", systemImage: "sparkles", requiredValue: 150, rarity: .gold),
        BadgeDefinition(id: "clean_parser", category: .accuracy, title: "Clean Parser", subtitle: "Log 20 high-confidence meals.", systemImage: "checkmark.circle.fill", requiredValue: 20, rarity: .silver),
        BadgeDefinition(id: "trusted_matches", category: .accuracy, title: "Trusted Matches", subtitle: "Get 50 high-confidence food matches.", systemImage: "seal.fill", requiredValue: 50, rarity: .silver),
        BadgeDefinition(id: "careful_reviewer", category: .accuracy, title: "Careful Reviewer", subtitle: "Manually refine 10 food items.", systemImage: "pencil.and.outline", requiredValue: 10, rarity: .gold),
        BadgeDefinition(id: "move_sync", category: .health, title: "Move Sync", subtitle: "Sync 3 active Health days.", systemImage: "figure.walk.circle.fill", requiredValue: 3, rarity: .bronze),
        BadgeDefinition(id: "active_week", category: .health, title: "Active Week", subtitle: "Sync 7 active Health days.", systemImage: "heart.circle.fill", requiredValue: 7, rarity: .silver),
        BadgeDefinition(id: "ten_k_club", category: .health, title: "Ten-K Club", subtitle: "Reach 10k steps on 3 days.", systemImage: "shoeprints.fill", requiredValue: 3, rarity: .gold)
    ]
}
