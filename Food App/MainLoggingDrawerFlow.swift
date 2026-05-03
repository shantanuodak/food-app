import SwiftUI

extension MainLoggingShellView {
    @ViewBuilder
    var detailsDrawer: some View {
        MainLoggingDetailsDrawer(
            isManualAdd: detailsDrawerMode == .manualAdd,
            parseResult: parseResult,
            totals: displayedTotals,
            items: displayedDrawerItems,
            onManualAddBackToText: {
                inputMode = .text
                detailsDrawerMode = .full
                isDetailsDrawerPresented = false
            },
            onItemQuantityChange: { itemOffset, quantity in
                applyActiveParseItemQuantity(itemOffset: itemOffset, quantity: quantity)
            },
            onRecalculate: {
                isDetailsDrawerPresented = false
                triggerParseNow()
            }
        )
    }

    @ViewBuilder
    func rowCalorieDetailsSheet(_ details: RowCalorieDetails) -> some View {
        let liveDetails = liveRowCalorieDetails(for: details.id, fallback: details)
        MainLoggingRowCalorieDetailsSheet(
            details: liveDetails,
            isDeleteDisabled: isRowDetailsDeleteDisabled(rowID: liveDetails.id),
            isDeleteConfirmationPresented: $isRowDetailsDeleteConfirmationPresented,
            onDeleteTapped: {
                rowDetailsPendingDeleteID = liveDetails.id
                isRowDetailsDeleteConfirmationPresented = true
            },
            onConfirmDelete: {
                if let rowID = rowDetailsPendingDeleteID {
                    confirmRowDetailsDelete(rowID: rowID)
                }
                rowDetailsPendingDeleteID = nil
            },
            onCancelDelete: {
                rowDetailsPendingDeleteID = nil
            },
            onDone: {
                selectedRowDetails = nil
            },
            onItemQuantityChange: { itemOffset, quantity in
                applyRowItemQuantity(
                    rowID: liveDetails.id,
                    itemOffset: itemOffset,
                    quantity: quantity
                )
            }
        )
    }

    @ViewBuilder
    var homeStatusStrip: some View {
        MainLoggingHomeStatusStrip(
            saveSuccessMessage: saveSuccessMessage,
            parseError: parseError,
            parseInfoMessage: parseInfoMessage,
            inputModeStatusMessage: inputModeStatusMessage,
            shouldShowRetryParseButton: shouldShowRetryParseButton,
            onRetryParse: triggerParseNow
        )
    }

    var shouldShowRetryParseButton: Bool {
        guard !isParsing else { return false }
        guard appStore.isNetworkReachable else { return false }
        guard !trimmedNoteText.isEmpty else { return false }
        if parseError != nil {
            return true
        }
        return parseInfoMessage == L10n.parseStillProcessingLabel
    }

    var inputModeStatusMessage: String? {
        switch inputMode {
        case .text:
            return nil
        case .voice:
            return "Voice capture is in progress. You can continue with text right now."
        case .camera:
            if let selectedCameraSource {
                return selectedCameraSource.statusMessage
            }
            return nil
        case .manualAdd:
            return "Manual add tools are open in Details."
        }
    }

    func presentRowDetails(for row: HomeLogRow) {
        guard let details = makeRowCalorieDetails(for: row) else { return }
        selectedRowDetails = details
    }

    func liveRowCalorieDetails(for rowID: UUID, fallback: RowCalorieDetails) -> RowCalorieDetails {
        guard let row = inputRows.first(where: { $0.id == rowID }),
              let refreshed = makeRowCalorieDetails(for: row) else {
            return fallback
        }
        return refreshed
    }

    func isRowDetailsDeleteDisabled(rowID: UUID) -> Bool {
        guard let row = inputRows.first(where: { $0.id == rowID }) else { return true }
        return row.isDeleting || pendingDeleteTasks[rowID] != nil
    }

    func confirmRowDetailsDelete(rowID: UUID) {
        guard let row = inputRows.first(where: { $0.id == rowID }) else {
            selectedRowDetails = nil
            return
        }

        selectedRowDetails = nil
        rowDetailsPendingDeleteID = nil

        if serverBackedDeleteContext(for: row) != nil {
            handleServerBackedRowCleared(row)
        } else {
            removeLocalRowFromDetails(rowID: rowID)
        }
    }

    func removeLocalRowFromDetails(rowID: UUID) {
        clearTransientWorkForDeletedRow(rowID: rowID)
        locallyDeletedPendingRowIDs.insert(rowID)
        let removedKeys = removePendingSaveQueueItems(forRowID: rowID)
        locallyDeletedPendingSaveKeys.formUnion(removedKeys)

        if let index = inputRows.firstIndex(where: { $0.id == rowID }) {
            withAnimation(.easeOut(duration: 0.14)) {
                inputRows.remove(at: index)
                if inputRows.isEmpty || inputRows.allSatisfy({ $0.isSaved }) {
                    inputRows.append(.empty())
                }
            }
        }

        if hasSaveableRowsPending {
            scheduleAutoSave()
        } else {
            cancelAutoSaveTask()
        }
    }

    func makeRowCalorieDetails(for row: HomeLogRow) -> RowCalorieDetails? {
        guard let calories = row.calories else { return nil }
        guard let rowIndex = inputRows.firstIndex(where: { $0.id == row.id }) else { return nil }

        let resolvedItems = resolvedItems(for: row)
        let overridePreview = manualOverridePreview(for: row, rowIndex: rowIndex)
        let parseConfidence = parseResult?.confidence ?? 0
        let itemConfidenceValues = resolvedItems.map(\.matchConfidence).filter { $0.isFinite }
        let itemConfidence = itemConfidenceValues.isEmpty
            ? nil
            : itemConfidenceValues.reduce(0, +) / Double(itemConfidenceValues.count)
        let primaryConfidence = itemConfidence ?? parseConfidence
        let route = parseResult?.route
        let routeDisplayName = route.map { L10n.routeDisplayName($0) }
        let sourceLabel = HomeLoggingDisplayText.sourceLabelForRowItems(
            resolvedItems,
            route: route,
            routeDisplayName: routeDisplayName
        )
        let hasManualOverride = resolvedItems.contains {
            ($0.manualOverride ?? false) || ($0.sourceFamily?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "manual")
        }
        let aggregatedProtein = resolvedItems.isEmpty ? nil : resolvedItems.reduce(0) { $0 + $1.protein }
        let aggregatedCarbs = resolvedItems.isEmpty ? nil : resolvedItems.reduce(0) { $0 + $1.carbs }
        let aggregatedFat = resolvedItems.isEmpty ? nil : resolvedItems.reduce(0) { $0 + $1.fat }
        let displayName: String
        if resolvedItems.count > 1 {
            let trimmed = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            displayName = trimmed.isEmpty ? "\(resolvedItems.count) items" : trimmed
        } else {
            displayName = resolvedItems.first?.name ?? row.text
        }
        return RowCalorieDetails(
            id: row.id,
            rowText: row.text,
            displayName: displayName,
            calories: calories,
            protein: aggregatedProtein,
            carbs: aggregatedCarbs,
            fat: aggregatedFat,
            parseConfidence: parseConfidence,
            itemConfidence: itemConfidence,
            primaryConfidence: min(max(primaryConfidence, 0), 1),
            hasManualOverride: hasManualOverride,
            sourceLabel: sourceLabel,
            thoughtProcess: HomeLoggingDisplayText.thoughtProcessText(
                for: row,
                sourceLabel: sourceLabel,
                items: resolvedItems,
                needsClarification: parseResult?.needsClarification == true
            ),
            parsedItems: resolvedItems,
            manualEditedFields: overridePreview.editedFields,
            manualOriginalSources: overridePreview.originalSources,
            imagePreviewData: row.imagePreviewData,
            imageRef: row.imageRef
        )
    }

    func manualOverridePreview(for row: HomeLogRow, rowIndex: Int) -> (editedFields: [String], originalSources: [String]) {
        var editedFieldSet: Set<String> = []
        var originalSourceSet: Set<String> = []
        let fallbackMap: [String: String] = [
            "name": "name",
            "quantity": "quantity",
            "unit": "unit",
            "calories": "calories",
            "protein": "protein",
            "carbs": "carbs",
            "fat": "fat",
            "nutritionSourceId": "source"
        ]

        for (itemOffset, item) in row.parsedItems.enumerated() {
            if let editableIndex = editableIndexForRowItem(rowIndex: rowIndex, itemOffset: itemOffset),
               editableItems.indices.contains(editableIndex) {
                let manualOverride = editableItems[editableIndex].asSaveParsedFoodItem().manualOverride
                for field in manualOverride?.editedFields ?? [] {
                    let label = fallbackMap[field] ?? field
                    editedFieldSet.insert(label)
                }
            } else if item.manualOverride == true || HomeLoggingDisplayText.normalizedLookupValue(item.sourceFamily ?? "") == "manual" {
                editedFieldSet.insert("nutrition")
            }

            let originalSourceID = (item.originalNutritionSourceId ?? item.nutritionSourceId)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !originalSourceID.isEmpty {
                originalSourceSet.insert(HomeLoggingDisplayText.sourceReferenceLabel(for: originalSourceID))
            }
        }

        return (
            editedFields: Array(editedFieldSet).sorted(),
            originalSources: Array(originalSourceSet).sorted()
        )
    }

    func resolvedItems(for row: HomeLogRow) -> [ParsedFoodItem] {
        if !row.parsedItems.isEmpty {
            return row.parsedItems
        }
        if let parsedItem = row.parsedItem {
            return [parsedItem]
        }
        return []
    }

    var displayedDrawerItems: [ParsedFoodItem] {
        if editableItems.isEmpty {
            return parseResult?.items ?? []
        }
        return editableItems.map { $0.asParsedFoodItem() }
    }

    @MainActor
    func applyActiveParseItemQuantity(itemOffset: Int, quantity: Double) {
        if editableItems.isEmpty, let items = parseResult?.items, items.indices.contains(itemOffset) {
            editableItems = items.map(EditableParsedItem.init(apiItem:))
        }
        guard editableItems.indices.contains(itemOffset) else { return }
        editableItems[itemOffset].updateQuantity(quantity)
        scheduleAutoSave()
    }

    @MainActor
    func applyRowItemQuantity(rowID: UUID, itemOffset: Int, quantity: Double) {
        guard let rowIndex = inputRows.firstIndex(where: { $0.id == rowID }) else { return }
        guard inputRows[rowIndex].parsedItems.indices.contains(itemOffset) else { return }
        applyRowParsedItemEdit(rowIndex: rowIndex, itemOffset: itemOffset) { editable in
            editable.updateQuantity(quantity)
        }
        handleQuantityFastPathUpdate(rowID: rowID)
    }

    func applyRowParsedItemEdit(
        rowIndex: Int,
        itemOffset: Int,
        mutate: (inout EditableParsedItem) -> Void
    ) {
        guard inputRows.indices.contains(rowIndex) else { return }
        guard inputRows[rowIndex].parsedItems.indices.contains(itemOffset) else { return }

        let currentItem = inputRows[rowIndex].parsedItems[itemOffset]
        let editableIndex = editableIndexForRowItem(rowIndex: rowIndex, itemOffset: itemOffset)

        var workingEditable: EditableParsedItem
        if let editableIndex, editableItems.indices.contains(editableIndex) {
            workingEditable = editableItems[editableIndex]
        } else {
            workingEditable = EditableParsedItem(apiItem: currentItem)
        }

        mutate(&workingEditable)
        let updatedItem = workingEditable.asParsedFoodItem()

        inputRows[rowIndex].parsedItems[itemOffset] = updatedItem
        inputRows[rowIndex].parsedItem = inputRows[rowIndex].parsedItems.first

        if let editableIndex, editableItems.indices.contains(editableIndex) {
            editableItems[editableIndex] = workingEditable
        } else {
            let newIndex = editableItems.count
            editableItems.append(workingEditable)
            if inputRows[rowIndex].editableItemIndices.count <= itemOffset {
                inputRows[rowIndex].editableItemIndices += Array(
                    repeating: newIndex,
                    count: itemOffset - inputRows[rowIndex].editableItemIndices.count + 1
                )
            } else {
                inputRows[rowIndex].editableItemIndices[itemOffset] = newIndex
            }
        }

        recalculateRowNutrition(rowIndex: rowIndex)
    }

    func editableIndexForRowItem(rowIndex: Int, itemOffset: Int) -> Int? {
        guard inputRows.indices.contains(rowIndex) else { return nil }
        guard inputRows[rowIndex].parsedItems.indices.contains(itemOffset) else { return nil }

        let mappedIndices = inputRows[rowIndex].editableItemIndices
        if mappedIndices.indices.contains(itemOffset) {
            let mappedIndex = mappedIndices[itemOffset]
            if editableItems.indices.contains(mappedIndex) {
                return mappedIndex
            }
        }

        let rowItem = inputRows[rowIndex].parsedItems[itemOffset]
        let normalizedSource = HomeLoggingDisplayText.normalizedLookupValue(rowItem.nutritionSourceId)
        let normalizedName = HomeLoggingDisplayText.normalizedLookupValue(rowItem.name)

        if let exact = editableItems.firstIndex(where: { item in
            HomeLoggingDisplayText.normalizedLookupValue(item.nutritionSourceId) == normalizedSource &&
                HomeLoggingDisplayText.normalizedLookupValue(item.name) == normalizedName
        }) {
            return exact
        }

        if let bySource = editableItems.firstIndex(where: {
            HomeLoggingDisplayText.normalizedLookupValue($0.nutritionSourceId) == normalizedSource
        }) {
            return bySource
        }

        if let byName = editableItems.firstIndex(where: {
            HomeLoggingDisplayText.normalizedLookupValue($0.name) == normalizedName
        }) {
            return byName
        }

        return nil
    }

    func recalculateRowNutrition(rowIndex: Int) {
        guard inputRows.indices.contains(rowIndex) else { return }
        let rowItems = inputRows[rowIndex].parsedItems
        guard !rowItems.isEmpty else { return }

        let calories = Int(max(0, rowItems.reduce(0) { $0 + $1.calories }).rounded())
        inputRows[rowIndex].calories = calories
        inputRows[rowIndex].calorieRangeText = inputRows[rowIndex].isApproximate
            ? estimatedCalorieRangeText(for: calories)
            : nil
    }

}
