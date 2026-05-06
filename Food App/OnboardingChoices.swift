import Foundation

enum SexOption: String, CaseIterable, Identifiable, Codable {
    case male
    case female
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .other: return "Other"
        }
    }
}

enum ActivityChoice: String, CaseIterable, Identifiable, Codable {
    case mostlySitting
    case lightlyActive
    case moderatelyActive
    case veryActive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mostlySitting: return "Mostly sitting"
        case .lightlyActive: return "Lightly active"
        case .moderatelyActive: return "Moderately active"
        case .veryActive: return "Very active"
        }
    }

    var apiValue: ActivityLevelOption {
        switch self {
        case .mostlySitting: return .low
        case .lightlyActive, .moderatelyActive: return .moderate
        case .veryActive: return .high
        }
    }
}

enum PaceChoice: String, CaseIterable, Identifiable, Codable {
    case conservative
    case balanced
    case aggressive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conservative: return "Conservative"
        case .balanced: return "Balanced"
        case .aggressive: return "Aggressive"
        }
    }
}

/// A multi-select chip option that can be rendered by `OnboardingChipSelector`.
/// Both diet preferences and allergies conform.
protocol ChipOption: Identifiable, Hashable {
    var title: String { get }
}

enum PreferenceChoice: String, CaseIterable, Identifiable, Hashable, Codable, ChipOption {
    case highProtein = "high_protein"
    case vegetarian
    case vegan
    case pescatarian
    case lowCarb = "low_carb"
    case keto
    case glutenFree = "gluten_free"
    case dairyFree = "dairy_free"
    case halal
    case lowSodium = "low_sodium"
    case mediterranean
    case noPreference = "no_preference"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highProtein: return "High protein"
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .pescatarian: return "Pescatarian"
        case .lowCarb: return "Low carb"
        case .keto: return "Keto"
        case .glutenFree: return "Gluten free"
        case .dairyFree: return "Dairy free"
        case .halal: return "Halal"
        case .lowSodium: return "Low sodium"
        case .mediterranean: return "Mediterranean"
        case .noPreference: return "No preference"
        }
    }
}

/// Common food allergens shown as multi-select chips in OB06 and the Profile.
///
/// IMPORTANT: the `matchTokens` here are mirrored on the backend in
/// `backend/src/services/dietaryConflictService.ts`. Backend is the
/// authoritative source for actual conflict detection; the iOS list is
/// used only for client-side preview before the backend response lands.
/// If you edit one list, edit the other.
enum AllergyChoice: String, CaseIterable, Identifiable, Hashable, Codable, ChipOption {
    case peanuts
    case treeNuts = "tree_nuts"
    case gluten
    case dairy
    case eggs
    case shellfish
    case fish
    case soy
    case sesame

    var id: String { rawValue }

    var title: String {
        switch self {
        case .peanuts: return "Peanuts"
        case .treeNuts: return "Tree nuts"
        case .gluten: return "Gluten / wheat"
        case .dairy: return "Dairy"
        case .eggs: return "Eggs"
        case .shellfish: return "Shellfish"
        case .fish: return "Fish"
        case .soy: return "Soy"
        case .sesame: return "Sesame"
        }
    }

    /// SF Symbol icon for chip/list rendering. One per case so users can
    /// scan the list visually rather than reading every label.
    var systemImage: String {
        switch self {
        case .peanuts:   return "circle.hexagongrid.fill"
        case .treeNuts:  return "tree.fill"
        case .gluten:    return "leaf.fill"
        case .dairy:     return "drop.fill"
        case .eggs:      return "oval.portrait.fill"
        case .shellfish: return "drop.triangle.fill"
        case .fish:      return "fish.fill"
        case .soy:       return "leaf.circle.fill"
        case .sesame:    return "circle.grid.3x3.fill"
        }
    }

    /// Lowercase substrings used for client-side conflict preview against parsed
    /// food item names. The backend has the authoritative version.
    var matchTokens: [String] {
        switch self {
        case .peanuts: return ["peanut"]
        case .treeNuts: return ["almond", "walnut", "cashew", "pecan", "pistachio", "hazelnut", "macadamia", "brazil nut"]
        case .gluten: return ["bread", "pasta", "wheat", "flour", "noodle", "barley", "rye", "couscous", "cracker", "pita", "tortilla", "bagel", "pretzel"]
        case .dairy: return ["milk", "cheese", "butter", "cream", "yogurt", "yoghurt", "ice cream", "whey", "paneer", "ghee"]
        case .eggs: return ["egg", "omelet", "omelette", "frittata", "quiche"]
        case .shellfish: return ["shrimp", "prawn", "lobster", "crab", "crawfish", "scallop", "clam", "oyster", "mussel"]
        case .fish: return ["salmon", "tuna", "cod", "tilapia", "mackerel", "trout", "halibut", "sardine", "anchovy", "bass"]
        case .soy: return ["soy", "tofu", "edamame", "tempeh", "miso", "soybean"]
        case .sesame: return ["sesame", "tahini"]
        }
    }
}

enum ExperienceChoice: String, CaseIterable, Identifiable, Codable {
    case newToIt
    case triedButQuit
    case currentlyCounting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newToIt: return "I'm new to calorie counting"
        case .triedButQuit: return "I've tried it before but quit"
        case .currentlyCounting: return "I'm currently counting"
        }
    }

    var icon: String {
        switch self {
        case .newToIt: return "flame"
        case .triedButQuit: return "arrow.uturn.backward.circle"
        case .currentlyCounting: return "number.square"
        }
    }
}

enum ChallengeChoice: String, CaseIterable, Identifiable, Codable {
    case portionControl
    case snacking
    case eatingOut
    case inconsistentMeals
    case emotionalEating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portionControl: return "Portion control"
        case .snacking: return "Late-night snacking"
        case .eatingOut: return "Eating out too often"
        case .inconsistentMeals: return "Inconsistent meals"
        case .emotionalEating: return "Emotional eating"
        }
    }

    var subtitle: String {
        switch self {
        case .portionControl: return "Hard to know the right serving size"
        case .snacking: return "Cravings that undo my progress"
        case .eatingOut: return "Restaurant meals are hard to track"
        case .inconsistentMeals: return "I skip meals or eat at random times"
        case .emotionalEating: return "I eat when stressed or bored"
        }
    }

    var icon: String {
        switch self {
        case .portionControl: return "chart.pie"
        case .snacking: return "moon.stars"
        case .eatingOut: return "fork.knife.circle"
        case .inconsistentMeals: return "clock.arrow.2.circlepath"
        case .emotionalEating: return "heart.circle"
        }
    }
}

enum AccountProvider: String, Codable {
    case apple
    case google
}
