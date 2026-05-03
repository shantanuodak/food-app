import SwiftUI
import UIKit

/// Purple-pink gradient used for AI-related shimmer and loading effects.
private let aiShimmerGradient = LinearGradient(
    colors: [
        Color(red: 0.58, green: 0.29, blue: 0.98),  // purple
        Color(red: 0.91, green: 0.30, blue: 0.60),  // pink
        Color(red: 0.58, green: 0.29, blue: 0.98)   // purple (bookend)
    ],
    startPoint: .leading,
    endPoint: .trailing
)

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
                                    Text(row.text)
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

struct VoiceRecordingOverlay: View {
    let transcribedText: String
    let isListening: Bool
    let audioLevel: Float
    let onCancel: () -> Void
    /// Called when the user stays silent for too long after the overlay appears.
    var onSilenceTimeout: (() -> Void)? = nil

    @State private var labelOpacity: Double = 1.0
    @State private var gradientPhase: CGFloat = 0
    /// Smooth audio level with easing — avoids jittery gradient jumps.
    @State private var smoothLevel: CGFloat = 0
    /// Tracks seconds since last detected speech for auto-dismiss.
    @State private var silenceTimer: Task<Void, Never>?

    private let silenceTimeoutSeconds: UInt64 = 4

    private var level: CGFloat { smoothLevel }

    // MARK: - Mesh Gradient (expanded + dispersed)

    private var meshPoints: [SIMD2<Float>] {
        let phase = Float(gradientPhase)
        let l = Float(level)
        // Organic sway — points drift gently based on phase + audio
        let cx = 0.5 + phase * 0.2 + l * 0.08
        let cy = 0.35 + l * 0.15
        let bx = 0.5 - phase * 0.15
        let by = 0.85 + l * 0.1
        let tx = 0.5 + phase * 0.12
        return [
            [0, 0],    [tx, 0],  [1, 0],
            [0, 0.4],  [cx, cy], [1, 0.45],
            [0, 1],    [bx, by], [1, 1]
        ]
    }

    private var meshColors: [Color] {
        let l = Double(level)
        // Richer saturation + spread across the full gradient area
        return [
            Color(red: 0.45, green: 0.15, blue: 0.85).opacity(0.55 + l * 0.2),
            Color(red: 0.35, green: 0.40, blue: 0.95).opacity(0.50 + l * 0.25),
            Color(red: 0.20, green: 0.60, blue: 0.90).opacity(0.45 + l * 0.15),

            Color(red: 0.75, green: 0.20, blue: 0.65).opacity(0.50 + l * 0.3),
            Color(red: 0.55, green: 0.25, blue: 0.95).opacity(0.65 + l * 0.3),
            Color(red: 0.30, green: 0.50, blue: 0.90).opacity(0.50 + l * 0.2),

            Color(red: 0.40, green: 0.20, blue: 0.80).opacity(0.45 + l * 0.15),
            Color(red: 0.70, green: 0.25, blue: 0.70).opacity(0.55 + l * 0.25),
            Color(red: 0.45, green: 0.30, blue: 0.85).opacity(0.45 + l * 0.15)
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                // Gradient background — taller, fades from top
                MeshGradient(width: 3, height: 3, points: meshPoints, colors: meshColors)
                    .frame(height: 240)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.3), location: 0.25),
                                .init(color: .black, location: 0.55)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                VStack(spacing: 12) {
                    if transcribedText.isEmpty {
                        Text("Listening")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .opacity(labelOpacity)
                    } else {
                        Text(transcribedText)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 24)
                    }

                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.top, 50)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                labelOpacity = 0.4
            }
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                gradientPhase = 1
            }
            startSilenceTimer()
        }
        .onDisappear {
            silenceTimer?.cancel()
        }
        .onChange(of: audioLevel) { _, newLevel in
            // Smooth the audio level with a spring so the gradient flows naturally
            withAnimation(.interpolatingSpring(stiffness: 40, damping: 8)) {
                smoothLevel = CGFloat(newLevel)
            }
        }
        .onChange(of: transcribedText) { _, newText in
            // Any new speech resets the silence timer
            if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                silenceTimer?.cancel()
            }
        }
    }

    // MARK: - Silence Timeout

    private func startSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: silenceTimeoutSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            // Only auto-dismiss if user hasn't said anything
            if transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onSilenceTimeout?() ?? onCancel()
            }
        }
    }
}

private struct InsertShimmerModifier: ViewModifier {
    let isActive: Bool
    let onComplete: () -> Void
    @State private var shimmerOffset: CGFloat = -0.6

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let sweepWidth = w * 0.55

                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.85), location: 0.45),
                                .init(color: .white.opacity(0.95), location: 0.5),
                                .init(color: .white.opacity(0.85), location: 0.55),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: sweepWidth)
                        .offset(x: shimmerOffset * (w + sweepWidth) - sweepWidth)
                        .blendMode(.sourceAtop)
                    }
                    .clipped()
                    .allowsHitTesting(false)
                    .onAppear {
                        shimmerOffset = -0.6
                        withAnimation(.easeInOut(duration: 0.7)) {
                            shimmerOffset = 1.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                            onComplete()
                        }
                    }
                }
            }
            .compositingGroup()
    }
}

/// Fast one-shot shimmer used when the calorie pill updates via the
/// client-side quantity fast path. Distinct from `InsertShimmerModifier`:
/// - shorter (~450ms total vs ~750ms) so it doesn't drag on rapid edits
/// - uses the purple→pink AI gradient so it reads as "we recalculated"
///   rather than a plain reveal
/// - wider gradient taper so small pill widths still feel like a sweep
private struct CalorieUpdateShimmerModifier: ViewModifier {
    let isActive: Bool
    let onComplete: () -> Void
    @State private var sweepPhase: CGFloat = -0.8

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let sweepWidth = w * 0.7

                        aiShimmerGradient
                            .frame(width: sweepWidth)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .white.opacity(0.7), location: 0.4),
                                        .init(color: .white, location: 0.5),
                                        .init(color: .white.opacity(0.7), location: 0.6),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .offset(x: sweepPhase * (w + sweepWidth) - sweepWidth)
                            .blendMode(.plusLighter)
                    }
                    .clipped()
                    .allowsHitTesting(false)
                    .onAppear {
                        sweepPhase = -0.8
                        withAnimation(.easeOut(duration: 0.45)) {
                            sweepPhase = 1.1
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            onComplete()
                        }
                    }
                }
            }
            .compositingGroup()
    }
}

private struct UnresolvedRowStatusView: View {
    var body: some View {
        Text("Edit & Retry")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.orange.opacity(0.95))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct FailedRowStatusView: View {
    var body: some View {
        Text(L10n.parseRetryShortLabel)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.red.opacity(0.95))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct QueuedRowStatusView: View {
    var body: some View {
        Text(L10n.parseQueuedShortLabel)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.secondary.opacity(0.95))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct RowThoughtProcessStatusView: View {
    let routeHint: LoadingRouteHint
    let startedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15)) { context in
            let start = startedAt ?? context.date
            let elapsed = max(0, context.date.timeIntervalSince(start))
            let text = phaseText(elapsed: elapsed)
            let shimmer = shimmerProgress(elapsed: elapsed)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(aiShimmerGradient)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .overlay(alignment: .trailing) {
                    GeometryReader { geometry in
                        let width = max(geometry.size.width, 1)
                        let sweepWidth = width * 0.72
                        let xOffset = (width + sweepWidth) * shimmer - sweepWidth

                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.9),
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
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
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

// MARK: - Backspace-Detecting UITextField

private class BackspaceDetectingTextField: UITextField {
    var onDeleteBackward: (() -> Void)?

    override func deleteBackward() {
        if text?.isEmpty == true || text == nil {
            onDeleteBackward?()
        }
        super.deleteBackward()
    }

    // iOS 26 applies a yellow "Writing Tools" highlight to text fields.
    // Disable it by opting out of the text interaction styling.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Remove any system-added highlight/interaction overlays
        let interactionsToRemove = interactions.filter {
            let typeName = String(describing: type(of: $0))
            return typeName.contains("Highlight") || typeName.contains("LookUp")
        }
        for interaction in interactionsToRemove {
            removeInteraction(interaction)
        }
        // Disable the Writing Tools highlight on iOS 18.2+ / iOS 26
        if #available(iOS 18.2, *) {
            self.writingToolsBehavior = .none
        }
    }
}

private struct BackspaceAwareTextFieldRepresentable: UIViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let onFocusChanged: (Bool) -> Void
    let onSubmit: () -> Void
    let onDeleteBackwardWhenEmpty: () -> Void
    var placeholder: String = ""

    func makeUIView(context: Context) -> BackspaceDetectingTextView {
        let tv = BackspaceDetectingTextView()
        tv.font = UIFont.systemFont(ofSize: 18)
        tv.backgroundColor = .clear
        tv.tintColor = .label
        tv.textColor = .label
        tv.delegate = context.coordinator
        tv.returnKeyType = .next
        tv.autocorrectionType = .no
        tv.spellCheckingType = .no
        tv.autocapitalizationType = .none
        if #available(iOS 17.0, *) {
            tv.inlinePredictionType = .no
        }
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        // Multi-line wrapping config
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)

        tv.onDeleteBackward = { [weak tv] in
            guard tv?.text.isEmpty == true else { return }
            onDeleteBackwardWhenEmpty()
        }

        // Placeholder label
        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = UIFont.systemFont(ofSize: 18)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.tag = 999
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: tv.leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: tv.topAnchor)
        ])
        placeholderLabel.isHidden = !text.isEmpty

        return tv
    }

    func updateUIView(_ uiView: BackspaceDetectingTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        // Update placeholder visibility
        if let placeholderLabel = uiView.viewWithTag(999) as? UILabel {
            placeholderLabel.isHidden = !text.isEmpty
        }
        if isFocused && !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isFocused && uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.resignFirstResponder() }
        }
        uiView.onDeleteBackward = { [weak uiView] in
            guard uiView?.text.isEmpty == true else { return }
            onDeleteBackwardWhenEmpty()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: BackspaceAwareTextFieldRepresentable

        init(_ parent: BackspaceAwareTextFieldRepresentable) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            if parent.text != newText {
                parent.text = newText
            }
            // Update placeholder
            if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
                placeholderLabel.isHidden = !newText.isEmpty
            }
            // Notify SwiftUI to resize the view
            textView.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Return key → submit (add new row), don't insert newline
            if text == "\n" {
                parent.onSubmit()
                return false
            }
            return true
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChanged(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChanged(false)
        }
    }
}

/// UITextView subclass that detects backspace on empty text and
/// reports its intrinsic height so SwiftUI wraps it to multiple lines.
private class BackspaceDetectingTextView: UITextView {
    var onDeleteBackward: (() -> Void)?

    override var intrinsicContentSize: CGSize {
        // Use current bounds width (or a fallback) to compute the height
        // needed for the text to wrap properly.
        let width = bounds.width > 0 ? bounds.width : 200
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: max(size.height, 26))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // When bounds change (rotation, layout pass), recalculate height
        // so SwiftUI gives us enough vertical space.
        let before = intrinsicContentSize.height
        invalidateIntrinsicContentSize()
        if intrinsicContentSize.height != before {
            superview?.setNeedsLayout()
        }
    }

    override func deleteBackward() {
        let wasEmpty = text.isEmpty
        super.deleteBackward()
        if wasEmpty {
            onDeleteBackward?()
        }
    }
}

private struct MinimalRowTextEditor: View {
    @Binding var text: String
    let isFocused: Bool
    let onFocusChanged: (Bool) -> Void
    let onSubmit: () -> Void
    let onDeleteBackwardWhenEmpty: () -> Void
    var placeholder: String = ""
    var showTypewriterPlaceholder: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            BackspaceAwareTextFieldRepresentable(
                text: $text,
                isFocused: isFocused,
                onFocusChanged: onFocusChanged,
                onSubmit: onSubmit,
                onDeleteBackwardWhenEmpty: onDeleteBackwardWhenEmpty,
                placeholder: showTypewriterPlaceholder ? "" : placeholder
            )
            .frame(minHeight: 26)

            if text.isEmpty && showTypewriterPlaceholder {
                TypewriterPlaceholder(text: placeholder)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct TypewriterPlaceholder: View {
    let text: String

    private let examples = [
        "Type your food here",
        "2 eggs and toast",
        "Greek yogurt with berries",
        "Chicken salad bowl",
        "Black coffee",
        "1 banana",
        "Oatmeal with honey"
    ]

    @State private var displayedText = ""
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        Text(displayedText)
            .font(.system(size: 18))
            .foregroundStyle(Color(.placeholderText))
            .onAppear { startLoop() }
            .onDisappear { animationTask?.cancel() }
    }

    private func startLoop() {
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)

            while !Task.isCancelled {
                for example in examples {
                    guard !Task.isCancelled else { return }

                    // Type in
                    for i in 1...example.count {
                        guard !Task.isCancelled else { return }
                        displayedText = String(example.prefix(i))
                        try? await Task.sleep(nanoseconds: 55_000_000)
                    }

                    // Pause to read
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    guard !Task.isCancelled else { return }

                    // Delete out
                    for i in stride(from: example.count, through: 0, by: -1) {
                        guard !Task.isCancelled else { return }
                        displayedText = String(example.prefix(i))
                        try? await Task.sleep(nanoseconds: 35_000_000)
                    }

                    // Brief pause before next
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
    }
}
