import SwiftUI
import UIKit

enum HomeInputMode: String, Hashable {
    case text
    case voice
    case camera
    case manualAdd

    var title: String {
        switch self {
        case .text: return "Text"
        case .voice: return "Voice"
        case .camera: return "Camera"
        case .manualAdd: return "Manual Add"
        }
    }

    var icon: String {
        switch self {
        case .text: return "character.cursor.ibeam"
        case .voice: return "mic.fill"
        case .camera: return "camera.fill"
        case .manualAdd: return "plus.circle.fill"
        }
    }
}

enum LoadingRouteHint: String, Hashable {
    case foodDatabase
    case ai
    case unknown
}

enum RowParsePhase: Equatable {
    case idle
    case active(routeHint: LoadingRouteHint, startedAt: Date)
    case queued
    case failed
    case unresolved
}

struct HomeLogRow: Identifiable, Equatable {
    let id: UUID
    var text: String
    var calories: Int?
    var calorieRangeText: String?
    var isApproximate: Bool
    var parsePhase: RowParsePhase
    var parsedItem: ParsedFoodItem?
    var parsedItems: [ParsedFoodItem]
    var editableItemIndices: [Int]
    var normalizedTextAtParse: String?
    var imagePreviewData: Data?
    var imageRef: String?
    /// True for rows that have already been saved to the backend.
    /// Saved rows are read-only and appear above the active input (Apple Notes style).
    var isSaved: Bool
    /// Pre-formatted time string shown below a saved row (e.g. "7:48 AM").
    var savedAt: String?

    static func empty() -> HomeLogRow {
        HomeLogRow(
            id: UUID(),
            text: "",
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

    var isLoading: Bool {
        if case .active = parsePhase {
            return true
        }
        return false
    }

    var isQueued: Bool {
        if case .queued = parsePhase {
            return true
        }
        return false
    }

    var isFailed: Bool {
        if case .failed = parsePhase {
            return true
        }
        return false
    }

    var isUnresolved: Bool {
        if case .unresolved = parsePhase {
            return true
        }
        return false
    }

    var loadingRouteHint: LoadingRouteHint? {
        if case let .active(routeHint, _) = parsePhase {
            return routeHint
        }
        return nil
    }

    var loadingStatusStartedAt: Date? {
        if case let .active(_, startedAt) = parsePhase {
            return startedAt
        }
        return nil
    }

    mutating func setParseActive(routeHint: LoadingRouteHint, startedAt: Date = Date()) {
        parsePhase = .active(routeHint: routeHint, startedAt: startedAt)
    }

    mutating func setParseQueued() {
        parsePhase = .queued
    }

    mutating func clearParsePhase() {
        parsePhase = .idle
    }

    mutating func setParseFailed() {
        parsePhase = .failed
    }

    mutating func setParseUnresolved() {
        parsePhase = .unresolved
    }

    static func predictedLoadingRouteHint(for rawText: String) -> LoadingRouteHint {
        let normalized = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return .unknown }

        let tokens = normalized
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let tokenCount = tokens.count

        let hasConnectorWord = normalized.contains(" and ") || normalized.contains(" with ")
        let hasComplexSeparator = normalized.contains(",") || normalized.contains("/") || normalized.contains("+") || normalized.contains("&")
        if hasConnectorWord || hasComplexSeparator || tokenCount > 4 {
            return .ai
        }

        let hasLeadingQuantity = normalized.range(of: #"^\d+(?:[./]\d+)?"#, options: .regularExpression) != nil
        let unitKeywords: Set<String> = [
            "cup", "cups", "tbsp", "tsp", "oz", "ounce", "ounces", "g", "gram", "grams",
            "kg", "ml", "l", "slice", "slices", "piece", "pieces", "serving", "servings",
            "bottle", "bottles", "can", "cans", "bar", "bars"
        ]
        let hasUnitKeyword = tokens.contains { unitKeywords.contains($0) }
        if hasLeadingQuantity || hasUnitKeyword || tokenCount <= 3 {
            return .foodDatabase
        }

        return .unknown
    }
}

struct RollingNumberText: View {
    let value: Double
    var fractionDigits: Int = 0
    var suffix: String = ""
    var useGrouping: Bool = false

    var body: some View {
        Text(formattedValue)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.25), value: formattedValue)
    }

    private var formattedValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = useGrouping
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let base = formatter.string(from: NSNumber(value: value)) ?? "0"
        return suffix.isEmpty ? base : "\(base)\(suffix)"
    }
}

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
        onFocusedRowChanged: @escaping (UUID?) -> Void = { _ in }
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
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(alignment: .top, spacing: 12) {
                            if row.isSaved {
                                Text(row.text)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .topLeading)
                            } else {
                                let isFirst = rows.filter({ !$0.isSaved }).first?.id == row.id
                                let placeholder = isFirst ? "1 banana" : "Add another item"

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
                                    placeholder: placeholder
                                )
                                .frame(maxWidth: .infinity, minHeight: 26, alignment: .topLeading)
                                .accessibilityLabel(Text(L10n.foodInputPrompt))
                                .accessibilityHint(Text(L10n.foodInputHint))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onInputTapped()
                                    setFocusedMinimalRowID(row.id)
                                }
                            }

                            trailingCaloriesView(for: row)
                                .frame(width: 116, alignment: .topTrailing)
                        }
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
    }

    private var joinedRowText: String {
        rows.map(\.text).joined(separator: "\n")
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
                rows[index].text = newValue
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
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
                } else {
                    // Preserve last resolved calories while user edits; replace only when a confident rematch arrives.
                    if hasActiveParseRequest {
                        rows[index].setParseQueued()
                    } else {
                        let startedAt = rows[index].loadingStatusStartedAt ?? Date()
                        rows[index].setParseActive(
                            routeHint: HomeLogRow.predictedLoadingRouteHint(for: newValue),
                            startedAt: startedAt
                        )
                    }
                    rows[index].parsedItem = nil
                    rows[index].parsedItems = []
                    rows[index].editableItemIndices = []
                    rows[index].normalizedTextAtParse = nil
                }
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

    @ViewBuilder
    private func trailingCaloriesView(for row: HomeLogRow) -> some View {
        if row.isLoading {
            RowThoughtProcessStatusView(
                routeHint: row.loadingRouteHint ?? .unknown,
                startedAt: row.loadingStatusStartedAt
            )
            .padding(.top, 4)
        } else if row.isQueued {
            QueuedRowStatusView()
                .padding(.top, 4)
        } else if row.isUnresolved {
            UnresolvedRowStatusView()
                .padding(.top, 4)
        } else if row.isFailed {
            FailedRowStatusView()
                .padding(.top, 4)
        } else if let calories = row.calories {
            Button {
                onCaloriesTapped(row)
            } label: {
                Group {
                    if row.isApproximate {
                        Text("~\(calories) cal")
                    } else {
                        RollingNumberText(value: Double(calories), suffix: " cal")
                    }
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Open item details"))
        } else {
            Color.clear
                .frame(height: 1)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
        }
    }
}

struct VoiceRecordingOverlay: View {
    let transcribedText: String
    let isListening: Bool
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 16) {
            // Pulsing mic indicator
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulseScale)

                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.3
                }
            }

            // Real-time transcription
            if transcribedText.isEmpty {
                Text("Listening...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text(transcribedText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 20)
            }

            Button("Cancel") {
                onCancel()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.red)
            .padding(.top, 4)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    colorScheme == .dark
                                        ? Color.white.opacity(0.18)
                                        : Color.white.opacity(0.85),
                                    colorScheme == .dark
                                        ? Color.white.opacity(0.05)
                                        : Color.black.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.25)
                                : Color.white.opacity(0.6),
                            lineWidth: 0.5
                        )
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.12), radius: 20, y: -5)
        .padding(.horizontal, 16)
        .padding(.bottom, 100)
    }
}

private struct UnresolvedRowStatusView: View {
    var body: some View {
        Text("Edit & Retry")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.orange.opacity(0.95))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .topTrailing)
    }
}

private struct FailedRowStatusView: View {
    var body: some View {
        Text(L10n.parseRetryShortLabel)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.red.opacity(0.95))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .topTrailing)
    }
}

private struct QueuedRowStatusView: View {
    var body: some View {
        Text(L10n.parseQueuedShortLabel)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.secondary.opacity(0.95))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .topTrailing)
    }
}

private struct RowThoughtProcessStatusView: View {
    let routeHint: LoadingRouteHint
    let startedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let start = startedAt ?? context.date
            let elapsed = max(0, context.date.timeIntervalSince(start))
            let text = phaseText(elapsed: elapsed)
            let shimmer = shimmerProgress(elapsed: elapsed)

            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.95))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .overlay(alignment: .topTrailing) {
                    GeometryReader { geometry in
                        let width = max(geometry.size.width, 1)
                        let sweepWidth = width * 0.72
                        let xOffset = (width + sweepWidth) * shimmer - sweepWidth

                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.8),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: sweepWidth, height: 16)
                        .offset(x: xOffset)
                    }
                    .mask(
                        Text(text)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .topTrailing)
                    )
                    .allowsHitTesting(false)
                }
        }
    }

    private func phaseText(elapsed: TimeInterval) -> String {
        let phrases: [String]
        switch routeHint {
        case .foodDatabase:
            phrases = [
                "Looking up food",
                "Finding best match",
                "Checking serving size",
                "Estimating calories"
            ]
        case .ai:
            phrases = [
                "Reading your note",
                "Cross-checking 3 sources",
                "Resolving serving assumptions",
                "Estimating calories"
            ]
        case .unknown:
            phrases = [
                "Analyzing entry",
                "Searching matches",
                "Estimating calories"
            ]
        }

        let phaseDuration = 1.05
        let index = Int(elapsed / phaseDuration) % phrases.count
        return phrases[index]
    }

    private func shimmerProgress(elapsed: TimeInterval) -> CGFloat {
        let cycle = 1.25
        let value = (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle
        return CGFloat(value)
    }
}

private struct MinimalRowTextEditor: View {
    @Binding var text: String
    let isFocused: Bool
    let onFocusChanged: (Bool) -> Void
    let onSubmit: () -> Void
    let onDeleteBackwardWhenEmpty: () -> Void
    var placeholder: String = ""

    @FocusState private var fieldFocused: Bool

    var body: some View {
        TextField("What did you eat?", text: $text)
            .font(.system(size: 16))
            .textFieldStyle(.plain)
            .focused($fieldFocused)
            .onSubmit { onSubmit() }
            .onChange(of: isFocused) { _, newValue in
                fieldFocused = newValue
            }
            .onChange(of: fieldFocused) { _, newValue in
                onFocusChanged(newValue)
            }
            .frame(minHeight: 26)
            .onAppear {
                if isFocused { fieldFocused = true }
            }
    }
}

struct HM00BottomActionDock: View {
    let selectedMode: HomeInputMode
    let needsClarification: Bool
    let onSelectMode: (HomeInputMode) -> Void
    let onOpenDetails: () -> Void

    init(
        selectedMode: HomeInputMode,
        needsClarification: Bool,
        onSelectMode: @escaping (HomeInputMode) -> Void,
        onOpenDetails: @escaping () -> Void
    ) {
        self.selectedMode = selectedMode
        self.needsClarification = needsClarification
        self.onSelectMode = onSelectMode
        self.onOpenDetails = onOpenDetails
    }

    var body: some View {
        HStack(spacing: 12) {
            dockButton(mode: .voice)
            dockButton(mode: .camera)
            dockButton(mode: .manualAdd)
            detailsButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private func dockButton(mode: HomeInputMode) -> some View {
        let isActive = selectedMode == mode

        return Button {
            onSelectMode(isActive ? .text : mode)
        } label: {
            Image(systemName: mode.icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isActive ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isActive ? Color.white.opacity(0.35) : Color.white.opacity(0.22), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(isActive ? 0.2 : 0.1), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(mode.title))
    }

    private var detailsButton: some View {
        Button {
            onOpenDetails()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "message")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 10, y: 4)

                if needsClarification {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .offset(x: -2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Open details"))
    }

}

struct HM03ParseSummarySection: View {
    let totals: NutritionTotals
    let hasEditedItems: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.estimatedTotalsTitle)
                .font(.headline)

            HStack(spacing: 10) {
                statPill(title: L10n.totalsCalories, value: totals.calories, fractionDigits: 0)
                statPill(title: L10n.totalsProtein, value: totals.protein, fractionDigits: 1, unit: "g")
            }
            HStack(spacing: 10) {
                statPill(title: L10n.totalsCarbs, value: totals.carbs, fractionDigits: 1, unit: "g")
                statPill(title: L10n.totalsFat, value: totals.fat, fractionDigits: 1, unit: "g")
            }

            if hasEditedItems {
                Text(L10n.totalsEditedHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.08))
        )
    }

    private func statPill(title: String, value: Double, fractionDigits: Int, unit: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                RollingNumberText(value: value, fractionDigits: fractionDigits)
                if !unit.isEmpty {
                    Text(unit)
                }
            }
                .font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.8))
        )
    }
}

struct HM02ParseAndSaveActionsSection: View {
    let isNetworkReachable: Bool
    let networkQualityHint: String
    let isParsing: Bool
    let isSaving: Bool
    let parseDisabled: Bool
    let openDetailsDisabled: Bool
    let saveDisabled: Bool
    let retryDisabled: Bool
    let showSaveDisabledHint: Bool
    let saveSuccessMessage: String?
    let lastTimeToLogLabel: String?
    let saveError: String?
    let idempotencyKeyLabel: String?
    let onParseNow: () -> Void
    let onOpenDetails: () -> Void
    let onSave: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isNetworkReachable {
                Text(L10n.offlineBanner)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if networkQualityHint != L10n.networkOnline {
                Text(networkQualityHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(L10n.parseNowButton) {
                    onParseNow()
                }
                .buttonStyle(.borderedProminent)
                .disabled(parseDisabled)
                .accessibilityLabel(Text(L10n.parseNowButton))
                .accessibilityHint(Text(L10n.parseNowHint))

                Button(L10n.openDetailsButton) {
                    onOpenDetails()
                }
                .buttonStyle(.bordered)
                .disabled(openDetailsDisabled)
                .accessibilityLabel(Text(L10n.openDetailsButton))
                .accessibilityHint(Text(L10n.openDetailsHint))

                if isParsing {
                    ProgressView()
                    Text(L10n.parseInProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button(L10n.saveLogButton) {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(saveDisabled)
                .accessibilityLabel(Text(L10n.saveLogButton))
                .accessibilityHint(Text(L10n.saveLogHint))

                Button(L10n.retryLastSaveButton) {
                    onRetry()
                }
                .buttonStyle(.bordered)
                .disabled(retryDisabled)
                .accessibilityLabel(Text(L10n.retryLastSaveButton))
                .accessibilityHint(Text(L10n.retryLastSaveHint))

                if isSaving {
                    ProgressView()
                    Text(L10n.saveInProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showSaveDisabledHint {
                Text(L10n.saveDisabledNeedsClarification)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let saveSuccessMessage {
                Text(saveSuccessMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }

            if let lastTimeToLogLabel {
                Text(lastTimeToLogLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let saveError {
                Text(saveError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let idempotencyKeyLabel {
                Text(idempotencyKeyLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

struct HM06DaySummarySection: View {
    @Binding var selectedDate: Date
    let maximumDate: Date
    let isLoading: Bool
    let daySummaryError: String?
    let daySummary: DaySummaryResponse?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.daySummaryTitle)
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }

            HStack {
                DatePicker(
                    L10n.daySummaryDateLabel,
                    selection: $selectedDate,
                    in: ...Calendar.current.startOfDay(for: maximumDate),
                    displayedComponents: .date
                )
                    .labelsHidden()
                Text(Self.summaryDisplayFormatter.string(from: selectedDate))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let daySummaryError {
                Text(daySummaryError)
                    .font(.footnote)
                    .foregroundStyle(.red)

                Button(L10n.retrySummaryButton) {
                    onRetry()
                }
                .buttonStyle(.bordered)
            } else if let daySummary {
                if isSummaryEmpty(daySummary) {
                    Text(L10n.daySummaryZeroTotals)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                summaryProgressRow(
                    title: L10n.totalsCalories,
                    consumed: daySummary.totals.calories,
                    target: daySummary.targets.calories,
                    remaining: daySummary.remaining.calories,
                    unit: "kcal"
                )

                summaryProgressRow(
                    title: L10n.totalsProtein,
                    consumed: daySummary.totals.protein,
                    target: daySummary.targets.protein,
                    remaining: daySummary.remaining.protein,
                    unit: "g"
                )

                summaryProgressRow(
                    title: L10n.totalsCarbs,
                    consumed: daySummary.totals.carbs,
                    target: daySummary.targets.carbs,
                    remaining: daySummary.remaining.carbs,
                    unit: "g"
                )

                summaryProgressRow(
                    title: L10n.totalsFat,
                    consumed: daySummary.totals.fat,
                    target: daySummary.targets.fat,
                    remaining: daySummary.remaining.fat,
                    unit: "g"
                )
            } else {
                Text(L10n.loadingDaySummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.08))
        )
    }

    private func summaryProgressRow(
        title: String,
        consumed: Double,
        target: Double,
        remaining: Double,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 0) {
                    RollingNumberText(value: consumed, fractionDigits: 1)
                    Text("/")
                    RollingNumberText(value: target, fractionDigits: 1)
                    Text(" \(unit)")
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressFraction(consumed: consumed, target: target))
                .tint(.green)

            Text(L10n.remainingLabel(max(remaining, 0), unit: unit))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.85))
        )
    }

    private func progressFraction(consumed: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(max(consumed / target, 0), 1)
    }

    private func isSummaryEmpty(_ summary: DaySummaryResponse) -> Bool {
        summary.totals.calories <= 0.05 &&
            summary.totals.protein <= 0.05 &&
            summary.totals.carbs <= 0.05 &&
            summary.totals.fat <= 0.05
    }

    private func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static let summaryDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct HM04ClarificationEscalationSection: View {
    let parseResult: ParseLogResponse
    let isEscalating: Bool
    let escalationInfoMessage: String?
    let escalationError: String?
    let disabledReason: String?
    let canEscalate: Bool
    let onEscalate: () -> Void

    var body: some View {
        if parseResult.needsClarification {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.clarificationNeededTitle)
                    .font(.headline)

                ForEach(Array(parseResult.clarificationQuestions.enumerated()), id: \.offset) { index, question in
                    Text("\(index + 1). \(question)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button(L10n.escalateParseButton) {
                    onEscalate()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!canEscalate)
                .accessibilityLabel(Text(L10n.escalateParseButton))
                .accessibilityHint(Text(L10n.escalateParseHint))

                if isEscalating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L10n.escalatingInProgress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let escalationInfoMessage {
                    Text(escalationInfoMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                if let escalationError {
                    Text(escalationError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let disabledReason {
                    Text(disabledReason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.08))
            )
        } else if let escalationInfoMessage {
            Text(escalationInfoMessage)
                .font(.footnote)
                .foregroundStyle(.green)
        }
    }
}
