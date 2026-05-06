import SwiftUI
import Charts

struct ChartScale {
    let minY: Double
    let maxY: Double

    func clamp(_ value: Double) -> Double {
        min(max(value, minY), maxY)
    }
}

/// Mode-aware color tokens for the progress charts. Replaces the
/// `Color.white.opacity(...)` / `Color.black.opacity(...)` literals
/// that assumed a dark canvas — every value here adapts to light
/// mode automatically. When a real design system lands, swap these
/// statics for tokens without touching the chart bodies.
enum ChartPalette {
    // Surfaces
    static let cardBackground: Color = Color(.tertiarySystemBackground)
    static let pointFill: Color      = Color(.systemBackground)

    // Lines & ticks
    static let gridLine: Color   = Color(.separator)
    static let scrubLine: Color  = Color.primary.opacity(0.4)
    static let targetLine: Color = Color.secondary.opacity(0.7)

    // Macros
    static let protein = Color(red: 0.19, green: 0.72, blue: 0.98)
    static let carbs   = Color(red: 0.99, green: 0.64, blue: 0.22)
    static let fat     = Color(red: 0.98, green: 0.38, blue: 0.36)

    // Hero card accents (used as 1pt strokes over Material)
    static let calorieAccent: Color = Color.green
    static let weightAccent: Color  = Color.blue
    static let stepsAccent: Color   = Color.orange
}

enum ProgressRange: Int, CaseIterable, Identifiable, Hashable {
    case week       = 7
    case month      = 30
    case sixMonths  = 180
    case year       = 365

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .week:      return "W"
        case .month:     return "M"
        case .sixMonths: return "6M"
        case .year:      return "Y"
        }
    }
}

enum MacroMetric: String, CaseIterable {
    case protein
    case carbs
    case fat

    var title: String {
        switch self {
        case .protein: return "Protein"
        case .carbs: return "Carbs"
        case .fat: return "Fat"
        }
    }

    var color: Color {
        switch self {
        case .protein: return ChartPalette.protein
        case .carbs:   return ChartPalette.carbs
        case .fat:     return ChartPalette.fat
        }
    }
}

struct NutritionChartPoint: Identifiable {
    let date: Date
    let consumed: Double
    let target: Double
    let hasLogs: Bool

    var id: Date { date }
}

struct WeightChartPoint: Identifiable {
    let date: Date
    let value: Double
    let smoothedValue: Double

    var id: Date { date }
}
