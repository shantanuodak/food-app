import SwiftUI
import UIKit

extension MainLoggingShellView {
    // MARK: - Camera Input

    /// Drawer row for an unresolved-placeholder item. Renders the original
    /// segment text plus a quiet inline caption with an underlined "Retry"
    /// link — same visual register as the offline/syncing caption. Tapping
    /// the link calls `retryUnresolvedItem`. While retrying the link is
    /// replaced by an inline spinner + "Retrying…" caption with no layout
    /// shift.
    @ViewBuilder
    func unresolvedItemRow(rowID: UUID, itemIndex: Int, item: ParsedFoodItem) -> some View {
        let key = "\(rowID.uuidString)-\(itemIndex)"
        let isRetrying = retryingPlaceholderKeys.contains(key)

        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            HStack(spacing: 4) {
                if isRetrying {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Retrying…")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.467, green: 0.416, blue: 0.380))
                } else {
                    Text("Couldn't parse · ")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.467, green: 0.416, blue: 0.380))
                    Button {
                        Task { await retryUnresolvedItem(rowID: rowID, itemIndex: itemIndex) }
                    } label: {
                        Text("Retry")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.902, green: 0.361, blue: 0.102))
                            .underline()
                            .padding(.vertical, 6)
                            .padding(.horizontal, 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRetrying)
                    .accessibilityLabel(Text("Retry parsing \(item.name)"))
                    .accessibilityHint(Text("Re-attempt to parse this item"))
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    func parseAndUpdateDrawer(_ image: UIImage, prefetchedBarcode: DetectedBarcode? = nil, contextNote: String? = nil) async {
        let flowStartedAt = Date()
        let clientAttemptId = UUID().uuidString.lowercased()
        // P1+P2 fix (2026-05-20): ImageVisionPipeline now downscales to
        // <=1280px and uses a 2500ms default timeout (was 800ms which
        // was consistently expiring on full-res HEIC). Removing the
        // explicit timeoutMs arg here picks up the new default.
        async let visionTask = ImageVisionPipeline.analyze(image)
        async let preparedTask = Task.detached(priority: .userInitiated) {
            MainLoggingShellView.prepareImagePayload(from: image)
        }.value

        let (visionResult, prepared) = await (visionTask, preparedTask)
        // V3.1 Phase 4: as soon as iOS Vision picks a lane, push the hint
        // into the analyzing drawer so the user sees "Scanning barcode…" or
        // "Reading nutrition label…" instead of the generic copy. Vision-lane
        // (the default) keeps the existing multi-phase progression.
        //
        // P0 fix (2026-05-20): pass the live-detected barcode (if any)
        // so the lane decision can short-circuit Vision's on-image
        // detection — the live AVCaptureMetadataOutput already validated
        // it, no need to re-detect on the full-res capture.
        let earlyLane = decideLane(visionResult: visionResult, prefetched: prefetchedBarcode)
        let earlyHint: AnalysisLaneHint = {
            switch earlyLane {
            case .barcode: return .barcode
            case .label:   return .label
            case .vision:  return .vision
            }
        }()
        if cameraDrawerState.isVisible {
            cameraDrawerState = .analyzing(image, earlyHint)
        }
        let imagePrepMs = Int(Date().timeIntervalSince(flowStartedAt) * 1000)
        guard let prepared else {
            ImageParseAttemptTelemetry.emit(
                apiClient: appStore.apiClient,
                clientAttemptId: clientAttemptId,
                parseRequestId: nil,
                outcome: "failed",
                errorCode: "image_prep_failed",
                prepMs: imagePrepMs,
                requestMs: nil,
                totalMs: Int(Date().timeIntervalSince(flowStartedAt) * 1000),
                backendMs: nil,
                imageBytes: nil,
                mimeType: nil,
                visionModel: nil,
                fallbackUsed: nil,
                source: .drawer
            )
            withAnimation {
                cameraDrawerState = .error("Unable to process this image.", image)
            }
            return
        }

        ensureDraftTimingStarted()

        do {
            let requestStartedAt = Date()
            let loggedAt = HomeLoggingDateUtils.loggedAtFormatter.string(from: draftLoggedAt ?? draftTimestampForSelectedDate())
            let response = try await performCameraLaneParse(
                image: image,
                prepared: prepared,
                visionResult: visionResult,
                prefetchedBarcode: prefetchedBarcode,
                contextNote: contextNote,
                clientAttemptId: clientAttemptId,
                loggedAt: loggedAt
            )
            let requestMs = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
            let totalMs = Int(Date().timeIntervalSince(flowStartedAt) * 1000)
            ImageParseAttemptTelemetry.emit(
                apiClient: appStore.apiClient,
                clientAttemptId: clientAttemptId,
                parseRequestId: response.parseRequestId,
                outcome: "succeeded",
                errorCode: nil,
                prepMs: imagePrepMs,
                requestMs: requestMs,
                totalMs: totalMs,
                backendMs: Int(response.parseDurationMs),
                imageBytes: prepared.uploadData.count,
                mimeType: prepared.mimeType,
                visionModel: response.visionModel,
                fallbackUsed: response.visionFallbackUsed,
                source: .drawer
            )
#if DEBUG
            print("[image_parse_timing] prepMs=\(imagePrepMs) requestMs=\(requestMs) totalMs=\(totalMs) backendMs=\(Int(response.parseDurationMs)) bytes=\(prepared.uploadData.count) visionModel=\(response.visionModel ?? "unknown") fallback=\(response.visionFallbackUsed == true)")
#else
            NSLog("[image_parse_timing] prepMs=%d requestMs=%d totalMs=%d backendMs=%d bytes=%d lane=%@ source=%@ visionModel=%@ fallback=%@", imagePrepMs, requestMs, totalMs, Int(response.parseDurationMs), prepared.uploadData.count, response.parseLaneUsed ?? response.inputKind ?? "image", response.parseLaneSource ?? "unknown", response.visionModel ?? "unknown", response.visionFallbackUsed == true ? "true" : "false")
#endif

            // Store the parse result and prepared data for when the user confirms
            parseResult = response
            pendingImageData = prepared.uploadData
            pendingImagePreviewData = prepared.previewData
            pendingImageMimeType = prepared.mimeType
            pendingImageStorageRef = nil
            latestParseInputKind = normalizedInputKind(response.inputKind, fallback: "image")

            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                cameraDrawerState = .parsed(image, response.items, response.totals)
            }
        } catch {
            ImageParseAttemptTelemetry.emit(
                apiClient: appStore.apiClient,
                clientAttemptId: clientAttemptId,
                parseRequestId: nil,
                outcome: "failed",
                errorCode: ImageParseAttemptTelemetry.errorCode(from: error),
                prepMs: imagePrepMs,
                requestMs: nil,
                totalMs: Int(Date().timeIntervalSince(flowStartedAt) * 1000),
                backendMs: nil,
                imageBytes: prepared.uploadData.count,
                mimeType: prepared.mimeType,
                visionModel: nil,
                fallbackUsed: nil,
                source: .drawer
            )
            handleAuthFailureIfNeeded(error)
            withAnimation {
                cameraDrawerState = .error(userFriendlyParseError(error), image)
            }
        }
    }

    private enum CameraParseLane {
        case barcode(String, String?)
        case label(String)
        case vision
    }

    private func decideLane(visionResult: ImageVisionResult, prefetched: DetectedBarcode? = nil) -> CameraParseLane {
        // P0 fix (2026-05-20): trust the live AVCaptureMetadataOutput
        // detection unconditionally — it's already been validated at
        // video rate by AVF's own barcode pipeline before we even got
        // here. No need to make Vision re-derive the same answer on the
        // full-res capture. This is the single biggest accuracy win
        // because in prod the on-image VNDetectBarcodesRequest was
        // routinely timing out and falling through to the vision lane.
        if let prefetched {
            return .barcode(prefetched.payload, prefetched.symbology)
        }
        if let barcode = visionResult.barcode, barcode.confidence >= 0.95 {
            return .barcode(barcode.payload, barcode.symbology)
        }
        if let label = visionResult.labelPanel, label.confidence >= 0.7 {
            return .label(visionResult.ocrText)
        }
        if let barcode = visionResult.barcode,
           barcode.confidence >= 0.80,
           visionResult.labelPanel == nil {
            return .barcode(barcode.payload, barcode.symbology)
        }
        return .vision
    }

    private func performCameraLaneParse(
        image: UIImage,
        prepared: PreparedImagePayload,
        visionResult: ImageVisionResult,
        prefetchedBarcode: DetectedBarcode? = nil,
        contextNote: String?,
        clientAttemptId: String,
        loggedAt: String
    ) async throws -> ParseLogResponse {
        switch decideLane(visionResult: visionResult, prefetched: prefetchedBarcode) {
        case let .barcode(code, symbology):
            do {
                let barcodeResponse = try await appStore.apiClient.parseBarcode(
                    code: code,
                    symbology: symbology,
                    contextNote: contextNote,
                    clientAttemptId: clientAttemptId,
                    loggedAt: loggedAt
                )
                if barcodeResponse.fallback == "image" {
                    if visionResult.labelPanel != nil, !visionResult.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return try await performLabelParse(
                            prepared: prepared,
                            ocrText: visionResult.ocrText,
                            contextNote: contextNote,
                            clientAttemptId: clientAttemptId,
                            loggedAt: loggedAt
                        )
                    }
                    return try await performVisionParse(
                        prepared: prepared,
                        contextNote: contextNote,
                        clientAttemptId: clientAttemptId,
                        loggedAt: loggedAt
                    )
                }
                return barcodeResponse
            } catch {
                return try await performVisionParse(
                    prepared: prepared,
                    contextNote: contextNote,
                    clientAttemptId: clientAttemptId,
                    loggedAt: loggedAt
                )
            }

        case let .label(ocrText):
            do {
                return try await performLabelParse(
                    prepared: prepared,
                    ocrText: ocrText,
                    contextNote: contextNote,
                    clientAttemptId: clientAttemptId,
                    loggedAt: loggedAt
                )
            } catch {
                return try await performVisionParse(
                    prepared: prepared,
                    contextNote: contextNote,
                    clientAttemptId: clientAttemptId,
                    loggedAt: loggedAt
                )
            }

        case .vision:
            return try await performVisionParse(
                prepared: prepared,
                contextNote: contextNote,
                clientAttemptId: clientAttemptId,
                loggedAt: loggedAt
            )
        }
    }

    private func performLabelParse(
        prepared: PreparedImagePayload,
        ocrText: String,
        contextNote: String?,
        clientAttemptId: String,
        loggedAt: String
    ) async throws -> ParseLogResponse {
        try await appStore.apiClient.parseLabel(
            ocrText: ocrText,
            imageData: prepared.uploadData,
            mimeType: prepared.mimeType,
            contextNote: contextNote,
            clientAttemptId: clientAttemptId,
            loggedAt: loggedAt
        )
    }

    private func performVisionParse(
        prepared: PreparedImagePayload,
        contextNote: String?,
        clientAttemptId: String,
        loggedAt: String
    ) async throws -> ParseLogResponse {
        try await appStore.apiClient.parseImageLog(
            imageData: prepared.uploadData,
            mimeType: prepared.mimeType,
            loggedAt: loggedAt,
            contextNote: contextNote,
            clientAttemptId: clientAttemptId
        )
    }

    @MainActor
    func handleDrawerLogIt(editedItems: [ParsedFoodItem]? = nil, editedTotals: NutritionTotals? = nil) {
        guard case .parsed(_, let items, _) = cameraDrawerState,
              let response = parseResult else { return }

        let confirmedItems = editedItems ?? items
        let confirmedTotals = editedTotals ?? response.totals
        let confirmedResponse = photoResponse(
            from: response,
            confirmedItems: confirmedItems,
            confirmedTotals: confirmedTotals
        )

        // Populate the input row with a short display name.
        // Full detail (brand, protein content, flavor, etc.) lives in the items
        // and is shown in the details drawer — the home screen just needs a readable label.
        let rowText = HomeLoggingDisplayText.shortenedFoodLabel(items: confirmedItems, extractedText: response.extractedText)

        var row = HomeLogRow.empty()
        row.text = rowText
        row.imagePreviewData = pendingImagePreviewData
        row.imageRef = pendingImageStorageRef
        row.mealType = currentDraftMealType()
        suppressDebouncedParseOnce = true

        // Preserve existing rows (both saved history and unsaved drafts the user typed)
        // instead of wiping them. Insert the camera row before the trailing empty row.
        let savedRows = inputRows.filter { $0.isSaved }
        let unsavedNonEmpty = inputRows.filter {
            !$0.isSaved && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        inputRows = savedRows + unsavedNonEmpty + [row]
        clearParseSchedulerState()

        parseResult = confirmedResponse
        latestParseInputKind = normalizedInputKind(confirmedResponse.inputKind, fallback: "image")
        editableItems = confirmedItems.map(EditableParsedItem.init(apiItem:))

        // Find the camera row we just inserted (the one with the image data)
        let cameraRowIndex = inputRows.lastIndex(where: { $0.id == row.id })
        let cameraRowIDSet: Set<UUID> = [row.id]
        applyRowParseResult(confirmedResponse, targetRowIDs: cameraRowIDSet)
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
            response: confirmedResponse,
            fallbackRawText: rowText
        )
        scheduleAutoSave()

        // V3.1 hotfix v2 (2026-05-20): two possible presenters depending on
        // entry point — dismiss both. For the camera-capture path the
        // analysis sheet is nested in the camera fullScreenCover, so
        // dismissing the cover tears the sheet down too (avoids a flash of
        // the camera review screen). For the photo-library path it's a
        // sibling sheet on the home view, dismissed by the second flag.
        // Setting whichever flag isn't currently true is a no-op.
        isCustomCameraPresented = false
        isCameraAnalysisSheetPresented = false
    }

    private func photoResponse(
        from response: ParseLogResponse,
        confirmedItems: [ParsedFoodItem],
        confirmedTotals: NutritionTotals
    ) -> ParseLogResponse {
        let loggedAt = HomeLoggingDateUtils.loggedAtFormatter.string(
            from: draftLoggedAt ??
                HomeLoggingDateUtils.date(fromLoggedAt: response.loggedAt) ??
                Date()
        )

        return ParseLogResponse(
            requestId: response.requestId,
            parseRequestId: response.parseRequestId,
            parseVersion: response.parseVersion,
            route: response.route,
            cacheHit: response.cacheHit,
            sourcesUsed: response.sourcesUsed,
            fallbackUsed: response.fallbackUsed,
            fallbackModel: response.fallbackModel,
            budget: response.budget,
            needsClarification: false,
            clarificationQuestions: [],
            reasonCodes: response.reasonCodes,
            retryAfterSeconds: response.retryAfterSeconds,
            parseDurationMs: response.parseDurationMs,
            loggedAt: loggedAt,
            confidence: response.confidence,
            totals: confirmedTotals,
            items: confirmedItems,
            assumptions: response.assumptions,
            cacheDebug: response.cacheDebug,
            inputKind: response.inputKind,
            extractedText: response.extractedText,
            imageMeta: response.imageMeta,
            visionModel: response.visionModel,
            visionFallbackUsed: response.visionFallbackUsed,
            parseLaneUsed: response.parseLaneUsed,
            parseLaneSource: response.parseLaneSource,
            parseLaneLatencyMs: response.parseLaneLatencyMs,
            fallback: response.fallback,
            missReason: response.missReason,
            dietaryFlags: response.dietaryFlags
        )
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
        cameraDrawerContextNote = ""
        cameraDrawerState = .analyzing(image, nil)
        isCameraAnalysisSheetPresented = true
        await parseAndUpdateDrawer(image)
    }

}
