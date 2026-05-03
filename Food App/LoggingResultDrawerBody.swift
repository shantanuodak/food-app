import SwiftUI
import Foundation

private let kDrawerPurple = Color(red: 0.420, green: 0.369, blue: 1.0)

/// Shared result body used by both the camera drawer (CameraResultDrawerView)
/// and the text-entry drawer (detailsDrawer in MainLoggingShellView).
/// Callers place whatever appears above this (hero image or eyebrow label),
/// and whatever appears below (CTAs or nothing for auto-saved text flow).
struct LoggingResultDrawerBody: View {
    let foodName: String
    let totals: NutritionTotals
    let items: [ParsedFoodItem]
    let thoughtProcess: String
    let onItemQuantityChange: ((Int, Double) -> Void)?
    let onRecalculate: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            foodNameView
            calorieHero
            Divider()
                .padding(.horizontal, 20)
                .padding(.top, 16)
            macroCards
            if !items.isEmpty {
                Divider()
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                detectedItemsList
            }
            thoughtProcessCard
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
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .padding(.horizontal, 20)
            .padding(.top, 6)
    }

    // MARK: - Calorie hero — Large Title

    private var calorieHero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.671, blue: 0), Color(red: 1, green: 0.333, blue: 0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            Text("\(Int(totals.calories.rounded()))")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.primary)
            Text("cal")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Macro cards

    private var macroCards: some View {
        HStack(spacing: 8) {
            drawerMacroCard(
                icon: "bolt.fill",
                value: "\(Int(totals.protein.rounded()))g",
                label: "Protein",
                iconColor: kDrawerPurple,
                bgColor: kDrawerPurple.opacity(0.10)
            )
            drawerMacroCard(
                icon: "leaf.fill",
                value: "\(Int(totals.carbs.rounded()))g",
                label: "Carbs",
                iconColor: .green,
                bgColor: Color.green.opacity(0.10)
            )
            drawerMacroCard(
                icon: "drop.fill",
                value: "\(Int(totals.fat.rounded()))g",
                label: "Fat",
                iconColor: .blue,
                bgColor: Color.blue.opacity(0.10)
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func drawerMacroCard(
        icon: String,
        value: String,
        label: String,
        iconColor: Color,
        bgColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(bgColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Detected items

    private var detectedItemsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Detected items")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
                .padding(.top, 16)
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Text(quantityLabel(for: item))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                if let onItemQuantityChange {
                    quantityStepper(item: item, itemOffset: itemOffset, onChange: onItemQuantityChange)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 5) {
                Text("\(Int(item.calories.rounded())) cal")
                    .font(.system(size: 15, weight: .semibold))
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
        .frame(minHeight: 96)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
        )
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

    // MARK: - Thought process card

    private var thoughtProcessCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Food App Thought Process")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text(thoughtProcess)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}
