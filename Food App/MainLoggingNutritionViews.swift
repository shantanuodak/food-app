import SwiftUI

struct MainLoggingNutritionSummarySheet: View {
    let totals: NutritionTotals
    let navigationTitle: String

    var body: some View {
        let macroCalories = max(1.0, totals.protein * 4 + totals.carbs * 4 + totals.fat * 9)

        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Daily Calories")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("\(Int(totals.calories.rounded())) kcal")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                VStack(spacing: 12) {
                    NutritionSummaryNutrientRow(
                        title: "Protein",
                        value: totals.protein,
                        suffix: "g",
                        percent: (totals.protein * 4) / macroCalories,
                        color: .blue
                    )
                    NutritionSummaryNutrientRow(
                        title: "Carbs",
                        value: totals.carbs,
                        suffix: "g",
                        percent: (totals.carbs * 4) / macroCalories,
                        color: .green
                    )
                    NutritionSummaryNutrientRow(
                        title: "Fat",
                        value: totals.fat,
                        suffix: "g",
                        percent: (totals.fat * 9) / macroCalories,
                        color: .orange
                    )
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct NutritionSummaryNutrientRow: View {
    let title: String
    let value: Double
    let suffix: String
    let percent: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(Int(value.rounded()))\(suffix) · \(Int((percent * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(0, min(proxy.size.width, proxy.size.width * percent)))
                }
            }
            .frame(height: 10)
        }
    }
}

extension NutritionTotals {
    static func visible(from rows: [HomeLogRow]) -> NutritionTotals {
        rows.reduce(NutritionTotals(calories: 0, protein: 0, carbs: 0, fat: 0)) { totals, row in
            let rowCalories = Double(row.calories ?? 0)
            let rowProtein: Double
            let rowCarbs: Double
            let rowFat: Double

            if !row.parsedItems.isEmpty {
                rowProtein = row.parsedItems.reduce(0) { $0 + $1.protein }
                rowCarbs = row.parsedItems.reduce(0) { $0 + $1.carbs }
                rowFat = row.parsedItems.reduce(0) { $0 + $1.fat }
            } else if let item = row.parsedItem {
                rowProtein = item.protein
                rowCarbs = item.carbs
                rowFat = item.fat
            } else {
                rowProtein = 0
                rowCarbs = 0
                rowFat = 0
            }

            return NutritionTotals(
                calories: totals.calories + rowCalories,
                protein: totals.protein + rowProtein,
                carbs: totals.carbs + rowCarbs,
                fat: totals.fat + rowFat
            )
        }
    }
}
