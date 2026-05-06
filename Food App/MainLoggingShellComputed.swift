import SwiftUI
import Foundation

extension MainLoggingShellView {
    var bottomActionDock: some View {
        MainLoggingBottomDock(
            shouldShowSyncExceptionPill: shouldShowSyncExceptionPill,
            syncStatusTitle: syncStatusTitle,
            syncStatusExplanation: syncStatusExplanation,
            currentFoodLogStreak: currentFoodLogStreak,
            isLoadingFoodLogStreak: isLoadingFoodLogStreak,
            isKeyboardVisible: isKeyboardVisible,
            isSyncInfoPresented: $isSyncInfoPresented,
            isStreakDrawerPresented: $isStreakDrawerPresented
        )
    }

    var pendingSyncItemCount: Int {
        let unresolvedQueueItems = unresolvedPendingQueueItems
        var pendingKeys = Set(unresolvedQueueItems.map { pendingSyncKey(for: $0) })
        pendingKeys.formUnion(pendingPatchTasks.keys.map { "patch:\($0.uuidString)" })
        pendingKeys.formUnion(pendingDeleteTasks.keys.map { "delete:\($0.uuidString)" })

        let unsavedVisibleRows = saveError == nil ? inputRows.filter { row in
            guard !row.isSaved else { return false }
            guard !pendingKeys.contains("row:\(row.id.uuidString)") else { return false }
            return row.calories != nil || !row.parsedItems.isEmpty || row.parsedItem != nil
        } : []
        pendingKeys.formUnion(unsavedVisibleRows.map { "row:\($0.id.uuidString)" })
        return pendingKeys.count
    }

    var shouldShowSyncExceptionPill: Bool {
        saveError != nil && pendingSyncItemCount > 0
    }

    var syncStatusTitle: String {
        pendingSyncItemCount == 1 ? "1 item waiting" : "\(pendingSyncItemCount) items waiting"
    }

    var syncStatusExplanation: String {
        "These items are visible here and included in your calories. Sync is retrying in the background."
    }

    var topHeaderStrip: some View {
        MainLoggingTopHeaderStrip(
            firstName: loggedInFirstName,
            dateTitle: todayPillTitle,
            colorScheme: colorScheme,
            isProfilePresented: $isProfilePresented,
            isCalendarPresented: $isCalendarPresented
        )
    }

    var todayPillTitle: String {
        if Calendar.current.isDateInToday(selectedSummaryDate) {
            return "Today"
        }
        return HomeLoggingDateUtils.topDateFormatter.string(from: selectedSummaryDate)
    }

    var loggedInFirstName: String? {
        appStore.authSessionStore.session?.displayFirstName
    }

    var isParsing: Bool {
        parseInFlightCount > 0
    }

    var hasActiveParseRequest: Bool {
        inFlightParseSnapshot != nil
    }

    var hasDirtyRowsPendingParse: Bool {
        !orderedDirtyRowIDsForCurrentInput().isEmpty
    }

    /// The scrollable food rows + status strip. The title "What did you eat today?"
    /// is rendered separately in the body so it stays pinned during day-swipe animations.
    var composeEntryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputSection

            homeStatusStrip
                .padding(.top, 8)
        }
    }

    var nutritionSummarySheet: some View {
        MainLoggingNutritionSummarySheet(
            totals: visibleNutritionTotals,
            navigationTitle: summaryDateString == HomeLoggingDateUtils.summaryRequestFormatter.string(from: Date()) ? "Today" : summaryDateString
        )
    }

    var visibleNutritionTotals: NutritionTotals {
        .visible(from: inputRows)
    }

    var inputSection: some View {
        HM01LogComposerSection(
            rows: $inputRows,
            focusBinding: $isNoteEditorFocused,
            mode: inputMode,
            inlineEstimateText: nil,
            hasActiveParseRequest: hasActiveParseRequest,
            minimalStyle: true,
            onInputTapped: {
                inputMode = .text
            },
            onCaloriesTapped: { row in
                presentRowDetails(for: row)
            },
            onFocusedRowChanged: { rowID in
                activeEditingRowID = rowID
            },
            onServerBackedRowCleared: { row in
                handleServerBackedRowCleared(row)
            },
            onQuantityFastPathUpdated: { rowID in
                handleQuantityFastPathUpdate(rowID: rowID)
            }
        )
    }

    var noteText: String {
        // Only consider active (unsaved) rows for parsing — saved rows are read-only history
        inputRows.filter { !$0.isSaved }.map(\.text).joined(separator: "\n")
    }

    var trimmedNoteText: String {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var parseCandidateRows: [String] {
        let normalized = inputRows.filter { !$0.isSaved }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var end = normalized.count
        while end > 0, normalized[end - 1].isEmpty {
            end -= 1
        }
        return Array(normalized.prefix(end))
    }

    var rowTextSignature: String {
        parseCandidateRows.joined(separator: "\u{001F}")
    }

    var displayedTotals: NutritionTotals {
        if editableItems.isEmpty {
            return parseResult?.totals ?? NutritionTotals(calories: 0, protein: 0, carbs: 0, fat: 0)
        }

        let calories = editableItems.reduce(0.0) { $0 + $1.calories }
        let protein = editableItems.reduce(0.0) { $0 + $1.protein }
        let carbs = editableItems.reduce(0.0) { $0 + $1.carbs }
        let fat = editableItems.reduce(0.0) { $0 + $1.fat }
        return NutritionTotals(
            calories: HomeLoggingDisplayText.roundOneDecimal(calories),
            protein: HomeLoggingDisplayText.roundOneDecimal(protein),
            carbs: HomeLoggingDisplayText.roundOneDecimal(carbs),
            fat: HomeLoggingDisplayText.roundOneDecimal(fat)
        )
    }

    enum SaveIntent {
        case manual
        case retry
        case auto
        case dateChangeBackground
    }

    struct SaveSubmissionResult {
        let didSucceed: Bool
        let savedDay: String?
    }

    struct DateChangeDraftRow {
        let rowID: UUID
        let text: String
        let loggedAt: String
        let inputKind: String
    }

    struct PreservedDateDraftRow {
        var row: HomeLogRow
        var isBackgroundManaged: Bool
    }

    var hasSaveableRowsPending: Bool {
        activeParseSnapshots.contains(where: { isAutoSaveEligibleEntry($0) }) ||
            hasQueuedPendingSaves
    }

    var hasQueuedPendingSaves: Bool {
        pendingSaveQueue.contains { item in
            item.serverLogId == nil && UUID(uuidString: item.idempotencyKey) != nil
        }
    }

    var hasVisibleUnsavedCalorieRows: Bool {
        inputRows.contains { row in
            !row.isSaved && row.calories != nil
        }
    }

}
