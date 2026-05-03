import SwiftUI
import UIKit

struct MainLoggingCalendarSheet: View {
    @Binding var selectedDate: Date
    let onToday: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Select Date")
                    .font(.headline)
                Spacer()
                Button("Today", action: onToday)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal)
            .padding(.top, 16)

            DatePicker(
                "",
                selection: $selectedDate,
                in: ...Calendar.current.startOfDay(for: Date()),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(.horizontal)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct MainLoggingDetailsDrawer: View {
    let isManualAdd: Bool
    let parseResult: ParseLogResponse?
    let totals: NutritionTotals
    let items: [ParsedFoodItem]
    let onManualAddBackToText: () -> Void
    let onItemQuantityChange: (Int, Double) -> Void
    let onRecalculate: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isManualAdd {
                    MainLoggingManualAddDrawerContent(onBackToText: onManualAddBackToText)
                        .padding()
                } else if let parseResult {
                    drawerEyebrow

                    LoggingResultDrawerBody(
                        foodName: MainLoggingDrawerDisplayText.foodName(from: parseResult),
                        totals: totals,
                        items: items,
                        thoughtProcess: MainLoggingDrawerDisplayText.thoughtProcess(for: parseResult),
                        onItemQuantityChange: onItemQuantityChange,
                        onRecalculate: onRecalculate
                    )
                    .padding(.bottom, 44)
                } else {
                    Text(L10n.parseFirstHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var drawerEyebrow: some View {
        Text("Food App Result")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 20)
            .padding(.top, 22)
    }
}

struct MainLoggingManualAddDrawerContent: View {
    let onBackToText: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Manual Add Options")
                .font(.headline)
            Text("Pick a manual path to keep logging when auto-parse is not ideal.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Add custom food item") { }
                .buttonStyle(.bordered)
            Button("Add from recent foods") { }
                .buttonStyle(.bordered)
            Button("Back to text mode", action: onBackToText)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct MainLoggingRowCalorieDetailsSheet: View {
    let details: RowCalorieDetails
    let isDeleteDisabled: Bool
    @Binding var isDeleteConfirmationPresented: Bool
    let onDeleteTapped: () -> Void
    let onConfirmDelete: () -> Void
    let onCancelDelete: () -> Void
    let onDone: () -> Void
    let onItemQuantityChange: (Int, Double) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerMedia

                    LoggingResultDrawerBody(
                        foodName: details.displayName,
                        totals: totals,
                        items: details.parsedItems,
                        thoughtProcess: details.thoughtProcess,
                        onItemQuantityChange: onItemQuantityChange,
                        onRecalculate: nil
                    )
                    .padding(.bottom, 44)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Delete", role: .destructive, action: onDeleteTapped)
                        .tint(.red)
                        .disabled(isDeleteDisabled)
                        .accessibilityHint(Text("Deletes this food entry and updates your totals."))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.doneButton, action: onDone)
                }
            }
        }
        .alert("How sure are you that you want to delete this entry?", isPresented: $isDeleteConfirmationPresented) {
            Button("Delete", role: .destructive, action: onConfirmDelete)
            Button("Cancel", role: .cancel, action: onCancelDelete)
        } message: {
            Text("This removes the food from your log, updates your calories, and deletes the database row when it has already synced.")
        }
        .presentationDetents([.fraction(0.62), .large])
        .presentationDragIndicator(.visible)
    }

    private var totals: NutritionTotals {
        NutritionTotals(
            calories: Double(details.calories),
            protein: details.protein ?? 0,
            carbs: details.carbs ?? 0,
            fat: details.fat ?? 0
        )
    }

    @ViewBuilder
    private var headerMedia: some View {
        if let imageData = details.imagePreviewData,
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 224)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 16)
        } else {
            Text("Food App Result")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 20)
                .padding(.top, 22)
        }
    }
}

enum MainLoggingDrawerDisplayText {
    static func foodName(from result: ParseLogResponse) -> String {
        let names = result.items.prefix(3).map(\.name)
        if names.isEmpty { return "Food" }
        if names.count == 1 { return names[0] }
        if names.count == 2 { return "\(names[0]) & \(names[1])" }
        return "\(names[0]), \(names[1]) & more"
    }

    static func thoughtProcess(for result: ParseLogResponse) -> String {
        let sourceLabel = HomeLoggingDisplayText.sourceLabelForRowItems(
            result.items, route: result.route, routeDisplayName: nil
        )
        let isApprox = result.confidence < 0.85 || result.needsClarification

        if result.items.count > 1 {
            let names = result.items.prefix(3).map(\.name)
            let preview = names.count <= 2
                ? names.joined(separator: " & ")
                : "\(names[0]), \(names[1]) & more"
            let total = Int(result.totals.calories.rounded())
            var text = "Interpreted as \(result.items.count) items: \(preview). Used \(sourceLabel) to estimate \(total) kcal total."
            if isApprox { text += " Result is marked approximate." }
            return text
        }

        if let item = result.items.first {
            if let explanation = item.explanation,
               !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return explanation
            }
            let qty = HomeLoggingDisplayText.formatOneDecimal(item.quantity)
            var text = "Interpreted as \"\(item.name)\". Used \(qty) \(item.unit) with \(sourceLabel) to estimate \(Int(item.calories.rounded())) kcal."
            if isApprox { text += " Result is marked approximate." }
            return text
        }

        return "A calorie estimate is available but no matched item was retained. Re-parse to refine."
    }
}
