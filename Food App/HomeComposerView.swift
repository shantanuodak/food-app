import SwiftUI


struct HM01LogComposerSection: View {
    @Binding var rows: [HomeLogRow]
    let focusBinding: FocusState<Bool>.Binding
    let mode: HomeInputMode
    let inlineEstimateText: String?
    let hasActiveParseRequest: Bool
    let minimalStyle: Bool
    let onInputTapped: () -> Void
    let onCaloriesTapped: (HomeLogRow) -> Void
    let onFocusedRowChanged: (UUID?) -> Void
    let onServerBackedRowCleared: (HomeLogRow) -> Void
    /// Fires after the client-side quantity fast path rescales a row's items
    /// (e.g. "3 chicken tenders" → "4 chicken tenders"). The parent view uses
    /// this to schedule persistence: PATCH for rows that already have a
    /// `serverLogId`, or to kick the regular auto-save for newly-composed
    /// rows.
    let onQuantityFastPathUpdated: (UUID) -> Void
    @State private var focusedMinimalRowID: UUID?

    init(
        rows: Binding<[HomeLogRow]>,
        focusBinding: FocusState<Bool>.Binding,
        mode: HomeInputMode,
        inlineEstimateText: String?,
        hasActiveParseRequest: Bool = false,
        minimalStyle: Bool = false,
        onInputTapped: @escaping () -> Void,
        onCaloriesTapped: @escaping (HomeLogRow) -> Void = { _ in },
        onFocusedRowChanged: @escaping (UUID?) -> Void = { _ in },
        onServerBackedRowCleared: @escaping (HomeLogRow) -> Void = { _ in },
        onQuantityFastPathUpdated: @escaping (UUID) -> Void = { _ in }
    ) {
        _rows = rows
        self.focusBinding = focusBinding
        self.mode = mode
        self.inlineEstimateText = inlineEstimateText
        self.hasActiveParseRequest = hasActiveParseRequest
        self.minimalStyle = minimalStyle
        self.onInputTapped = onInputTapped
        self.onCaloriesTapped = onCaloriesTapped
        self.onFocusedRowChanged = onFocusedRowChanged
        self.onServerBackedRowCleared = onServerBackedRowCleared
        self.onQuantityFastPathUpdated = onQuantityFastPathUpdated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !minimalStyle {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(L10n.foodInputPrompt)
                        .font(.headline)

                    Spacer()

                    if let inlineEstimateText {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                            Text(inlineEstimateText)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            if mode != .text && !minimalStyle {
                Text("Mode: \(mode.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if minimalStyle {
                let firstActiveRowID = rows.first(where: { !$0.isSaved })?.id
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 12) {
                            if row.isSaved {
                                Button {
                                    guard !row.isDeleting else { return }
                                    if let index = indexForRowID(row.id) {
                                        rows[index].isSaved = false
                                        rows[index].savedAt = nil
                                        onInputTapped()
                                        setFocusedMinimalRowID(row.id)
                                    }
                                } label: {
                                    Text(homeRowTitle(for: row))
                                        .font(.system(size: 18))
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .disabled(row.isDeleting)
                                .modifier(InsertShimmerModifier(isActive: row.showInsertShimmer, onComplete: {
                                    if let index = indexForRowID(row.id) {
                                        rows[index].showInsertShimmer = false
                                    }
                                }))
                            } else {
                                let isFirst = row.id == firstActiveRowID
                                let placeholder = isFirst ? "Type your food here" : "Add another item"

                                MinimalRowTextEditor(
                                    text: bindingForRowText(row.id),
                                    isFocused: focusedMinimalRowID == row.id,
                                    onFocusChanged: { isFocused in
                                        DispatchQueue.main.async {
                                            guard indexForRowID(row.id) != nil else { return }
                                            if isFocused {
                                                onInputTapped()
                                                setFocusedMinimalRowID(row.id)
                                            } else if focusedMinimalRowID == row.id {
                                                setFocusedMinimalRowID(nil)
                                            }
                                        }
                                    },
                                    onSubmit: {
                                        addMinimalRow(after: row.id)
                                    },
                                    onDeleteBackwardWhenEmpty: {
                                        deleteCurrentEmptyRowAndFocusPrevious(rowID: row.id)
                                    },
                                    placeholder: placeholder,
                                    showTypewriterPlaceholder: isFirst
                                )
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                                .modifier(InsertShimmerModifier(isActive: row.showInsertShimmer, onComplete: {
                                    if let index = indexForRowID(row.id) {
                                        rows[index].showInsertShimmer = false
                                    }
                                }))
                                .accessibilityLabel(Text(L10n.foodInputPrompt))
                                .accessibilityHint(Text(L10n.foodInputHint))
                            }

                            trailingCaloriesView(for: row)
                                .frame(width: 150, alignment: .trailing)
                        }
                        .opacity(row.isDeleting ? 0.35 : 1)
                        .animation(.easeOut(duration: 0.12), value: row.isDeleting)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextEditor(text: rowTextBinding)
                    .focused(focusBinding)
                    .scrollDisabled(true)
                    .frame(minHeight: 160)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .accessibilityLabel(Text(L10n.foodInputPrompt))
                    .accessibilityHint(Text(L10n.foodInputHint))
                    .onTapGesture {
                        onInputTapped()
                        focusBinding.wrappedValue = true
                    }
            }
            if !minimalStyle {
                HStack(spacing: 0) {
                    RollingNumberText(
                        value: Double(joinedRowText.trimmingCharacters(in: .whitespacesAndNewlines).count),
                        fractionDigits: 0
                    )
                    Text("/500")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissKeyboardFromTabBar)) { _ in
            focusedMinimalRowID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusComposerInputFromBackgroundTap)) { _ in
            focusLastEditableRow()
        }
    }

    private var joinedRowText: String {
        rows.map(\.text).joined(separator: "\n")
    }

    private func homeRowTitle(for row: HomeLogRow) -> String {
        let trimmed = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let lowercased = trimmed.lowercased()
        let looksLikeOCR = trimmed.count > 80 ||
            lowercased.contains("nutrition facts") ||
            lowercased.contains("serving size") ||
            lowercased.contains("total carbohydrate") ||
            lowercased.contains("saturated fat")

        guard looksLikeOCR else { return trimmed }

        let items = row.parsedItems.isEmpty
            ? row.parsedItem.map { [$0] } ?? []
            : row.parsedItems

        guard !items.isEmpty else {
            return HomeLoggingDisplayText.shortenedFoodLabel(items: [], extractedText: trimmed)
        }

        return HomeLoggingDisplayText.shortenedFoodLabel(items: items, extractedText: trimmed)
    }

    private var rowTextBinding: Binding<String> {
        Binding(
            get: { joinedRowText },
            set: { newValue in
                rows = textToRows(newValue)
            }
        )
    }

    private func textToRows(_ value: String) -> [HomeLogRow] {
        let parts = value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let normalized = parts.isEmpty ? [""] : parts
        return normalized.map { part in
            HomeLogRow(
                id: UUID(),
                text: part,
                calories: nil,
                calorieRangeText: nil,
                isApproximate: false,
                parsePhase: .idle,
                parsedItem: nil,
                parsedItems: [],
                editableItemIndices: [],
                normalizedTextAtParse: nil,
                imagePreviewData: nil,
                imageRef: nil,
                isSaved: false,
                savedAt: nil
            )
        }
    }

    private func bindingForRowText(_ rowID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let index = indexForRowID(rowID), rows.indices.contains(index) else {
                    return ""
                }
                return rows[index].text
            },
            set: { newValue in
                guard let index = indexForRowID(rowID), rows.indices.contains(index) else {
                    return
                }
                guard rows[index].text != newValue else { return }

                let oldRow = rows[index]
                let oldText = oldRow.text
                let wasEmpty = oldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                rows[index].text = newValue
                let isEmpty = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                if isEmpty && !wasEmpty && oldRow.serverLogId != nil {
                    onServerBackedRowCleared(oldRow)
                    return
                }

                if isEmpty && !wasEmpty {
                    // Text just became empty — clear all parse state
                    rows[index].calories = nil
                    rows[index].calorieRangeText = nil
                    rows[index].isApproximate = false
                    rows[index].clearParsePhase()
                    rows[index].parsedItem = nil
                    rows[index].parsedItems = []
                    rows[index].editableItemIndices = []
                    rows[index].normalizedTextAtParse = nil
                    rows[index].imagePreviewData = nil
                    rows[index].imageRef = nil
                    return
                }

                // --- Quantity-only fast path ---------------------------------
                // If the row already has parsed items and the only change is
                // the leading quantity (e.g. "3 chicken tenders" → "4 chicken
                // tenders"), rescale calories/macros locally instead of
                // triggering a backend re-parse. Also updates
                // `normalizedTextAtParse` so `rowNeedsFreshParse()` returns
                // false for the new text, preventing the debounced parser
                // from undoing our work.
                if !isEmpty,
                   !wasEmpty,
                   !rows[index].parsedItems.isEmpty,
                   !rows[index].isLoading,
                   let edit = detectQuantityOnlyEdit(oldText: oldText, newText: newValue) {
                    let scaled = rows[index].parsedItems.map {
                        scaleParsedFoodItem($0, by: edit.multiplier)
                    }
                    rows[index].parsedItems = scaled
                    rows[index].parsedItem = scaled.first
                    if let existing = rows[index].calories {
                        let newCalories = Double(existing) * edit.multiplier
                        rows[index].calories = Int(newCalories.rounded())
                    } else if !scaled.isEmpty {
                        rows[index].calories = Int(
                            scaled.reduce(0.0) { $0 + $1.calories }.rounded()
                        )
                    }
                    // Mark as fresh against the new text so the debounced
                    // parser skips this row — we already have the right values.
                    rows[index].normalizedTextAtParse = normalizedRowTextForComposer(newValue)
                    // Kick the confirmation shimmer. The modifier clears this
                    // flag automatically when the animation finishes.
                    rows[index].showCalorieUpdateShimmer = true
                    // Notify the parent so it can schedule persistence (PATCH
                    // for saved rows, or let auto-save pick it up for new rows).
                    onQuantityFastPathUpdated(rowID)
                }
                // NOTE: Do NOT set parsePhase here. Creating a new Date() on every
                // keystroke forces SwiftUI to re-diff the row each character, causing
                // severe typing lag. The debounce timer in scheduleDebouncedParse
                // handles parse ownership via synchronizeParseOwnership() after the
                // user pauses typing.
            }
        )
    }

    private func indexForRowID(_ rowID: UUID) -> Int? {
        rows.firstIndex(where: { $0.id == rowID })
    }

    private func addMinimalRow(after rowID: UUID) {
        guard let index = indexForRowID(rowID) else { return }
        if index == rows.count - 1 {
            rows.append(.empty())
        }
        let nextIndex = min(index + 1, max(rows.count - 1, 0))
        setFocusedMinimalRowID(rows[nextIndex].id)
    }

    private func deleteCurrentEmptyRowAndFocusPrevious(rowID: UUID) {
        guard rows.count > 1 else { return }
        guard let index = indexForRowID(rowID), rows.indices.contains(index) else { return }
        let trimmed = rows[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return }

        rows.remove(at: index)
        if rows.isEmpty {
            rows = [.empty()]
        }

        let targetIndex = min(max(index - 1, 0), rows.count - 1)
        let targetRowID = rows[targetIndex].id
        DispatchQueue.main.async {
            setFocusedMinimalRowID(targetRowID)
        }
    }

    private func setFocusedMinimalRowID(_ rowID: UUID?) {
        guard focusedMinimalRowID != rowID else { return }
        focusedMinimalRowID = rowID
        onFocusedRowChanged(rowID)
    }

    private func focusLastEditableRow() {
        onInputTapped()

        if minimalStyle {
            if rows.allSatisfy(\.isSaved) {
                rows.append(.empty())
            }

            guard let targetRowID = rows.last(where: { !$0.isSaved && !$0.isDeleting })?.id else { return }
            setFocusedMinimalRowID(targetRowID)
            return
        }

        focusBinding.wrappedValue = true
    }

    @ViewBuilder
    private func trailingCaloriesView(for row: HomeLogRow) -> some View {
        let showCalories = !row.isLoading && !row.isQueued && !row.isUnresolved && !row.isFailed && row.calories != nil

        ZStack(alignment: .trailing) {
            if row.isLoading {
                RowThoughtProcessStatusView(
                    routeHint: row.loadingRouteHint ?? .unknown,
                    startedAt: row.loadingStatusStartedAt
                )
                .transition(.opacity)
            }

            QueuedRowStatusView()
                .opacity(row.isQueued ? 1 : 0)

            UnresolvedRowStatusView()
                .opacity(row.isUnresolved ? 1 : 0)

            FailedRowStatusView()
                .opacity(row.isFailed ? 1 : 0)

            if let calories = row.calories {
                Button {
                    onCaloriesTapped(row)
                } label: {
                    HStack(spacing: 6) {
                        // Red exclamation badge when one or more parsed items
                        // are placeholders. Tap routes to the same drawer as
                        // the calorie label, where the user can retry the
                        // unresolved segments.
                        if showCalories && row.hasUnresolvedItems {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.red)
                                .accessibilityLabel(
                                    Text("\(row.unresolvedItemCount) item\(row.unresolvedItemCount == 1 ? "" : "s") couldn't parse")
                                )
                        }

                        Group {
                            if row.isApproximate {
                                Text("~\(calories) cal")
                            } else {
                                RollingNumberText(value: Double(calories), suffix: " cal")
                            }
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .modifier(InsertShimmerModifier(isActive: row.showCalorieRevealShimmer, onComplete: {
                    if let index = indexForRowID(row.id) {
                        rows[index].showCalorieRevealShimmer = false
                    }
                }))
                .modifier(CalorieUpdateShimmerModifier(isActive: row.showCalorieUpdateShimmer, onComplete: {
                    if let index = indexForRowID(row.id) {
                        rows[index].showCalorieUpdateShimmer = false
                    }
                }))
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Open item details"))
                .opacity(showCalories ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: row.parsePhase)
        .animation(.easeInOut(duration: 0.2), value: row.calories)
    }
}
