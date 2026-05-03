import SwiftUI
import UIKit

extension MainLoggingShellView {
    // MARK: - Camera Input

    /// Drawer row for an unresolved-placeholder item. Shows the original
    /// segment text + a Retry button (or a spinner while a retry is
    /// in flight). Tapping Retry calls `retryUnresolvedItem`.
    @ViewBuilder
    func unresolvedItemRow(rowID: UUID, itemIndex: Int, item: ParsedFoodItem) -> some View {
        let key = "\(rowID.uuidString)-\(itemIndex)"
        let isRetrying = retryingPlaceholderKeys.contains(key)

        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("Couldn't parse — tap Retry")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await retryUnresolvedItem(rowID: rowID, itemIndex: itemIndex) }
            } label: {
                Group {
                    if isRetrying {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.primary)
                    } else {
                        Text("Retry")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(width: 64, height: 32)
                .background(
                    Capsule().fill(Color.red.opacity(0.12))
                )
                .overlay(
                    Capsule().stroke(Color.red.opacity(0.35), lineWidth: 1)
                )
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(isRetrying)
            .accessibilityLabel(Text("Retry parsing \(item.name)"))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.red.opacity(0.18), lineWidth: 1)
                )
        )
    }

    // MARK: - Per-item Retry (drawer)
    //
    // When the segment-aware parser couldn't resolve a segment it emits a
    // placeholder item; the drawer renders that with a Retry button.
    // Retry re-parses just that segment text and replaces the placeholder
    // with the new item if the second pass succeeds. In-memory only —
    // saved-row persistence (PATCH) is queued as a separate follow-up.

    @MainActor
    func retryUnresolvedItem(rowID: UUID, itemIndex: Int) async {
        let key = "\(rowID.uuidString)-\(itemIndex)"
        guard !retryingPlaceholderKeys.contains(key) else { return }
        retryingPlaceholderKeys.insert(key)
        defer { retryingPlaceholderKeys.remove(key) }

        guard let rowIndex = inputRows.firstIndex(where: { $0.id == rowID }) else { return }
        guard itemIndex < inputRows[rowIndex].parsedItems.count else { return }
        let placeholder = inputRows[rowIndex].parsedItems[itemIndex]
        guard placeholder.isUnresolvedPlaceholder else { return }

        let segmentText = placeholder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segmentText.isEmpty else { return }

        let loggedAtIso = HomeLoggingDateUtils.loggedAtFormatter.string(from: draftLoggedAt ?? draftTimestampForSelectedDate())
        let request = ParseLogRequest(text: segmentText, loggedAt: loggedAtIso)

        do {
            let response = try await appStore.apiClient.parseLog(request)

            // Pick the first non-placeholder item the retry produced.
            // If the retry ALSO came back as a placeholder, leave the
            // existing one in place — the user can edit the text or try
            // again.
            guard let resolved = response.items.first(where: { !$0.isUnresolvedPlaceholder }) else {
                return
            }

            // Re-validate the row + item index — the row may have been
            // edited or removed during the in-flight retry.
            guard let freshRowIndex = inputRows.firstIndex(where: { $0.id == rowID }),
                  itemIndex < inputRows[freshRowIndex].parsedItems.count,
                  inputRows[freshRowIndex].parsedItems[itemIndex].isUnresolvedPlaceholder else {
                return
            }

            inputRows[freshRowIndex].parsedItems[itemIndex] = resolved

            // Recompute row totals from the updated items so the row's
            // headline calorie reflects the freshly-parsed item.
            let totalCalories = inputRows[freshRowIndex].parsedItems.reduce(0.0) { $0 + $1.calories }
            inputRows[freshRowIndex].calories = Int(totalCalories.rounded())
            inputRows[freshRowIndex].showCalorieUpdateShimmer = true

            // If this row has already been persisted (saved on a prior
            // day or auto-saved earlier), push the in-memory swap to the
            // server so the placeholder doesn't reappear on the next
            // day-summary fetch. `performPatchUpdate` reads the row's
            // current parsedItems and totals and PATCHes the log,
            // refreshes the day cache, and posts the
            // `nutritionProgressDidChange` notification — same flow used
            // for any other row edit. Soft-fail on errors (the in-memory
            // state is still correct).
            if let serverLogId = inputRows[freshRowIndex].serverLogId {
                await performPatchUpdate(rowID: rowID, serverLogId: serverLogId)
            }
        } catch {
            // Soft fail — keep placeholder. The button stays available.
            // We could surface a toast here in a follow-up.
        }
    }

    // MARK: - Custom Camera Drawer Flow

    @MainActor
    func parseAndUpdateDrawer(_ image: UIImage) async {
        guard let prepared = prepareImagePayload(from: image) else {
            withAnimation {
                cameraDrawerState = .error("Unable to process this image.", image)
            }
            return
        }

        ensureDraftTimingStarted()

        do {
            let response = try await appStore.apiClient.parseImageLog(
                imageData: prepared.uploadData,
                mimeType: prepared.mimeType,
                loggedAt: HomeLoggingDateUtils.loggedAtFormatter.string(from: draftLoggedAt ?? draftTimestampForSelectedDate())
            )

            // Store the parse result and prepared data for when the user confirms
            parseResult = response
            pendingImageData = prepared.uploadData
            pendingImagePreviewData = prepared.previewData
            pendingImageMimeType = prepared.mimeType
            pendingImageStorageRef = nil
            latestParseInputKind = "image"

            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                cameraDrawerState = .parsed(image, response.items, response.totals)
            }
        } catch {
            handleAuthFailureIfNeeded(error)
            withAnimation {
                cameraDrawerState = .error(userFriendlyParseError(error), image)
            }
        }
    }

    @MainActor
    func handleDrawerLogIt() {
        guard case .parsed(_, let items, _) = cameraDrawerState,
              let response = parseResult else { return }

        // Populate the input row with a short display name.
        // Full detail (brand, protein content, flavor, etc.) lives in the items
        // and is shown in the details drawer — the home screen just needs a readable label.
        let rowText = HomeLoggingDisplayText.shortenedFoodLabel(items: items, extractedText: response.extractedText)

        var row = HomeLogRow.empty()
        row.text = rowText
        row.imagePreviewData = pendingImagePreviewData
        row.imageRef = pendingImageStorageRef
        suppressDebouncedParseOnce = true

        // Preserve existing rows (both saved history and unsaved drafts the user typed)
        // instead of wiping them. Insert the camera row before the trailing empty row.
        let savedRows = inputRows.filter { $0.isSaved }
        let unsavedNonEmpty = inputRows.filter {
            !$0.isSaved && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        inputRows = savedRows + unsavedNonEmpty + [row]
        clearParseSchedulerState()

        latestParseInputKind = normalizedInputKind(response.inputKind, fallback: "image")
        editableItems = response.items.map(EditableParsedItem.init(apiItem:))

        // Find the camera row we just inserted (the one with the image data)
        let cameraRowIndex = inputRows.lastIndex(where: { $0.id == row.id })
        let cameraRowIDSet: Set<UUID> = [row.id]
        applyRowParseResult(response, targetRowIDs: cameraRowIDSet)
        if let idx = cameraRowIndex {
            inputRows[idx].imagePreviewData = pendingImagePreviewData
            inputRows[idx].imageRef = pendingImageStorageRef
        }

        parseInfoMessage = nil
        parseError = nil
        saveError = nil
        appStore.setError(nil)
        upsertParseSnapshot(
            rowID: row.id,
            response: response,
            fallbackRawText: rowText
        )
        scheduleAutoSave()

        // Dismiss the sheet — food appears on home screen
        isCameraAnalysisSheetPresented = false
    }

    @MainActor
    func handlePickedImage(_ image: UIImage) async {
        // Dismiss the picker sheet first, then open the analysis drawer —
        // identical flow to the camera capture path so both feel the same.
        isImagePickerPresented = false
        inputMode = .text
        selectedCameraSource = nil

        debounceTask?.cancel()
        parseTask?.cancel()
        cancelAutoSaveTask()
        parseRequestSequence += 1
        parseCoordinator.clearAll()
        autoSavedParseIDs = []
        clearPendingSaveContext()
        appStore.setError(nil)
        parseError = nil
        saveError = nil
        saveSuccessMessage = nil
        escalationError = nil
        escalationInfoMessage = nil
        escalationBlockedCode = nil

        // iOS needs a beat between sheet dismissal and the next sheet presentation.
        try? await Task.sleep(for: .milliseconds(350))

        cameraDrawerImage = image
        cameraDrawerState = .analyzing(image)
        isCameraAnalysisSheetPresented = true
        await parseAndUpdateDrawer(image)
    }

}
