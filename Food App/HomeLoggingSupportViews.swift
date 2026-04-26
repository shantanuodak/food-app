import SwiftUI
import Foundation
import UIKit

struct PendingSaveDraft: Codable {
    let request: SaveLogRequest
    let fingerprint: String
    let idempotencyKey: String
}

struct InFlightParseSnapshot {
    let text: String
    let requestSequence: Int
    let activeRowID: UUID
    let dirtyRowIDsAtDispatch: [UUID]
}

struct RowCalorieDetails: Identifiable {
    let id: UUID
    let rowText: String
    let displayName: String
    let calories: Int
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let parseConfidence: Double
    let itemConfidence: Double?
    let primaryConfidence: Double
    let hasManualOverride: Bool
    let sourceLabel: String
    let thoughtProcess: String
    let parsedItems: [ParsedFoodItem]
    let manualEditedFields: [String]
    let manualOriginalSources: [String]
    let imagePreviewData: Data?
    let imageRef: String?
}

struct PreparedImagePayload {
    let uploadData: Data
    let previewData: Data
    let mimeType: String
}

struct HomeImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: HomeImagePicker

        init(parent: HomeImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.originalImage] as? UIImage) ?? (info[.editedImage] as? UIImage)
            parent.dismiss()
            if let image {
                parent.onImagePicked(image)
            } else {
                parent.onCancel()
            }
        }
    }
}

/// Applies the swipe offset/opacity as a single GPU-composited layer.
/// Without this, every frame of the swipe gesture forces SwiftUI to re-layout
/// the entire child tree. `drawingGroup()` flattens it to a Metal texture first.
struct DaySwipeOffsetModifier: ViewModifier, Animatable {
    var offset: CGFloat

    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(1.0 - min(abs(offset) / 200, 0.4))
    }
}

struct LiquidGlassCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct EditableParsedItem: Identifiable {
    let id = UUID()

    var name: String
    var quantity: Double
    var unit: String
    var grams: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var nutritionSourceId: String
    var originalNutritionSourceId: String?
    var sourceFamily: String?
    var matchConfidence: Double
    var servingOptions: [ParsedServingOption]?
    var foodDescription: String?
    var explanation: String?

    private var gramsPerUnit: Double
    private var caloriesPerUnit: Double
    private var proteinPerUnit: Double
    private var carbsPerUnit: Double
    private var fatPerUnit: Double
    private let originalName: String
    private let originalQuantity: Double
    private let originalUnit: String
    private let originalCalories: Double
    private let originalProtein: Double
    private let originalCarbs: Double
    private let originalFat: Double
    private let originalNutritionSourceIdSnapshot: String

    init(apiItem: ParsedFoodItem) {
        let quantityBasis = apiItem.amount ?? apiItem.quantity
        let safeQuantity = max(quantityBasis, 0.0001)
        name = apiItem.name
        quantity = quantityBasis
        unit = apiItem.unitNormalized ?? apiItem.unit
        grams = apiItem.grams
        calories = apiItem.calories
        protein = apiItem.protein
        carbs = apiItem.carbs
        fat = apiItem.fat
        nutritionSourceId = apiItem.nutritionSourceId
        originalNutritionSourceId = apiItem.originalNutritionSourceId
        sourceFamily = apiItem.sourceFamily
        matchConfidence = apiItem.matchConfidence
        servingOptions = apiItem.servingOptions
        foodDescription = apiItem.foodDescription
        explanation = apiItem.explanation

        gramsPerUnit = apiItem.gramsPerUnit ?? (apiItem.grams / safeQuantity)
        caloriesPerUnit = apiItem.calories / safeQuantity
        proteinPerUnit = apiItem.protein / safeQuantity
        carbsPerUnit = apiItem.carbs / safeQuantity
        fatPerUnit = apiItem.fat / safeQuantity

        originalName = apiItem.name.trimmingCharacters(in: .whitespacesAndNewlines)
        originalQuantity = quantityBasis
        originalUnit = (apiItem.unitNormalized ?? apiItem.unit).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        originalCalories = apiItem.calories
        originalProtein = apiItem.protein
        originalCarbs = apiItem.carbs
        originalFat = apiItem.fat
        originalNutritionSourceIdSnapshot = apiItem.originalNutritionSourceId ?? apiItem.nutritionSourceId
    }

    mutating func updateQuantity(_ newQuantity: Double) {
        let bounded = max(newQuantity, 0)
        quantity = bounded
        grams = Self.roundOneDecimal(gramsPerUnit * bounded)
        calories = Self.roundOneDecimal(caloriesPerUnit * bounded)
        protein = Self.roundOneDecimal(proteinPerUnit * bounded)
        carbs = Self.roundOneDecimal(carbsPerUnit * bounded)
        fat = Self.roundOneDecimal(fatPerUnit * bounded)
    }

    mutating func applyServingOption(_ option: ParsedServingOption) {
        let usesServingBasis = optionUsesServingBasis(option)
        let baseQuantity = usesServingBasis ? 1.0 : max(option.quantity, 0.0001)
        let resolvedUnit = option.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolvedUnit.isEmpty {
            if usesServingBasis || isWeightOrVolumeUnit(resolvedUnit) {
                unit = "serving"
            } else {
                unit = resolvedUnit
            }
        }

        if usesServingBasis {
            gramsPerUnit = option.grams
            caloriesPerUnit = option.calories
            proteinPerUnit = option.protein
            carbsPerUnit = option.carbs
            fatPerUnit = option.fat
        } else {
            gramsPerUnit = option.grams / baseQuantity
            caloriesPerUnit = option.calories / baseQuantity
            proteinPerUnit = option.protein / baseQuantity
            carbsPerUnit = option.carbs / baseQuantity
            fatPerUnit = option.fat / baseQuantity
        }

        let sourceId = option.nutritionSourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceId.isEmpty {
            nutritionSourceId = sourceId
        }

        updateQuantity(quantity)
    }

    private func optionUsesServingBasis(_ option: ParsedServingOption) -> Bool {
        if abs(option.quantity - 1) > 0.0001 {
            return true
        }
        return isWeightOrVolumeUnit(option.unit)
    }

    private func isWeightOrVolumeUnit(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "g" || normalized == "gram" || normalized == "grams" ||
            normalized == "ml" || normalized == "milliliter" || normalized == "milliliters" ||
            normalized == "oz" || normalized == "ounce" || normalized == "ounces"
    }

    func asParsedFoodItem() -> ParsedFoodItem {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = normalizedName.isEmpty ? "item" : normalizedName
        let normalizedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedUnit = normalizedUnit.isEmpty ? "count" : normalizedUnit
        let editedFields = manualEditedFields(
            currentName: resolvedName,
            currentQuantity: quantity,
            currentUnit: resolvedUnit,
            currentCalories: calories,
            currentProtein: protein,
            currentCarbs: carbs,
            currentFat: fat,
            currentSource: nutritionSourceId
        )

        return ParsedFoodItem(
            name: resolvedName,
            quantity: quantity,
            unit: resolvedUnit,
            grams: grams,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            nutritionSourceId: nutritionSourceId,
            originalNutritionSourceId: originalNutritionSourceId ?? originalNutritionSourceIdSnapshot,
            sourceFamily: editedFields.isEmpty ? sourceFamily : "manual",
            matchConfidence: matchConfidence,
            amount: quantity,
            unitNormalized: resolvedUnit,
            gramsPerUnit: quantity > 0 ? (grams / quantity) : nil,
            needsClarification: false,
            manualOverride: editedFields.isEmpty ? nil : true,
            servingOptions: servingOptions,
            foodDescription: foodDescription,
            explanation: explanation
        )
    }

    func asSaveParsedFoodItem() -> SaveParsedFoodItem {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = normalizedName.isEmpty ? "item" : normalizedName
        let normalizedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedUnit = normalizedUnit.isEmpty ? "count" : normalizedUnit
        let editedFields = manualEditedFields(
            currentName: resolvedName,
            currentQuantity: quantity,
            currentUnit: resolvedUnit,
            currentCalories: calories,
            currentProtein: protein,
            currentCarbs: carbs,
            currentFat: fat,
            currentSource: nutritionSourceId
        )

        return SaveParsedFoodItem(
            name: resolvedName,
            quantity: quantity,
            amount: quantity,
            unit: resolvedUnit,
            unitNormalized: resolvedUnit,
            grams: grams,
            gramsPerUnit: quantity > 0 ? (grams / quantity) : nil,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            nutritionSourceId: nutritionSourceId,
            originalNutritionSourceId: originalNutritionSourceId ?? originalNutritionSourceIdSnapshot,
            sourceFamily: editedFields.isEmpty ? sourceFamily : "manual",
            matchConfidence: matchConfidence,
            needsClarification: false,
            manualOverride: editedFields.isEmpty
                ? nil
                : SaveManualOverride(
                    enabled: true,
                    reason: "Adjusted manually in app.",
                    editedFields: editedFields
                )
        )
    }

    private func manualEditedFields(
        currentName: String,
        currentQuantity: Double,
        currentUnit: String,
        currentCalories: Double,
        currentProtein: Double,
        currentCarbs: Double,
        currentFat: Double,
        currentSource: String
    ) -> [String] {
        var fields: [String] = []
        if currentName.lowercased() != originalName.lowercased() { fields.append("name") }
        if abs(currentQuantity - originalQuantity) > 0.0001 { fields.append("quantity") }
        if currentUnit != originalUnit { fields.append("unit") }
        if abs(currentCalories - originalCalories) > 0.05 { fields.append("calories") }
        if abs(currentProtein - originalProtein) > 0.05 { fields.append("protein") }
        if abs(currentCarbs - originalCarbs) > 0.05 { fields.append("carbs") }
        if abs(currentFat - originalFat) > 0.05 { fields.append("fat") }
        if currentSource != originalNutritionSourceIdSnapshot { fields.append("nutritionSourceId") }
        return fields
    }

    private static func roundOneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

