import SwiftUI
import Foundation

private let kDrawerPurple = Color(red: 0.420, green: 0.369, blue: 1.0)
private let kDrawerProtein = Color(red: 0.420, green: 0.369, blue: 1.0)
private let kDrawerCarbs = Color(red: 0.106, green: 0.620, blue: 0.353)
private let kDrawerFat = Color(red: 0.000, green: 0.478, blue: 1.0)

enum LoggingResultDrawerMode {
    case textDetails
    case photoReview
}

/// Shared result body used by both the camera drawer (CameraResultDrawerView)
/// and the text-entry drawer (detailsDrawer in MainLoggingShellView).
/// Callers place whatever appears above this (hero image or eyebrow label),
/// and whatever appears below (CTAs or nothing for auto-saved text flow).
struct LoggingResultDrawerBody: View {
    let foodName: String
    let totals: NutritionTotals
    let items: [ParsedFoodItem]
    let thoughtProcess: String
    let mode: LoggingResultDrawerMode
    let showsThoughtProcess: Bool
    let onItemQuantityChange: ((Int, Double) -> Void)?
    let onRecalculate: (() -> Void)?

    init(
        foodName: String,
        totals: NutritionTotals,
        items: [ParsedFoodItem],
        thoughtProcess: String,
        mode: LoggingResultDrawerMode = .textDetails,
        showsThoughtProcess: Bool = true,
        onItemQuantityChange: ((Int, Double) -> Void)?,
        onRecalculate: (() -> Void)?
    ) {
        self.foodName = foodName
        self.totals = totals
        self.items = items
        self.thoughtProcess = thoughtProcess
        self.mode = mode
        self.showsThoughtProcess = showsThoughtProcess
        self.onItemQuantityChange = onItemQuantityChange
        self.onRecalculate = onRecalculate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mode == .photoReview {
                photoSummaryLabel
            }
            foodNameView
            calorieHero
            macroCards
            if !items.isEmpty {
                detectedItemsList
            }
            if showsThoughtProcess {
                LoggingResultThoughtProcessCard(thoughtProcess: thoughtProcess)
            }
            if let onRecalculate {
                Button(action: onRecalculate) {
                    Text("Something wrong? Recalculate")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(kDrawerPurple)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            }
        }
    }

    // MARK: - Food name — Title 2

    private var foodNameView: some View {
        Text(foodName)
            .font(.system(size: mode == .photoReview ? 20 : 22, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .padding(.horizontal, 20)
            .padding(.top, mode == .photoReview ? 4 : 12)
    }

    // MARK: - Calorie hero — Large Title

    private var calorieHero: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(totals.calories.rounded()))")
                    .font(.system(size: mode == .photoReview ? 42 : 44, weight: .bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text("cal")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Macro cards

    private var macroCards: some View {
        HStack(spacing: 8) {
            drawerMacroCard(
                icon: "figure.strengthtraining.traditional",
                value: "\(Int(totals.protein.rounded()))g",
                label: "Protein",
                iconColor: kDrawerProtein,
                bgColor: kDrawerProtein.opacity(0.11)
            )
            drawerMacroCard(
                icon: "leaf.fill",
                value: "\(Int(totals.carbs.rounded()))g",
                label: "Carbs",
                iconColor: kDrawerCarbs,
                bgColor: kDrawerCarbs.opacity(0.11)
            )
            drawerMacroCard(
                icon: "drop.fill",
                value: "\(Int(totals.fat.rounded()))g",
                label: "Fat",
                iconColor: kDrawerFat,
                bgColor: kDrawerFat.opacity(0.11)
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    @ViewBuilder
    private func drawerMacroCard(
        icon: String,
        value: String,
        label: String,
        iconColor: Color,
        bgColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(bgColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Detected items

    private var detectedItemsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Detected items")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 10)

            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                detectedItemRow(item: item, itemOffset: idx)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
        }
    }

    private func detectedItemRow(item: ParsedFoodItem, itemOffset: Int) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Text(quantityLabel(for: item))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                if let onItemQuantityChange {
                    quantityStepper(item: item, itemOffset: itemOffset, onChange: onItemQuantityChange)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 5) {
                Text("\(Int(item.calories.rounded())) cal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()

                Text("P \(formatMacro(item.protein)) · C \(formatMacro(item.carbs)) · F \(formatMacro(item.fat))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(minHeight: onItemQuantityChange == nil ? 82 : 100)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }

    private var photoSummaryLabel: some View {
        Text(items.count == 1 ? "Detected from photo" : "\(items.count) items detected from photo")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(kDrawerPurple)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(kDrawerPurple.opacity(0.12), in: Capsule())
            .padding(.horizontal, 20)
            .padding(.top, 18)
    }

    private func quantityStepper(
        item: ParsedFoodItem,
        itemOffset: Int,
        onChange: @escaping (Int, Double) -> Void
    ) -> some View {
        let quantity = item.amount ?? item.quantity
        let canDecrease = quantity > 0.5

        return HStack(spacing: 8) {
            Button {
                onChange(itemOffset, max(0.5, quantity - 0.5))
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(.systemGray6)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canDecrease ? .primary : .tertiary)
            .disabled(!canDecrease)
            .accessibilityLabel(Text("Decrease serving by 0.5"))

            Text(formatQuantity(quantity))
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 34)

            Button {
                onChange(itemOffset, quantity + 0.5)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(kDrawerPurple.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(kDrawerPurple)
            .accessibilityLabel(Text("Increase serving by 0.5"))
        }
    }

    private func quantityLabel(for item: ParsedFoodItem) -> String {
        "\(formatQuantity(item.amount ?? item.quantity)) \(item.unitNormalized ?? item.unit)"
    }

    private func formatQuantity(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }

    private func formatMacro(_ value: Double) -> String {
        "\(formatQuantity(value))g"
    }

}

struct LoggingResultThoughtProcessCard: View {
    let thoughtProcess: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How Food App Estimated This")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Text(thoughtProcess)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}
