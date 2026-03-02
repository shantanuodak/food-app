import SwiftUI
import Foundation
import PhotosUI
import UIKit

struct MainLoggingShellView: View {
    @EnvironmentObject private var appStore: AppStore

    @State private var inputRows: [HomeLogRow] = [.empty()]
    @State private var parseInFlightCount = 0
    @State private var parseRequestSequence = 0
    @State private var parseResult: ParseLogResponse?
    @State private var parseError: String?
    @State private var parseInfoMessage: String?
    @State private var debounceTask: Task<Void, Never>?
    @State private var parseTask: Task<Void, Never>?
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var isDetailsDrawerPresented = false
    @State private var editableItems: [EditableParsedItem] = []
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var saveSuccessMessage: String?
    @State private var pendingSaveRequest: SaveLogRequest?
    @State private var pendingSaveFingerprint: String?
    @State private var pendingSaveIdempotencyKey: UUID?
    @State private var isEscalating = false
    @State private var escalationError: String?
    @State private var escalationInfoMessage: String?
    @State private var escalationBlockedCode: String?
    @State private var selectedSummaryDate = Date()
    @State private var daySummary: DaySummaryResponse?
    @State private var isLoadingDaySummary = false
    @State private var daySummaryError: String?
    @FocusState private var isNoteEditorFocused: Bool
    @State private var flowStartedAt: Date?
    @State private var draftLoggedAt: Date?
    @State private var lastTimeToLogMs: Double?
    @State private var lastAutoSavedContentFingerprint: String?
    @State private var inputMode: HomeInputMode = .text
    @State private var detailsDrawerMode: DetailsDrawerMode = .full
    @State private var selectedRowDetails: RowCalorieDetails?
    @State private var activeEditingRowID: UUID?
    @State private var rowsPendingParseIDs: Set<UUID> = []
    @State private var isCameraSourceDialogPresented = false
    @State private var selectedCameraSource: CameraInputSource?
    @State private var isImagePickerPresented = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var pendingImageData: Data?
    @State private var pendingImagePreviewData: Data?
    @State private var pendingImageMimeType: String?
    @State private var pendingImageStorageRef: String?
    @State private var latestParseInputKind: String = "text"
    @State private var suppressDebouncedParseOnce = false
    private let defaults = UserDefaults.standard
    private let autoSaveDelayNs: UInt64 = 10_000_000_000
    private let autoSaveMinConfidence = 0.70

    private enum DetailsDrawerMode {
        case compact
        case full
        case manualAdd
    }

    private enum CameraInputSource {
        case takePicture
        case photo

        var statusMessage: String {
            switch self {
            case .takePicture:
                return "Captured photo ready for parsing."
            case .photo:
                return "Selected photo ready for parsing."
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    composeEntrySection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                topHeaderStrip
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
            }
            .confirmationDialog(
                "Add from",
                isPresented: $isCameraSourceDialogPresented,
                titleVisibility: .visible
            ) {
                Button("Take a picture") {
                    handleCameraSourceSelection(.takePicture)
                }
                Button("Photo") {
                    handleCameraSourceSelection(.photo)
                }
                Button("Cancel", role: .cancel) {
                    inputMode = .text
                }
            } message: {
                Text("Choose how you want to add food.")
            }
            .padding()
            .onChange(of: rowTextSignature) { _, _ in
                if suppressDebouncedParseOnce {
                    suppressDebouncedParseOnce = false
                    return
                }
                if latestParseInputKind == "image" {
                    clearImageContext()
                }
                if !trimmedNoteText.isEmpty, inputMode != .text {
                    inputMode = .text
                }
                scheduleDebouncedParse(for: noteText)
            }
            .onChange(of: inputMode) { _, newMode in
                if newMode == .camera {
                    isCameraSourceDialogPresented = true
                }
            }
            .onChange(of: selectedSummaryDate) { _, _ in
                let clamped = clampedSummaryDate(selectedSummaryDate)
                if !Calendar.current.isDate(clamped, inSameDayAs: selectedSummaryDate) {
                    selectedSummaryDate = clamped
                    return
                }
                refreshDaySummary()
            }
            .onAppear {
                restorePendingSaveContextIfNeeded()
                refreshDaySummary()
            }
            .onDisappear {
                debounceTask?.cancel()
                parseTask?.cancel()
                autoSaveTask?.cancel()
            }
            .sheet(isPresented: $isDetailsDrawerPresented) {
                detailsDrawer
            }
            .sheet(isPresented: $isImagePickerPresented) {
                HomeImagePicker(
                    sourceType: imagePickerSourceType,
                    onImagePicked: { image in
                        Task {
                            await handlePickedImage(image)
                        }
                    },
                    onCancel: {
                        inputMode = .text
                        selectedCameraSource = nil
                    }
                )
            }
            .sheet(item: $selectedRowDetails) { details in
                rowCalorieDetailsSheet(details)
            }
        }
    }

    private var topHeaderStrip: some View {
        HStack(alignment: .center, spacing: 12) {
            HomeGreetingChip(firstName: loggedInFirstName)

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedSummaryDate = Calendar.current.startOfDay(for: Date())
                }
            } label: {
                Text(todayPillTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
            }
            .buttonStyle(LiquidGlassCapsuleButtonStyle())
            .accessibilityLabel(Text("Select today"))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                    handleTopHeaderSwipe(value)
                }
        )
    }

    private var todayPillTitle: String {
        if Calendar.current.isDateInToday(selectedSummaryDate) {
            return "Today"
        }
        return Self.topDateFormatter.string(from: selectedSummaryDate)
    }

    private var loggedInFirstName: String? {
        let session = appStore.authSessionStore.session
        let emailLocalPart = session?.email?
            .split(separator: "@", maxSplits: 1)
            .first
            .map(String.init)

        if let firstName = normalizedFirstName(from: session?.firstName) {
            // Ignore low-quality values that are identical to an email username like "shantanuodak".
            if let emailLocalPart,
               firstName.caseInsensitiveCompare(emailLocalPart) == .orderedSame,
               !emailLocalPart.contains(where: { !$0.isLetter }) {
                // Fall through to JWT or better sources.
            } else {
                return firstName
            }
        }

        if let firstName = normalizedFirstName(fromJWT: session?.accessToken) {
            return firstName
        }

        return normalizedFirstName(fromEmail: session?.email)
    }

    private func normalizedFirstName(from rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let firstToken = trimmed.split(whereSeparator: { !$0.isLetter }).first
        guard let firstToken, !firstToken.isEmpty else {
            return nil
        }

        return firstToken.prefix(1).uppercased() + firstToken.dropFirst().lowercased()
    }

    private func normalizedFirstName(fromEmail email: String?) -> String? {
        guard let email else {
            return nil
        }

        guard let localPart = email.split(separator: "@", maxSplits: 1).first.map(String.init) else {
            return nil
        }

        // Only use email fallback when a clear separator exists (e.g. john.doe, john_doe).
        guard localPart.contains(where: { !$0.isLetter }) else {
            return nil
        }

        return normalizedFirstName(from: localPart)
    }

    private func normalizedFirstName(fromJWT token: String?) -> String? {
        guard let token else {
            return nil
        }

        let segments = token.split(separator: ".")
        guard segments.count > 1 else {
            return nil
        }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = payload.count % 4
        if padding > 0 {
            payload += String(repeating: "=", count: 4 - padding)
        }

        guard let data = Data(base64Encoded: payload),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let claims = jsonObject as? [String: Any] else {
            return nil
        }

        if let firstName = extractFirstName(from: claims) {
            return firstName
        }

        if let metadata = claims["user_metadata"] as? [String: Any] {
            return extractFirstName(from: metadata)
        }

        return nil
    }

    private func extractFirstName(from source: [String: Any]) -> String? {
        for key in ["name", "full_name"] {
            if let value = source[key] as? String,
               value.contains(where: { !$0.isLetter }),
               let first = normalizedFirstName(from: value) {
                return first
            }
        }

        if let givenName = source["given_name"] as? String {
            let familyNameCandidate = (source["family_name"] as? String) ?? (source["last_name"] as? String)
            if let familyName = familyNameCandidate {
                let normalizedGiven = givenName.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedFamily = familyName.trimmingCharacters(in: .whitespacesAndNewlines)

                if !normalizedGiven.isEmpty,
                   !normalizedFamily.isEmpty,
                   normalizedGiven.count > normalizedFamily.count,
                   normalizedGiven.lowercased().hasSuffix(normalizedFamily.lowercased()) {
                    let firstOnly = String(normalizedGiven.dropLast(normalizedFamily.count))
                    if let first = normalizedFirstName(from: firstOnly) {
                        return first
                    }
                }
            }
        }

        for key in ["given_name", "first_name"] {
            if let value = source[key] as? String,
               let first = normalizedFirstName(from: value) {
                return first
            }
        }

        return nil
    }

    private func handleTopHeaderSwipe(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height
        guard abs(horizontal) > abs(vertical), abs(horizontal) >= 40 else {
            return
        }

        if horizontal > 0 {
            shiftSelectedSummaryDate(byDays: -1)
        } else {
            shiftSelectedSummaryDate(byDays: 1)
        }
    }

    private func shiftSelectedSummaryDate(byDays days: Int) {
        guard let moved = Calendar.current.date(byAdding: .day, value: days, to: selectedSummaryDate) else {
            return
        }

        let normalized = clampedSummaryDate(moved)
        guard !Calendar.current.isDate(normalized, inSameDayAs: selectedSummaryDate) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSummaryDate = normalized
        }
    }

    private func clampedSummaryDate(_ date: Date) -> Date {
        let normalized = Calendar.current.startOfDay(for: date)
        let today = Calendar.current.startOfDay(for: Date())
        return min(normalized, today)
    }

    private var isEmptyHomeState: Bool {
        trimmedNoteText.isEmpty &&
            parseResult == nil &&
            editableItems.isEmpty
    }

    private var isParsing: Bool {
        parseInFlightCount > 0
    }

    private var composeEntrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What did you eat today?")
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            inputSection
            homeStatusStrip
        }
    }

    private var inputSection: some View {
        HM01LogComposerSection(
            rows: $inputRows,
            focusBinding: $isNoteEditorFocused,
            mode: inputMode,
            inlineEstimateText: nil,
            minimalStyle: true,
            onInputTapped: {
                inputMode = .text
            },
            onCaloriesTapped: { row in
                presentRowDetails(for: row)
            },
            onFocusedRowChanged: { rowID in
                activeEditingRowID = rowID
            }
        )
    }

    private var noteText: String {
        inputRows.map(\.text).joined(separator: "\n")
    }

    private var trimmedNoteText: String {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parseCandidateRows: [String] {
        let normalized = inputRows.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var end = normalized.count
        while end > 0, normalized[end - 1].isEmpty {
            end -= 1
        }
        return Array(normalized.prefix(end))
    }

    private var rowTextSignature: String {
        parseCandidateRows.joined(separator: "\u{001F}")
    }

    private var parseActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HM02ParseAndSaveActionsSection(
                isNetworkReachable: appStore.isNetworkReachable,
                networkQualityHint: appStore.networkQualityHint,
                isParsing: isParsing,
                isSaving: isSaving,
                parseDisabled: isParsing || !appStore.isNetworkReachable || trimmedNoteText.isEmpty,
                openDetailsDisabled: parseResult == nil,
                saveDisabled: isSaving || !appStore.isNetworkReachable || buildSaveDraftRequest() == nil || parseResult?.needsClarification == true,
                retryDisabled: isSaving || !appStore.isNetworkReachable || pendingSaveRequest == nil || pendingSaveIdempotencyKey == nil,
                showSaveDisabledHint: parseResult?.needsClarification == true,
                saveSuccessMessage: saveSuccessMessage,
                lastTimeToLogLabel: lastTimeToLogMs.map { L10n.timeToLog($0 / 1000) },
                saveError: saveError,
                idempotencyKeyLabel: pendingSaveIdempotencyKey.map { L10n.idempotencyKey($0.uuidString.lowercased()) },
                onParseNow: triggerParseNow,
                onOpenDetails: {
                    detailsDrawerMode = .full
                    isDetailsDrawerPresented = true
                },
                onSave: startSaveFlow,
                onRetry: retryLastSave
            )
        }
    }

    @ViewBuilder
    private func parseSummaryCard(_: ParseLogResponse) -> some View {
        HM03ParseSummarySection(
            totals: displayedTotals,
            hasEditedItems: !editableItems.isEmpty
        )
    }

    @ViewBuilder
    private func parseMetaCard(_ result: ParseLogResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.xaxis")
                    Text("\(L10n.confidenceLabel) ")
                    RollingNumberText(value: result.confidence, fractionDigits: 3)
                }
                Spacer()
                Label(result.fallbackUsed ? L10n.fallbackUsedLabel : L10n.routeDisplayName(result.route), systemImage: "bolt.horizontal")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if result.needsClarification {
                Text(L10n.parseClarificationHint)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if let sources = result.sourcesUsed, !sources.isEmpty {
                Text("Sources: \(sources.map(sourceDisplayName).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.08))
        )
    }

    private func sourceDisplayName(_ source: String) -> String {
        switch source.lowercased() {
        case "fatsecret":
            return "Food Database"
        case "gemini":
            return "Gemini"
        case "cache":
            return "Cache"
        case "manual":
            return "Manual"
        default:
            return source
        }
    }

    @ViewBuilder
    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.8))
        )
    }

    @ViewBuilder
    private var daySummarySection: some View {
        HM06DaySummarySection(
            selectedDate: $selectedSummaryDate,
            maximumDate: Calendar.current.startOfDay(for: Date()),
            isLoading: isLoadingDaySummary,
            daySummaryError: daySummaryError,
            daySummary: daySummary,
            onRetry: refreshDaySummary
        )
    }

    @ViewBuilder
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

    @ViewBuilder
    private func clarificationEscalationSection(_ result: ParseLogResponse) -> some View {
        HM04ClarificationEscalationSection(
            parseResult: result,
            isEscalating: isEscalating,
            escalationInfoMessage: escalationInfoMessage,
            escalationError: escalationError,
            disabledReason: escalationDisabledReason(result),
            canEscalate: canEscalate(result),
            onEscalate: startEscalationFlow
        )
    }

    @ViewBuilder
    private var detailsDrawer: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if detailsDrawerMode == .manualAdd {
                        manualAddDrawerContent
                    } else if let parseResult {
                        if detailsDrawerMode == .compact {
                            compactDrawerContent(parseResult)
                        } else {
                            fullDrawerContent(parseResult)
                        }
                    } else {
                        Text(L10n.parseFirstHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.parseDetailsTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.doneButton) {
                        isDetailsDrawerPresented = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowCalorieDetailsSheet(_ details: RowCalorieDetails) -> some View {
        let liveDetails = liveRowCalorieDetails(for: details.id, fallback: details)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let imageData = liveDetails.imagePreviewData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    } else if let imageRef = liveDetails.imageRef,
                              !imageRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Food Photo")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Stored as \(imageRef)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.gray.opacity(0.12))
                        )
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(liveDetails.displayName)
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(liveDetails.calories) cal")
                                .font(.title2.weight(.bold))
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 6) {
                            if liveDetails.hasManualOverride {
                                Text("Manual Override")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.orange.opacity(0.15))
                                    )
                            }
                            if !liveDetails.hasManualOverride {
                                Text(liveDetails.itemConfidence == nil ? "Confidence" : "Match Confidence")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(Int((liveDetails.primaryConfidence * 100).rounded()))%")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(liveDetails.primaryConfidence >= 0.7 ? .green : .orange)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Macro Breakdown")
                            .font(.headline)

                        if let protein = liveDetails.protein,
                           let carbs = liveDetails.carbs,
                           let fat = liveDetails.fat {
                            HStack(spacing: 10) {
                                statPill(title: "Calories", value: "\(liveDetails.calories)")
                                statPill(title: "Protein", value: formatOneDecimal(protein) + "g")
                            }
                            HStack(spacing: 10) {
                                statPill(title: "Carbs", value: formatOneDecimal(carbs) + "g")
                                statPill(title: "Fat", value: formatOneDecimal(fat) + "g")
                            }
                        } else {
                            Text("Macro breakdown is not available for this row yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if liveDetails.hasManualOverride {
                        manualOverrideSection(liveDetails)
                    }

                    if shouldShowServingSizeSection(liveDetails) {
                        rowServingSizeSection(liveDetails)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Thought Process")
                                .font(.headline)
                            Spacer()
                            Text(liveDetails.sourceLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.gray.opacity(0.16))
                                )
                        }
                        Text(liveDetails.thoughtProcess)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if shouldShowGeminiSourcesSection(liveDetails) {
                        rowSourcesSection(liveDetails)
                    }

                }
                .padding()
            }
            .navigationTitle("Item Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.doneButton) {
                        selectedRowDetails = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func manualOverrideSection(_ details: RowCalorieDetails) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Manual Override Details")
                    .font(.headline)
                Spacer()
                Text("Provenance")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.gray.opacity(0.16))
                    )
            }

            Text("Reason: Adjusted manually in app.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !details.manualEditedFields.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Edited fields")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(details.manualEditedFields, id: \.self) { field in
                                Text(field)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.primary.opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(Color.orange.opacity(0.18))
                                    )
                            }
                        }
                    }
                }
            }

            if !details.manualOriginalSources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Original source")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(details.manualOriginalSources, id: \.self) { source in
                        Text(source)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.10))
        )
    }

    @ViewBuilder
    private func rowServingSizeSection(_ details: RowCalorieDetails) -> some View {
        let entries = servingSizeEntries(for: details)
        VStack(alignment: .leading, spacing: 10) {
            Text("Serving Size")
                .font(.headline)
            Text("Choose from Food Database serving sizes.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(entries, id: \.offset) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.item.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    let selectedOptionOffset = selectedServingOptionOffset(
                        rowID: details.id,
                        itemOffset: entry.offset,
                        servingOptions: entry.options
                    )
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(entry.options.enumerated()), id: \.offset) { optionOffset, option in
                                let selected = selectedOptionOffset == optionOffset
                                Button {
                                    applyRowServingOption(
                                        rowID: details.id,
                                        itemOffset: entry.offset,
                                        option: option
                                    )
                                } label: {
                                    Text(option.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.9))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule()
                                                .fill(selected ? Color.blue : Color.gray.opacity(0.20))
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Serving option \(optionOffset + 1): \(option.label)"))
                            }
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.10))
                )
            }
        }
    }

    private func shouldShowServingSizeSection(_ details: RowCalorieDetails) -> Bool {
        if normalizedLookupValue(parseResult?.route ?? "") == "gemini" {
            return false
        }
        return !servingSizeEntries(for: details).isEmpty
    }

    private func servingSizeEntries(for details: RowCalorieDetails) -> [(offset: Int, item: ParsedFoodItem, options: [ParsedServingOption])] {
        Array(details.parsedItems.enumerated()).compactMap { itemOffset, item in
            if isGeminiParsedItem(item) {
                return nil
            }
            guard let servingOptions = rowServingOptions(rowID: details.id, itemOffset: itemOffset, fallback: item),
                  !servingOptions.isEmpty else {
                return nil
            }
            return (offset: itemOffset, item: item, options: servingOptions)
        }
    }

    private func isGeminiParsedItem(_ item: ParsedFoodItem) -> Bool {
        let source = normalizedLookupValue(item.nutritionSourceId)
        let family = normalizedLookupValue(item.sourceFamily ?? "")
        return source.contains("gemini") || family == "gemini"
    }

    private func shouldShowGeminiSourcesSection(_ details: RowCalorieDetails) -> Bool {
        let route = normalizedLookupValue(parseResult?.route ?? "")
        if route == "gemini" {
            return true
        }
        if details.parsedItems.contains(where: isGeminiParsedItem) {
            return true
        }
        if let sourcesUsed = parseResult?.sourcesUsed {
            return sourcesUsed.contains { normalizedLookupValue($0) == "gemini" }
        }
        return false
    }

    private func sourceChipsForDetails(_ details: RowCalorieDetails) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        if let sourcesUsed = parseResult?.sourcesUsed {
            for source in sourcesUsed {
                let label = sourceDisplayName(source)
                if seen.insert(label).inserted {
                    ordered.append(label)
                }
            }
        }

        let route = parseResult?.route
        for item in details.parsedItems {
            let label = nutritionSourceDisplayName(item.nutritionSourceId, route: route)
            if seen.insert(label).inserted {
                ordered.append(label)
            }
        }

        return ordered
    }

    private func sourceReferencesForDetails(_ details: RowCalorieDetails) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        for item in details.parsedItems {
            let rawID = item.nutritionSourceId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawID.isEmpty else { continue }
            let label = sourceReferenceLabel(for: rawID)
            if seen.insert(label).inserted {
                ordered.append(label)
            }
        }

        if ordered.isEmpty {
            let chips = sourceChipsForDetails(details)
            for chip in chips where seen.insert(chip).inserted {
                ordered.append(chip)
            }
        }

        return ordered
    }

    private func sourceReferenceLabel(for rawSourceID: String) -> String {
        let normalized = normalizedLookupValue(rawSourceID)
        if normalized.contains("gemini") {
            return "Gemini nutrition estimate"
        }
        if normalized.contains("fatsecret") {
            return "Food Database nutrition match"
        }
        if normalized.contains("cache") {
            return "Cached nutrition result"
        }
        if normalized.contains("manual") {
            return "Manual nutrition edit"
        }
        return rawSourceID
    }

    @ViewBuilder
    private func rowSourcesSection(_ details: RowCalorieDetails) -> some View {
        let chips = sourceChipsForDetails(details)
        let references = sourceReferencesForDetails(details)

        VStack(alignment: .leading, spacing: 10) {
            Text("Sources")
                .font(.headline)
            Text("Nutrition references used for this estimate.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.primary.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(Color.gray.opacity(0.20))
                                )
                        }
                    }
                }
            }

            if !references.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(references, id: \.self) { reference in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                            Text(reference)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.10))
        )
    }

    @ViewBuilder
    private var manualAddDrawerContent: some View {
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
            Button("Back to text mode") {
                inputMode = .text
                detailsDrawerMode = .full
                isDetailsDrawerPresented = false
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var homeStatusStrip: some View {
        HStack(spacing: 10) {
            if let saveSuccessMessage {
                Text(saveSuccessMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            } else if let parseError {
                if isConnectivityParseError(parseError) {
                    Text(L10n.parseConnectivityIssueLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.16))
                        )
                } else {
                    Text(parseError)
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            } else if inputMode != .text {
                Text(modeStatusMessage(inputMode))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                EmptyView()
            }

            Spacer(minLength: 0)
        }
    }

    private func isConnectivityParseError(_ message: String) -> Bool {
        message == L10n.noNetworkParse || message == L10n.parseNetworkFailure
    }

    private func modeStatusMessage(_ mode: HomeInputMode) -> String {
        switch mode {
        case .text:
            return ""
        case .voice:
            return "Voice capture is in progress. You can continue with text right now."
        case .camera:
            if let selectedCameraSource {
                return selectedCameraSource.statusMessage
            }
            return "Choose how you want to add food: take a picture or photo."
        case .manualAdd:
            return "Manual add tools are open in Details."
        }
    }

    private func presentRowDetails(for row: HomeLogRow) {
        guard let details = makeRowCalorieDetails(for: row) else { return }
        selectedRowDetails = details
    }

    private func liveRowCalorieDetails(for rowID: UUID, fallback: RowCalorieDetails) -> RowCalorieDetails {
        guard let row = inputRows.first(where: { $0.id == rowID }),
              let refreshed = makeRowCalorieDetails(for: row) else {
            return fallback
        }
        return refreshed
    }

    private func makeRowCalorieDetails(for row: HomeLogRow) -> RowCalorieDetails? {
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
        let sourceLabel = sourceLabelForRowItems(resolvedItems, route: parseResult?.route)
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
            thoughtProcess: thoughtProcessText(for: row, sourceLabel: sourceLabel, items: resolvedItems),
            parsedItems: resolvedItems,
            manualEditedFields: overridePreview.editedFields,
            manualOriginalSources: overridePreview.originalSources,
            imagePreviewData: row.imagePreviewData,
            imageRef: row.imageRef
        )
    }

    private func manualOverridePreview(for row: HomeLogRow, rowIndex: Int) -> (editedFields: [String], originalSources: [String]) {
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
            } else if item.manualOverride == true || normalizedLookupValue(item.sourceFamily ?? "") == "manual" {
                editedFieldSet.insert("nutrition")
            }

            let originalSourceID = (item.originalNutritionSourceId ?? item.nutritionSourceId)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !originalSourceID.isEmpty {
                originalSourceSet.insert(sourceReferenceLabel(for: originalSourceID))
            }
        }

        return (
            editedFields: Array(editedFieldSet).sorted(),
            originalSources: Array(originalSourceSet).sorted()
        )
    }

    private func resolvedItems(for row: HomeLogRow) -> [ParsedFoodItem] {
        if !row.parsedItems.isEmpty {
            return row.parsedItems
        }
        if let parsedItem = row.parsedItem {
            return [parsedItem]
        }
        return []
    }

    private func rowServingOptions(rowID: UUID, itemOffset: Int, fallback: ParsedFoodItem) -> [ParsedServingOption]? {
        guard let rowIndex = inputRows.firstIndex(where: { $0.id == rowID }),
              inputRows[rowIndex].parsedItems.indices.contains(itemOffset) else {
            return fallback.servingOptions
        }
        return inputRows[rowIndex].parsedItems[itemOffset].servingOptions
    }

    private func applyRowServingOption(rowID: UUID, itemOffset: Int, option: ParsedServingOption) {
        guard let rowIndex = inputRows.firstIndex(where: { $0.id == rowID }) else { return }
        guard inputRows[rowIndex].parsedItems.indices.contains(itemOffset) else { return }
        applyRowParsedItemEdit(rowIndex: rowIndex, itemOffset: itemOffset) { editable in
            editable.applyServingOption(option)
        }
    }

    private func isServingOptionSelected(rowID: UUID, itemOffset: Int, option: ParsedServingOption) -> Bool {
        guard let rowIndex = inputRows.firstIndex(where: { $0.id == rowID }),
              inputRows[rowIndex].parsedItems.indices.contains(itemOffset) else {
            return false
        }
        let rowItem = inputRows[rowIndex].parsedItems[itemOffset]
        let rowSource = normalizedLookupValue(rowItem.nutritionSourceId)
        let optionSource = normalizedLookupValue(option.nutritionSourceId)
        if !rowSource.isEmpty, !optionSource.isEmpty, rowSource != optionSource {
            return false
        }

        let rowQuantity = max(rowItem.quantity, 0.0001)
        let optionQuantity = servingOptionUsesServingBasis(option) ? 1.0 : max(option.quantity, 0.0001)
        let rowGramsPerUnit = rowItem.gramsPerUnit ?? (rowItem.grams / rowQuantity)
        let optionGramsPerUnit = servingOptionUsesServingBasis(option)
            ? option.grams
            : (option.grams / optionQuantity)
        let rowCaloriesPerUnit = rowItem.calories / rowQuantity
        let optionCaloriesPerUnit = servingOptionUsesServingBasis(option)
            ? option.calories
            : (option.calories / optionQuantity)
        let rowProteinPerUnit = rowItem.protein / rowQuantity
        let optionProteinPerUnit = servingOptionUsesServingBasis(option)
            ? option.protein
            : (option.protein / optionQuantity)
        let rowCarbsPerUnit = rowItem.carbs / rowQuantity
        let optionCarbsPerUnit = servingOptionUsesServingBasis(option)
            ? option.carbs
            : (option.carbs / optionQuantity)
        let rowFatPerUnit = rowItem.fat / rowQuantity
        let optionFatPerUnit = servingOptionUsesServingBasis(option)
            ? option.fat
            : (option.fat / optionQuantity)

        return nearlyEqual(rowGramsPerUnit, optionGramsPerUnit, tolerance: 0.2) &&
            nearlyEqual(rowCaloriesPerUnit, optionCaloriesPerUnit, tolerance: 0.2) &&
            nearlyEqual(rowProteinPerUnit, optionProteinPerUnit, tolerance: 0.2) &&
            nearlyEqual(rowCarbsPerUnit, optionCarbsPerUnit, tolerance: 0.2) &&
            nearlyEqual(rowFatPerUnit, optionFatPerUnit, tolerance: 0.2)
    }

    private func servingOptionUsesServingBasis(_ option: ParsedServingOption) -> Bool {
        if abs(option.quantity - 1) > 0.0001 {
            return true
        }
        return isWeightOrVolumeServingUnit(option.unit)
    }

    private func isWeightOrVolumeServingUnit(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "g" || normalized == "gram" || normalized == "grams" ||
            normalized == "ml" || normalized == "milliliter" || normalized == "milliliters" ||
            normalized == "oz" || normalized == "ounce" || normalized == "ounces"
    }

    private func selectedServingOptionOffset(rowID: UUID, itemOffset: Int, servingOptions: [ParsedServingOption]) -> Int? {
        servingOptions.firstIndex { option in
            isServingOptionSelected(rowID: rowID, itemOffset: itemOffset, option: option)
        }
    }

    private func nearlyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private func applyRowParsedItemEdit(
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

    private func editableIndexForRowItem(rowIndex: Int, itemOffset: Int) -> Int? {
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
        let normalizedSource = normalizedLookupValue(rowItem.nutritionSourceId)
        let normalizedName = normalizedLookupValue(rowItem.name)

        if let exact = editableItems.firstIndex(where: { item in
            normalizedLookupValue(item.nutritionSourceId) == normalizedSource &&
                normalizedLookupValue(item.name) == normalizedName
        }) {
            return exact
        }

        if let bySource = editableItems.firstIndex(where: {
            normalizedLookupValue($0.nutritionSourceId) == normalizedSource
        }) {
            return bySource
        }

        if let byName = editableItems.firstIndex(where: {
            normalizedLookupValue($0.name) == normalizedName
        }) {
            return byName
        }

        return nil
    }

    private func recalculateRowNutrition(rowIndex: Int) {
        guard inputRows.indices.contains(rowIndex) else { return }
        let rowItems = inputRows[rowIndex].parsedItems
        guard !rowItems.isEmpty else { return }

        let calories = Int(max(0, rowItems.reduce(0) { $0 + $1.calories }).rounded())
        inputRows[rowIndex].calories = calories
        inputRows[rowIndex].calorieRangeText = inputRows[rowIndex].isApproximate
            ? estimatedCalorieRangeText(for: calories)
            : nil
    }

    private func normalizedLookupValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sourceLabelForRowItems(_ items: [ParsedFoodItem], route: String?) -> String {
        guard !items.isEmpty else {
            return nutritionSourceDisplayName(nil, route: route)
        }

        let labels = Array(Set(items.map { nutritionSourceDisplayName($0.nutritionSourceId, route: route) })).sorted()
        if labels.count == 1, let label = labels.first {
            return label
        }
        return labels.joined(separator: ", ")
    }

    private func nutritionSourceDisplayName(_ nutritionSourceId: String?, route: String?) -> String {
        let upstreamSource = upstreamNutritionSourceDisplayName(nutritionSourceId)

        guard let route else {
            return upstreamSource ?? "Estimate"
        }

        let normalizedRoute = route.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedRoute == "cache" {
            if let upstreamSource {
                return "Cache (\(upstreamSource))"
            }
            return "Cache"
        }

        return upstreamSource ?? L10n.routeDisplayName(route)
    }

    private func upstreamNutritionSourceDisplayName(_ nutritionSourceId: String?) -> String? {
        guard let nutritionSourceId else { return nil }
        let trimmed = nutritionSourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.lowercased()
        if normalized.contains("fatsecret") {
            return "Food Database"
        }
        if normalized.contains("gemini") {
            return "Gemini"
        }
        if normalized.contains("manual") {
            return "Manual"
        }
        if normalized.contains("cache") {
            return "Cache"
        }
        return nil
    }

    private func thoughtProcessText(for row: HomeLogRow, sourceLabel: String, items: [ParsedFoodItem]) -> String {
        let rowText = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if items.count > 1 {
            let itemNames = items.map(\.name)
            let previewNames: String
            if itemNames.count <= 3 {
                previewNames = itemNames.joined(separator: ", ")
            } else {
                previewNames = itemNames.prefix(3).joined(separator: ", ") + " +\(itemNames.count - 3) more"
            }
            let estimatedCalories = Int(items.reduce(0) { $0 + $1.calories }.rounded())
            var thought = "Interpreted “\(rowText)” as multiple items: \(previewNames). "
            thought += "Used \(sourceLabel) nutrition data to estimate \(estimatedCalories) kcal total."
            if row.isApproximate || (parseResult?.needsClarification == true) {
                thought += " This is marked as approximate because confidence is below the strict threshold."
            }
            return thought
        }

        if let item = items.first {
            if let explanation = item.explanation, !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return explanation
            }
            var thought = "Interpreted “\(rowText)” as “\(item.name)”. "
            thought += "Used \(formatOneDecimal(item.quantity)) \(item.unit) (~\(formatOneDecimal(item.grams)) g) "
            thought += "with \(sourceLabel) nutrition data to estimate \(Int(item.calories.rounded())) kcal and scale macros."
            if row.isApproximate || (parseResult?.needsClarification == true) {
                thought += " This is marked as approximate because confidence is below the strict threshold."
            }
            return thought
        }

        var fallback = "A calorie estimate is available for this row, but no fully matched nutrition item was retained."
        fallback += " Re-parse or open Parse Details to refine mapping and macro breakdown."
        return fallback
    }

    private func handleCameraSourceSelection(_ source: CameraInputSource) {
        selectedCameraSource = source
        inputMode = .camera
        switch source {
        case .takePicture:
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                parseError = "Camera is unavailable on this device."
                inputMode = .text
                return
            }
            imagePickerSourceType = .camera
        case .photo:
            imagePickerSourceType = .photoLibrary
        }
        isImagePickerPresented = true
    }

    @MainActor
    private func handlePickedImage(_ image: UIImage) async {
        isImagePickerPresented = false
        debounceTask?.cancel()
        parseTask?.cancel()
        autoSaveTask?.cancel()
        parseRequestSequence += 1

        guard let prepared = prepareImagePayload(from: image) else {
            parseError = "Unable to process this image. Please try another photo."
            inputMode = .text
            selectedCameraSource = nil
            return
        }

        if flowStartedAt == nil {
            let now = Date()
            flowStartedAt = now
            draftLoggedAt = now
        }
        if draftLoggedAt == nil {
            draftLoggedAt = Date()
        }

        pendingImageData = prepared.uploadData
        pendingImagePreviewData = prepared.previewData
        pendingImageMimeType = prepared.mimeType
        pendingImageStorageRef = nil
        latestParseInputKind = "image"

        parseInfoMessage = "Analyzing photo…"
        parseError = nil
        saveError = nil
        saveSuccessMessage = nil
        escalationError = nil
        escalationInfoMessage = nil
        escalationBlockedCode = nil
        clearPendingSaveContext()
        appStore.setError(nil)

        parseInFlightCount += 1
        let startedAt = Date()
        defer {
            parseInFlightCount = max(0, parseInFlightCount - 1)
            inputMode = .text
            selectedCameraSource = nil
        }

        do {
            let response = try await appStore.apiClient.parseImageLog(
                imageData: prepared.uploadData,
                mimeType: prepared.mimeType,
                loggedAt: Self.loggedAtFormatter.string(from: draftLoggedAt ?? Date())
            )
            let durationMs = elapsedMs(since: startedAt)

            var rowText = (response.extractedText ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if rowText.isEmpty {
                rowText = response.items.map(\.name).joined(separator: ", ")
            }
            if rowText.isEmpty {
                rowText = "Photo meal"
            }

            var row = HomeLogRow.empty()
            row.text = rowText
            row.imagePreviewData = prepared.previewData
            row.imageRef = pendingImageStorageRef
            suppressDebouncedParseOnce = true
            inputRows = [row]

            parseResult = response
            latestParseInputKind = normalizedInputKind(response.inputKind, fallback: "image")
            editableItems = response.items.map(EditableParsedItem.init(apiItem:))
            applyRowParseResult(response)
            if inputRows.indices.contains(0) {
                inputRows[0].imagePreviewData = prepared.previewData
                inputRows[0].imageRef = pendingImageStorageRef
            }
            parseInfoMessage = nil
            parseError = nil
            saveError = nil
            appStore.setError(nil)
            scheduleDetailsDrawer(for: response)
            emitParseTelemetrySuccess(response: response, durationMs: durationMs, uiApplied: true)
            scheduleAutoSave()
        } catch {
            let durationMs = elapsedMs(since: startedAt)
            handleAuthFailureIfNeeded(error)
            parseInfoMessage = nil
            parseError = userFriendlyParseError(error)
            appStore.setError(parseError)
            emitParseTelemetryFailure(error: error, durationMs: durationMs, uiApplied: true)
        }
    }

    private func clearImageContext() {
        pendingImageData = nil
        pendingImagePreviewData = nil
        pendingImageMimeType = nil
        pendingImageStorageRef = nil
        latestParseInputKind = "text"
        selectedCameraSource = nil
        for index in inputRows.indices {
            inputRows[index].imagePreviewData = nil
            inputRows[index].imageRef = nil
        }
    }

    private func prepareImagePayload(from image: UIImage) -> PreparedImagePayload? {
        let resized = resizeImageIfNeeded(image, maxDimension: 1600)
        let qualityAttempts: [CGFloat] = [0.86, 0.78, 0.70, 0.62, 0.55]
        let maxBytes = 5_800_000

        for quality in qualityAttempts {
            guard let data = resized.jpegData(compressionQuality: quality) else {
                continue
            }
            if data.count <= maxBytes {
                return PreparedImagePayload(uploadData: data, previewData: data, mimeType: "image/jpeg")
            }
        }

        guard let fallbackData = resized.jpegData(compressionQuality: 0.5) else {
            return nil
        }
        return PreparedImagePayload(uploadData: fallbackData, previewData: fallbackData, mimeType: "image/jpeg")
    }

    private func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else {
            return image
        }

        let scale = maxDimension / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    @ViewBuilder
    private func compactDrawerContent(_ parseResult: ParseLogResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Confirmation")
                .font(.headline)
            HStack(spacing: 0) {
                Text("Confidence: ")
                RollingNumberText(value: parseResult.confidence, fractionDigits: 3)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            HM03ParseSummarySection(
                totals: displayedTotals,
                hasEditedItems: !editableItems.isEmpty
            )

            HStack(spacing: 12) {
                Button(L10n.saveLogButton) {
                    startSaveFlow()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isSaving || buildSaveDraftRequest() == nil || parseResult.needsClarification)

                Button("Open Full Details") {
                    detailsDrawerMode = .full
                }
                .buttonStyle(.bordered)
            }

            if parseResult.needsClarification {
                Text(L10n.saveDisabledNeedsClarification)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func fullDrawerContent(_ parseResult: ParseLogResponse) -> some View {
        HM03ParseSummarySection(
            totals: displayedTotals,
            hasEditedItems: !editableItems.isEmpty
        )

        parseMetaCard(parseResult)

        parseActionSection

        if let parseError {
            Text(parseError)
                .font(.footnote)
                .foregroundStyle(.red)
        }

        daySummarySection

        Group {
            Text(L10n.parseMetadataTitle)
                .font(.headline)
            Text(L10n.routeLabel(parseResult.route))
                .font(.footnote)
            Text(L10n.parseRequestIDLabel(parseResult.parseRequestId))
                .font(.footnote)
            Text(L10n.parseVersionLabel(parseResult.parseVersion))
                .font(.footnote)
            HStack(spacing: 0) {
                Text("\(L10n.confidenceLabel): ")
                RollingNumberText(value: parseResult.confidence, fractionDigits: 3)
            }
            .font(.footnote)
        }
        .foregroundStyle(.secondary)

        if parseResult.needsClarification {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.clarificationQuestionsTitle)
                    .font(.headline)
                ForEach(Array(parseResult.clarificationQuestions.enumerated()), id: \.offset) { _, question in
                    Text("• \(question)")
                        .font(.footnote)
                }
            }
        }

        clarificationEscalationSection(parseResult)

        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.editableItemsTitle)
                .font(.headline)
            ForEach($editableItems) { $item in
                VStack(alignment: .leading, spacing: 8) {
                    TextField(L10n.itemNamePlaceholder, text: $item.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Stepper(
                        value: Binding(
                            get: { item.quantity },
                            set: { item.updateQuantity($0) }
                        ),
                        in: 0 ... 20,
                        step: 0.5
                    ) {
                        Text(L10n.quantityLabel(item.quantity))
                            .font(.footnote)
                    }

                    TextField(L10n.unitPlaceholder, text: $item.unit)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack(spacing: 2) {
                        RollingNumberText(value: Double(Int(item.calories.rounded())), suffix: " kcal")
                        Text("• P ")
                        RollingNumberText(value: item.protein, fractionDigits: 1, suffix: "g")
                        Text(" • C ")
                        RollingNumberText(value: item.carbs, fractionDigits: 1, suffix: "g")
                        Text(" • F ")
                        RollingNumberText(value: item.fat, fractionDigits: 1, suffix: "g")
                    }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.08))
                )
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.saveActionsTitle)
                .font(.headline)

            HStack(spacing: 12) {
                Button(L10n.saveLogButton) {
                    startSaveFlow()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isSaving || buildSaveDraftRequest() == nil || parseResult.needsClarification)

                Button(L10n.retryLastSaveButton) {
                    retryLastSave()
                }
                .buttonStyle(.bordered)
                .disabled(isSaving || pendingSaveRequest == nil || pendingSaveIdempotencyKey == nil)
            }

            if parseResult.needsClarification {
                Text(L10n.saveDisabledNeedsClarification)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let saveSuccessMessage {
                Text(saveSuccessMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }

            if let saveError {
                Text(saveError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let pendingSaveIdempotencyKey {
                Text(L10n.idempotencyKey(pendingSaveIdempotencyKey.uuidString.lowercased()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.saveContractPreviewTitle)
                .font(.headline)
            Text(saveDraftPreviewJSON())
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.05))
                )
        }
    }

    @MainActor
    private func scheduleDebouncedParse(for newValue: String) {
        debounceTask?.cancel()
        parseTask?.cancel()
        autoSaveTask?.cancel()
        parseError = nil
        parseInfoMessage = nil
        saveError = nil
        escalationError = nil
        escalationInfoMessage = nil
        escalationBlockedCode = nil

        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parseResult = nil
            editableItems = []
            isEscalating = false
            rowsPendingParseIDs = []
            flowStartedAt = nil
            draftLoggedAt = nil
            lastTimeToLogMs = nil
            lastAutoSavedContentFingerprint = nil
            inputRows = [HomeLogRow.empty()]
            clearImageContext()
            clearPendingSaveContext()
            return
        }

        if flowStartedAt == nil {
            let now = Date()
            flowStartedAt = now
            draftLoggedAt = now
        }
        if draftLoggedAt == nil {
            draftLoggedAt = Date()
        }

        if shouldDeferDebouncedParse(for: newValue) {
            rowsPendingParseIDs = []
            clearRowLoadingState()
            return
        }

        rowsPendingParseIDs = rowsPendingParseIDsForCurrentInput()
        guard !rowsPendingParseIDs.isEmpty else {
            clearRowLoadingState()
            return
        }

        parseRequestSequence += 1
        let requestSequence = parseRequestSequence
        markRowsLoadingForCurrentInput()

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                parseTask?.cancel()
                parseTask = Task { @MainActor in
                    await parseCurrentText(trimmed, requestSequence: requestSequence)
                }
            }
        }
    }

    @MainActor
    private func triggerParseNow() {
        debounceTask?.cancel()
        parseTask?.cancel()
        let trimmed = trimmedNoteText
        guard !trimmed.isEmpty else { return }
        if flowStartedAt == nil {
            let now = Date()
            flowStartedAt = now
            draftLoggedAt = now
        }
        if draftLoggedAt == nil {
            draftLoggedAt = Date()
        }

        rowsPendingParseIDs = rowsPendingParseIDsForCurrentInput()
        guard !rowsPendingParseIDs.isEmpty else {
            clearRowLoadingState()
            return
        }

        parseRequestSequence += 1
        let requestSequence = parseRequestSequence
        markRowsLoadingForCurrentInput()

        parseTask = Task { @MainActor in
            await parseCurrentText(trimmed, requestSequence: requestSequence)
        }
    }

    @MainActor
    private func parseCurrentText(_ text: String, requestSequence: Int) async {
        let activeText = trimmedNoteText
        guard !activeText.isEmpty else { return }
        guard requestSequence == parseRequestSequence else { return }
        guard appStore.isNetworkReachable else {
            parseInfoMessage = nil
            parseError = L10n.noNetworkParse
            clearRowLoadingState()
            return
        }
        let startedAt = Date()
        parseInFlightCount += 1
        defer { parseInFlightCount = max(0, parseInFlightCount - 1) }

        let request = ParseLogRequest(
            text: text,
            loggedAt: Self.loggedAtFormatter.string(from: draftLoggedAt ?? Date())
        )

        do {
            let response = try await appStore.apiClient.parseLog(request)
            let durationMs = elapsedMs(since: startedAt)
#if DEBUG
            if let cacheDebug = response.cacheDebug {
                print("[parse_cache_debug] route=\(response.route) cacheHit=\(response.cacheHit) scope=\(cacheDebug.scope) hash=\(cacheDebug.textHash) normalized=\(cacheDebug.normalizedText)")
            } else {
                print("[parse_cache_debug] route=\(response.route) cacheHit=\(response.cacheHit)")
            }
#endif
            if requestSequence != parseRequestSequence || text != trimmedNoteText {
                emitParseTelemetrySuccess(response: response, durationMs: durationMs, uiApplied: false)
                return
            }

            if shouldHoldUnresolvedResponse(response) {
                rowsPendingParseIDs = []
                clearRowLoadingState()
                parseInfoMessage = L10n.parseStillProcessingLabel
                parseError = nil
                appStore.setError(nil)
                emitParseTelemetrySuccess(response: response, durationMs: durationMs, uiApplied: false)
                return
            }

            parseResult = response
            latestParseInputKind = normalizedInputKind(response.inputKind, fallback: "text")
            editableItems = response.items.map(EditableParsedItem.init(apiItem:))
            applyRowParseResult(response)
            parseInfoMessage = nil
            parseError = nil
            saveError = nil
            escalationError = nil
            escalationInfoMessage = nil
            escalationBlockedCode = nil
            clearPendingSaveContext()
            rowsPendingParseIDs = []
            appStore.setError(nil)
            scheduleDetailsDrawer(for: response)
            emitParseTelemetrySuccess(response: response, durationMs: durationMs, uiApplied: true)
            scheduleAutoSave()
        } catch {
            let durationMs = elapsedMs(since: startedAt)
            if error is CancellationError || Task.isCancelled {
                return
            }
            if requestSequence != parseRequestSequence || text != trimmedNoteText {
                emitParseTelemetryFailure(error: error, durationMs: durationMs, uiApplied: false)
                return
            }
            handleAuthFailureIfNeeded(error)
            rowsPendingParseIDs = []
            clearRowLoadingState()
            let message = userFriendlyParseError(error)
            parseInfoMessage = nil
            parseError = message
            appStore.setError(message)
            emitParseTelemetryFailure(error: error, durationMs: durationMs, uiApplied: true)
        }
    }

    private func shouldHoldUnresolvedResponse(_ response: ParseLogResponse) -> Bool {
        guard response.items.isEmpty else { return false }
        return response.route == "unresolved" || response.route == "gemini"
    }

    private func shouldDeferDebouncedParse(for rawText: String) -> Bool {
        guard rawText.contains("\n") else { return false }
        let lines = rawText.components(separatedBy: .newlines)
        guard let lastLine = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines), !lastLine.isEmpty else {
            return false
        }

        let sanitized = lastLine.replacingOccurrences(of: "[,;:]+$", with: "", options: .regularExpression)
        return sanitized.range(of: #"^\d+(?:[./]\d+)?$"#, options: .regularExpression) != nil
    }

    private func markRowsLoadingForCurrentInput() {
        let pendingIDs = rowsPendingParseIDs.isEmpty ? rowsPendingParseIDsForCurrentInput() : rowsPendingParseIDs
        for index in inputRows.indices {
            let shouldShowLoading = pendingIDs.contains(inputRows[index].id)
            if shouldShowLoading {
                if !inputRows[index].isLoading {
                    inputRows[index].loadingStatusStartedAt = Date()
                }
                inputRows[index].isLoading = true
                inputRows[index].loadingRouteHint = HomeLogRow.predictedLoadingRouteHint(for: inputRows[index].text)
                if inputRows[index].loadingStatusStartedAt == nil {
                    inputRows[index].loadingStatusStartedAt = Date()
                }
            } else {
                inputRows[index].isLoading = false
                inputRows[index].loadingRouteHint = nil
                inputRows[index].loadingStatusStartedAt = nil
            }
        }
    }

    private func clearRowLoadingState() {
        for index in inputRows.indices {
            inputRows[index].isLoading = false
            inputRows[index].loadingRouteHint = nil
            inputRows[index].loadingStatusStartedAt = nil
        }
    }

    private func rowsPendingParseIDsForCurrentInput() -> Set<UUID> {
        var pending: Set<UUID> = []
        for row in inputRows {
            if rowNeedsFreshParse(row) {
                pending.insert(row.id)
            }
        }
        return pending
    }

    private func rowNeedsFreshParse(_ row: HomeLogRow) -> Bool {
        let normalizedCurrentText = normalizedRowText(row.text)
        guard !normalizedCurrentText.isEmpty else {
            return false
        }

        if let normalizedTextAtParse = row.normalizedTextAtParse {
            return normalizedTextAtParse != normalizedCurrentText
        }

        if row.calories != nil {
            return false
        }

        // Row has content but no parse snapshot yet.
        return row.parsedItem == nil && row.parsedItems.isEmpty
    }

    private func applyRowParseResult(_ response: ParseLogResponse) {
        let rowIndicesMarkedLoading = Set(inputRows.indices.filter { inputRows[$0].isLoading })
        clearRowLoadingState()
        let geminiAuthoritative = isGeminiAuthoritativeResponse(response)
        let approximateDisplay = response.needsClarification || response.confidence < 0.70

        let nonEmptyIndices = inputRows.indices.filter {
            !inputRows[$0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !nonEmptyIndices.isEmpty else { return }

        let rowsNeedingFreshMapping: Set<Int> = Set(nonEmptyIndices.filter { rowIndex in
            if rowIndicesMarkedLoading.contains(rowIndex) {
                return true
            }
            let row = inputRows[rowIndex]
            let normalized = normalizedRowText(row.text)
            guard !normalized.isEmpty else { return false }
            if row.normalizedTextAtParse == nil { return true }
            if row.normalizedTextAtParse != normalized { return true }
            return row.calories == nil || (row.parsedItem == nil && row.parsedItems.isEmpty)
        })

        let lockedRowIndices: Set<Int> = Set(nonEmptyIndices.filter { rowIndex in
            guard let existingCalories = inputRows[rowIndex].calories, existingCalories > 0 else {
                return false
            }
            let normalized = normalizedRowText(inputRows[rowIndex].text)
            guard !normalized.isEmpty else { return false }
            return inputRows[rowIndex].normalizedTextAtParse == normalized
        })

        for rowIndex in nonEmptyIndices where rowsNeedingFreshMapping.contains(rowIndex) && !lockedRowIndices.contains(rowIndex) {
            inputRows[rowIndex].calories = nil
            inputRows[rowIndex].calorieRangeText = nil
            inputRows[rowIndex].isApproximate = false
            inputRows[rowIndex].parsedItem = nil
            inputRows[rowIndex].parsedItems = []
            inputRows[rowIndex].editableItemIndices = []
            inputRows[rowIndex].normalizedTextAtParse = nil
        }
        var mappedCaloriesByRow: [Int: Int] = [:]
        var mappedItemsByRow: [Int: ParsedFoodItem] = [:]
        var mappedItemOffsetsByRow: [Int: Int] = [:]
        var usedItemOffsets: Set<Int> = []

        // Gemini-authoritative mode: preserve input ordering and map directly in order.
        if geminiAuthoritative {
            let assignCount = min(nonEmptyIndices.count, response.items.count)
            for offset in 0..<assignCount {
                let rowIndex = nonEmptyIndices[offset]
                let itemOffset = offset
                guard let normalizedCalories = normalizedRowCalories(
                    from: response.items[itemOffset].calories,
                    response: response
                ) else {
                    continue
                }
                mappedCaloriesByRow[rowIndex] = normalizedCalories
                mappedItemsByRow[rowIndex] = response.items[itemOffset]
                mappedItemOffsetsByRow[rowIndex] = itemOffset
                usedItemOffsets.insert(itemOffset)
            }
        } else if nonEmptyIndices.count == response.items.count {
            // Non-Gemini mode: in-order assignment only when parser rows line up with UI rows.
            for (itemOffset, rowIndex) in nonEmptyIndices.enumerated() {
                guard let normalizedCalories = normalizedRowCalories(
                    from: response.items[itemOffset].calories,
                    response: response
                ) else {
                    continue
                }
                mappedCaloriesByRow[rowIndex] = normalizedCalories
                mappedItemsByRow[rowIndex] = response.items[itemOffset]
                mappedItemOffsetsByRow[rowIndex] = itemOffset
                usedItemOffsets.insert(itemOffset)
            }
        }

        // Second attempt: best-match remap for parser-expanded or parser-collapsed responses.
        for rowIndex in nonEmptyIndices where mappedCaloriesByRow[rowIndex] == nil {
            let rowText = inputRows[rowIndex].text
            var bestOffset: Int?
            var bestScore = 0.0

            for (itemOffset, item) in response.items.enumerated() where !usedItemOffsets.contains(itemOffset) {
                let score = rowItemMatchScore(rowText: rowText, itemName: item.name)
                if score > bestScore {
                    bestScore = score
                    bestOffset = itemOffset
                }
            }

            let bestMatchThreshold = geminiAuthoritative ? 0.20 : 0.35
            if let bestOffset, bestScore >= bestMatchThreshold {
                if let normalizedCalories = normalizedRowCalories(
                    from: response.items[bestOffset].calories,
                    response: response
                ) {
                    mappedCaloriesByRow[rowIndex] = normalizedCalories
                    mappedItemsByRow[rowIndex] = response.items[bestOffset]
                    mappedItemOffsetsByRow[rowIndex] = bestOffset
                    usedItemOffsets.insert(bestOffset)
                }
            }
        }

        // Final fallback: assign remaining parser items in order only for high-confidence non-Gemini routes.
        // For Gemini/clarification flows this can create misleading duplicated values across rows.
        let unmatchedRowIndices = nonEmptyIndices.filter {
            rowsNeedingFreshMapping.contains($0) && mappedCaloriesByRow[$0] == nil
        }
        let remainingItemOffsets = response.items.indices.filter { !usedItemOffsets.contains($0) }
        let canUseSequentialFallback = !geminiAuthoritative && !response.needsClarification && response.confidence >= 0.75
        if canUseSequentialFallback, !unmatchedRowIndices.isEmpty, !remainingItemOffsets.isEmpty {
            let assignCount = min(unmatchedRowIndices.count, remainingItemOffsets.count)
            for offset in 0..<assignCount {
                let rowIndex = unmatchedRowIndices[offset]
                let itemOffset = remainingItemOffsets[offset]
                guard let normalizedCalories = normalizedRowCalories(
                    from: response.items[itemOffset].calories,
                    response: response
                ) else {
                    continue
                }
                mappedCaloriesByRow[rowIndex] = normalizedCalories
                mappedItemsByRow[rowIndex] = response.items[itemOffset]
                mappedItemOffsetsByRow[rowIndex] = itemOffset
                usedItemOffsets.insert(itemOffset)
            }
        }

        debugRowParseMapping(
            response: response,
            nonEmptyIndices: nonEmptyIndices,
            rowsNeedingFreshMapping: rowsNeedingFreshMapping,
            lockedRowIndices: lockedRowIndices,
            mappedCaloriesByRow: mappedCaloriesByRow
        )

        for rowIndex in nonEmptyIndices where rowsNeedingFreshMapping.contains(rowIndex) {
            if let mapped = mappedCaloriesByRow[rowIndex] {
                if lockedRowIndices.contains(rowIndex) {
                    continue
                }
                inputRows[rowIndex].calories = mapped
                inputRows[rowIndex].isApproximate = approximateDisplay
                inputRows[rowIndex].calorieRangeText = approximateDisplay ? estimatedCalorieRangeText(for: mapped) : nil
                inputRows[rowIndex].parsedItem = mappedItemsByRow[rowIndex]
                inputRows[rowIndex].parsedItems = mappedItemsByRow[rowIndex].map { [$0] } ?? []
                inputRows[rowIndex].editableItemIndices = mappedItemOffsetsByRow[rowIndex].map { [$0] } ?? []
                inputRows[rowIndex].normalizedTextAtParse = normalizedRowText(inputRows[rowIndex].text)
            }
        }

        if nonEmptyIndices.count == 1,
           let normalizedTotalsCalories = normalizedRowCalories(from: response.totals.calories, response: response) {
            let onlyRowIndex = nonEmptyIndices[0]
            if rowsNeedingFreshMapping.contains(onlyRowIndex) {
                inputRows[onlyRowIndex].calories = normalizedTotalsCalories
                inputRows[onlyRowIndex].isApproximate = approximateDisplay
                inputRows[onlyRowIndex].calorieRangeText = approximateDisplay
                    ? estimatedCalorieRangeText(for: normalizedTotalsCalories)
                    : nil
                if let firstItem = response.items.first {
                    inputRows[onlyRowIndex].parsedItem = firstItem
                }
                inputRows[onlyRowIndex].parsedItems = response.items
                inputRows[onlyRowIndex].editableItemIndices = Array(response.items.indices)
                inputRows[onlyRowIndex].normalizedTextAtParse = normalizedRowText(inputRows[onlyRowIndex].text)
            }
        }
    }

    private func estimatedCalorieRangeText(for calories: Int) -> String {
        let lower = max(0, Int((Double(calories) * 0.8).rounded()))
        let upper = max(lower + 1, Int((Double(calories) * 1.2).rounded()))
        return "\(lower)-\(upper) cal"
    }

    private func normalizedRowCalories(from rawCalories: Double, response: ParseLogResponse) -> Int? {
        let rounded = Int(rawCalories.rounded())
        guard rounded >= 0 else {
            return nil
        }

        // Keep non-Gemini clarification rows from showing empty zero values.
        if response.needsClarification && rounded == 0 && !isGeminiAuthoritativeResponse(response) {
            return nil
        }

        return rounded
    }

    private func isGeminiAuthoritativeResponse(_ response: ParseLogResponse) -> Bool {
        response.route == "gemini" && !response.items.isEmpty
    }

    private func rowItemMatchScore(rowText: String, itemName: String) -> Double {
        let rowTokens = Set(normalizedMatchTokens(from: rowText))
        let itemTokens = Set(normalizedMatchTokens(from: itemName))
        guard !rowTokens.isEmpty, !itemTokens.isEmpty else { return 0.0 }

        let exactIntersection = rowTokens.intersection(itemTokens).count
        var weightedIntersection = Double(exactIntersection)

        // Typo-tolerant fuzzy token match (e.g. "cofeee" ~= "coffee") while keeping one-to-one alignment.
        var unmatchedItemTokens = itemTokens.subtracting(rowTokens)
        for rowToken in rowTokens.subtracting(itemTokens) {
            var bestItemToken: String?
            var bestSimilarity = 0.0
            for itemToken in unmatchedItemTokens {
                let similarity = fuzzyTokenSimilarity(rowToken, itemToken)
                if similarity > bestSimilarity {
                    bestSimilarity = similarity
                    bestItemToken = itemToken
                }
            }
            if let bestItemToken, bestSimilarity >= 0.80 {
                weightedIntersection += 0.75
                unmatchedItemTokens.remove(bestItemToken)
            }
        }

        let union = Double(rowTokens.count + itemTokens.count) - weightedIntersection
        guard union > 0 else { return 0.0 }

        let jaccard = weightedIntersection / union
        let rowCoverage = weightedIntersection / Double(rowTokens.count)
        let itemCoverage = weightedIntersection / Double(itemTokens.count)

        var score = max(jaccard, max(rowCoverage * 0.72, itemCoverage * 0.88))

        if itemCoverage == 1.0 || rowCoverage == 1.0 {
            score += 0.15
        }

        let normalizedRow = rowTokens.sorted().joined(separator: " ")
        let normalizedItem = itemTokens.sorted().joined(separator: " ")
        if normalizedRow.contains(normalizedItem) || normalizedItem.contains(normalizedRow) {
            score += 0.10
        }

        return min(score, 1.0)
    }

    private func fuzzyTokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs {
            return 1.0
        }
        if lhs.count < 3 || rhs.count < 3 {
            return 0.0
        }

        if lhs.contains(rhs) || rhs.contains(lhs) {
            return Double(min(lhs.count, rhs.count)) / Double(max(lhs.count, rhs.count))
        }

        let distance = levenshteinDistance(lhs, rhs)
        let maxLength = max(lhs.count, rhs.count)
        guard maxLength > 0 else { return 0.0 }
        return max(0, 1.0 - Double(distance) / Double(maxLength))
    }

    private func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        if lhs == rhs {
            return 0
        }

        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        if lhsChars.isEmpty {
            return rhsChars.count
        }
        if rhsChars.isEmpty {
            return lhsChars.count
        }

        var previous = Array(0 ... rhsChars.count)
        for (lhsIndex, lhsChar) in lhsChars.enumerated() {
            var current = Array(repeating: 0, count: rhsChars.count + 1)
            current[0] = lhsIndex + 1

            for (rhsIndex, rhsChar) in rhsChars.enumerated() {
                let insertion = current[rhsIndex] + 1
                let deletion = previous[rhsIndex + 1] + 1
                let substitution = previous[rhsIndex] + (lhsChar == rhsChar ? 0 : 1)
                current[rhsIndex + 1] = min(insertion, min(deletion, substitution))
            }
            previous = current
        }

        return previous[rhsChars.count]
    }

    private func normalizedMatchTokens(from text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }

    private func normalizedRowText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func debugRowParseMapping(
        response: ParseLogResponse,
        nonEmptyIndices: [Int],
        rowsNeedingFreshMapping: Set<Int>,
        lockedRowIndices: Set<Int>,
        mappedCaloriesByRow: [Int: Int]
    ) {
#if DEBUG
        let rowSummary = nonEmptyIndices.map { rowIndex in
            let action = rowsNeedingFreshMapping.contains(rowIndex) ? "update" : "keep"
            let lockState = lockedRowIndices.contains(rowIndex) ? "locked" : "free"
            let mapped = mappedCaloriesByRow[rowIndex].map(String.init) ?? "nil"
            let normalized = normalizedRowText(inputRows[rowIndex].text)
            return "#\(rowIndex){action=\(action),lock=\(lockState),mapped=\(mapped),text=\(normalized)}"
        }.joined(separator: " | ")
        print("[parse_row_map] route=\(response.route) confidence=\(String(format: "%.3f", response.confidence)) rows=\(rowSummary)")
#endif
    }

    private func scheduleDetailsDrawer(for response: ParseLogResponse) {
        if response.needsClarification || response.confidence < 0.60 {
            detailsDrawerMode = .full
            return
        }

        if response.confidence < 0.85 {
            detailsDrawerMode = .compact
            return
        }

        detailsDrawerMode = .full
    }

    private func presentDetailsFromDock() {
        guard let parseResult else {
            detailsDrawerMode = .full
            isDetailsDrawerPresented = true
            return
        }
        scheduleDetailsDrawer(for: parseResult)
        isDetailsDrawerPresented = true
    }

    private func canEscalate(_ result: ParseLogResponse) -> Bool {
        guard appStore.isNetworkReachable else { return false }
        guard result.needsClarification else { return false }
        guard !isEscalating else { return false }
        if result.budget.escalationAllowed == false {
            return false
        }
        if escalationBlockedCode == "ESCALATION_DISABLED" || escalationBlockedCode == "BUDGET_EXCEEDED" {
            return false
        }
        return true
    }

    private func escalationDisabledReason(_ result: ParseLogResponse) -> String? {
        if result.budget.escalationAllowed == false || escalationBlockedCode == "BUDGET_EXCEEDED" {
            return L10n.escalationBudgetReason
        }
        if escalationBlockedCode == "ESCALATION_DISABLED" {
            return L10n.escalationConfigReason
        }
        return nil
    }

    private func startEscalationFlow() {
        guard appStore.isNetworkReachable else {
            escalationError = L10n.noNetworkEscalate
            return
        }
        guard let parseResult else {
            escalationError = L10n.parseBeforeEscalation
            return
        }

        guard parseResult.needsClarification else {
            escalationError = L10n.escalationNotRequired
            return
        }

        if parseResult.budget.escalationAllowed == false {
            escalationBlockedCode = "BUDGET_EXCEEDED"
            escalationError = L10n.escalationBudgetBlocked
            return
        }

        Task {
            await escalateCurrentParse(parseResult)
        }
    }

    private func escalateCurrentParse(_ current: ParseLogResponse) async {
        isEscalating = true
        escalationError = nil
        escalationInfoMessage = nil
        defer { isEscalating = false }

        let request = EscalateParseRequest(
            parseRequestId: current.parseRequestId,
            loggedAt: current.loggedAt
        )

        do {
            let response = try await appStore.apiClient.escalateParse(request)
            parseResult = ParseLogResponse(
                requestId: response.requestId,
                parseRequestId: response.parseRequestId,
                parseVersion: response.parseVersion,
                route: response.route,
                cacheHit: false,
                sourcesUsed: response.sourcesUsed,
                fallbackUsed: false,
                fallbackModel: response.model,
                budget: response.budget,
                needsClarification: false,
                clarificationQuestions: [],
                parseDurationMs: response.parseDurationMs,
                loggedAt: response.loggedAt,
                confidence: response.confidence,
                totals: response.totals,
                items: response.items,
                assumptions: [],
                cacheDebug: nil,
                inputKind: "text",
                extractedText: nil,
                imageMeta: nil,
                visionModel: nil,
                visionFallbackUsed: nil
            )
            editableItems = response.items.map(EditableParsedItem.init(apiItem:))
            if let parseResult {
                applyRowParseResult(parseResult)
            }
            parseInfoMessage = nil
            parseError = nil
            escalationBlockedCode = nil
            escalationError = nil
            escalationInfoMessage = L10n.escalationCompleted
            clearPendingSaveContext()
            appStore.setError(nil)
        } catch {
            handleAuthFailureIfNeeded(error)
            let mapped = userFriendlyEscalationError(error)
            escalationBlockedCode = mapped.blockCode
            escalationError = mapped.message
            escalationInfoMessage = nil
            appStore.setError(mapped.message)
        }
    }

    private var displayedTotals: NutritionTotals {
        if editableItems.isEmpty {
            return parseResult?.totals ?? NutritionTotals(calories: 0, protein: 0, carbs: 0, fat: 0)
        }

        let calories = editableItems.reduce(0.0) { $0 + $1.calories }
        let protein = editableItems.reduce(0.0) { $0 + $1.protein }
        let carbs = editableItems.reduce(0.0) { $0 + $1.carbs }
        let fat = editableItems.reduce(0.0) { $0 + $1.fat }
        return NutritionTotals(
            calories: roundOneDecimal(calories),
            protein: roundOneDecimal(protein),
            carbs: roundOneDecimal(carbs),
            fat: roundOneDecimal(fat)
        )
    }

    private func buildSaveDraftRequest() -> SaveLogRequest? {
        guard let parseResult else { return nil }
        let rawText = trimmedNoteText
        guard !rawText.isEmpty else { return nil }
        let effectiveLoggedAt = Self.loggedAtFormatter.string(from: draftLoggedAt ?? Date())
        let inputKind = normalizedInputKind(parseResult.inputKind, fallback: latestParseInputKind)
        let currentImageRef = pendingImageStorageRef ??
            inputRows.compactMap(\.imageRef).first

        return SaveLogRequest(
            parseRequestId: parseResult.parseRequestId,
            parseVersion: parseResult.parseVersion,
            parsedLog: SaveLogBody(
                rawText: rawText,
                loggedAt: effectiveLoggedAt,
                inputKind: inputKind,
                imageRef: currentImageRef,
                confidence: parseResult.confidence,
                totals: displayedTotals,
                sourcesUsed: parseResult.sourcesUsed,
                items: editableItems.map { $0.asSaveParsedFoodItem() }
            )
        )
    }

    private enum SaveIntent {
        case manual
        case retry
        case auto
    }

    private func startSaveFlow() {
        guard appStore.isNetworkReachable else {
            saveError = L10n.noNetworkSave
            return
        }
        guard parseResult?.needsClarification != true else {
            saveError = L10n.parseNeedsClarificationBeforeSave
            return
        }

        guard let request = buildSaveDraftRequest() else {
            saveError = L10n.parseBeforeSave
            return
        }

        let fingerprint = saveRequestFingerprint(request)
        let requestToSave = request
        let idempotencyKey: UUID
        let isRetry: Bool

        if let pendingSaveIdempotencyKey, pendingSaveFingerprint == fingerprint {
            idempotencyKey = pendingSaveIdempotencyKey
            isRetry = true
        } else {
            idempotencyKey = UUID()
            pendingSaveFingerprint = fingerprint
            pendingSaveRequest = requestToSave
            pendingSaveIdempotencyKey = idempotencyKey
            persistPendingSaveContext()
            isRetry = false
        }

        Task {
            await submitSave(
                request: requestToSave,
                idempotencyKey: idempotencyKey,
                isRetry: isRetry,
                intent: .manual
            )
        }
    }

    private func retryLastSave() {
        guard appStore.isNetworkReachable else {
            saveError = L10n.noNetworkRetry
            return
        }
        guard let pendingSaveRequest, let pendingSaveIdempotencyKey else {
            saveError = L10n.noPreviousRetry
            return
        }

        Task {
            await submitSave(
                request: pendingSaveRequest,
                idempotencyKey: pendingSaveIdempotencyKey,
                isRetry: true,
                intent: .retry
            )
        }
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: autoSaveDelayNs)
            guard !Task.isCancelled else { return }
            await autoSaveIfNeeded()
        }
    }

    private func autoSaveIfNeeded() async {
        guard appStore.isNetworkReachable else { return }
        guard !isSaving else { return }
        guard let parseResult else { return }
        guard parseResult.needsClarification != true else { return }
        guard parseResult.confidence >= autoSaveMinConfidence else { return }
        guard parseError == nil else { return }
        guard let request = buildSaveDraftRequest() else { return }

        let contentFingerprint = autoSaveContentFingerprint(request)
        if contentFingerprint == lastAutoSavedContentFingerprint {
            return
        }

        let idempotencyKey = UUID()
        pendingSaveFingerprint = saveRequestFingerprint(request)
        pendingSaveRequest = request
        pendingSaveIdempotencyKey = idempotencyKey
        persistPendingSaveContext()

        await submitSave(
            request: request,
            idempotencyKey: idempotencyKey,
            isRetry: false,
            intent: .auto
        )
    }

    private func autoSaveContentFingerprint(_ request: SaveLogRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        struct Payload: Codable {
            let parseRequestId: String
            let rawText: String
            let inputKind: String?
            let imageRef: String?
            let totals: NutritionTotals
            let items: [SaveParsedFoodItem]
        }
        let payload = Payload(
            parseRequestId: request.parseRequestId,
            rawText: request.parsedLog.rawText,
            inputKind: request.parsedLog.inputKind,
            imageRef: request.parsedLog.imageRef,
            totals: request.parsedLog.totals,
            items: request.parsedLog.items
        )
        guard let data = try? encoder.encode(payload) else {
            return UUID().uuidString
        }
        return data.base64EncodedString()
    }

    private func normalizedInputKind(_ rawValue: String?, fallback: String = "text") -> String {
        let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch normalized {
        case "text", "image", "voice", "manual":
            return normalized
        default:
            return fallback
        }
    }

    private func requestWithImageRef(_ request: SaveLogRequest, imageRef: String?) -> SaveLogRequest {
        SaveLogRequest(
            parseRequestId: request.parseRequestId,
            parseVersion: request.parseVersion,
            parsedLog: SaveLogBody(
                rawText: request.parsedLog.rawText,
                loggedAt: request.parsedLog.loggedAt,
                inputKind: normalizedInputKind(request.parsedLog.inputKind, fallback: latestParseInputKind),
                imageRef: imageRef,
                confidence: request.parsedLog.confidence,
                totals: request.parsedLog.totals,
                sourcesUsed: request.parsedLog.sourcesUsed,
                items: request.parsedLog.items
            )
        )
    }

    private func prepareSaveRequestForNetwork(_ request: SaveLogRequest, idempotencyKey: UUID) async throws -> SaveLogRequest {
        var prepared = request
        let kind = normalizedInputKind(prepared.parsedLog.inputKind, fallback: latestParseInputKind)

        if kind == "image" &&
            (prepared.parsedLog.imageRef?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
            let pendingImageData {
            let storageService = ImageStorageService(
                configuration: appStore.configuration,
                authTokenProvider: { [appStore] in
                    if let token = appStore.authSessionStore.session?.accessToken,
                       !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return token
                    }
                    return appStore.configuration.authToken
                }
            )
            let uploadedRef = try await storageService.uploadJPEG(pendingImageData)
            pendingImageStorageRef = uploadedRef
            prepared = requestWithImageRef(prepared, imageRef: uploadedRef)
            for rowIndex in inputRows.indices where inputRows[rowIndex].imagePreviewData != nil {
                inputRows[rowIndex].imageRef = uploadedRef
            }
        } else if kind == "image",
                  let existingRef = pendingImageStorageRef ?? prepared.parsedLog.imageRef {
            prepared = requestWithImageRef(prepared, imageRef: existingRef)
        }

        if pendingSaveIdempotencyKey == idempotencyKey {
            pendingSaveRequest = prepared
            pendingSaveFingerprint = saveRequestFingerprint(prepared)
            persistPendingSaveContext()
        }

        return prepared
    }

    private func submitSave(request: SaveLogRequest, idempotencyKey: UUID, isRetry: Bool, intent: SaveIntent) async {
        let startedAt = Date()
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        var effectiveRequest = request
        do {
            effectiveRequest = try await prepareSaveRequestForNetwork(request, idempotencyKey: idempotencyKey)
            let response = try await appStore.apiClient.saveLog(effectiveRequest, idempotencyKey: idempotencyKey)
            let savedDay = String(effectiveRequest.parsedLog.loggedAt.prefix(10))
            let prefix = isRetry ? L10n.retrySucceededPrefix : L10n.savedSuccessfullyPrefix
            let timeToLogMs = flowStartedAt.map { elapsedMs(since: $0) }
            if intent == .auto {
                saveSuccessMessage = nil
                lastAutoSavedContentFingerprint = autoSaveContentFingerprint(effectiveRequest)
            } else {
                if let timeToLogMs {
                    saveSuccessMessage = L10n.saveSuccessWithTTL(prefix: prefix, logID: response.logId, day: savedDay, ttlSeconds: timeToLogMs / 1000)
                    lastTimeToLogMs = timeToLogMs
                } else {
                    saveSuccessMessage = L10n.saveSuccessWithoutTTL(prefix: prefix, logID: response.logId, day: savedDay)
                }
            }

            let syncedToHealth = await syncSavedLogToAppleHealthIfEnabled(effectiveRequest)
            if syncedToHealth {
                if intent == .auto {
                    saveSuccessMessage = nil
                } else if let current = saveSuccessMessage, !current.isEmpty {
                    saveSuccessMessage = "\(current) • Synced to Apple Health"
                }
            }

            saveError = nil
            appStore.setError(nil)
            emitSaveTelemetrySuccess(
                request: effectiveRequest,
                durationMs: elapsedMs(since: startedAt),
                isRetry: isRetry,
                logId: response.logId,
                timeToLogMs: timeToLogMs
            )
            if intent != .auto {
                flowStartedAt = nil
                draftLoggedAt = nil
            }
            if let parsedDate = Self.summaryRequestFormatter.date(from: savedDay) {
                selectedSummaryDate = parsedDate
            }
            await loadDaySummary(forcedDate: savedDay)
            NotificationCenter.default.post(
                name: .nutritionProgressDidChange,
                object: nil,
                userInfo: ["savedDay": savedDay]
            )
        } catch {
            saveSuccessMessage = nil
            handleAuthFailureIfNeeded(error)
            let message: String
            if error is ImageStorageServiceError {
                message = (error as? LocalizedError)?.errorDescription ?? "Image upload failed."
            } else {
                message = userFriendlySaveError(error)
            }
            saveError = message
            appStore.setError(message)
            emitSaveTelemetryFailure(
                request: effectiveRequest,
                error: error,
                durationMs: elapsedMs(since: startedAt),
                isRetry: isRetry
            )
        }
    }

    private func syncSavedLogToAppleHealthIfEnabled(_ request: SaveLogRequest) async -> Bool {
        guard appStore.isHealthSyncEnabled else { return false }

        let loggedAtDate = Self.loggedAtFormatter.date(from: request.parsedLog.loggedAt) ??
            ISO8601DateFormatter().date(from: request.parsedLog.loggedAt) ??
            Date()
        do {
            return try await appStore.syncNutritionToAppleHealth(
                totals: request.parsedLog.totals,
                loggedAt: loggedAtDate
            )
        } catch {
            if let healthError = error as? HealthKitServiceError,
               case .notAuthorized = healthError {
                appStore.disconnectAppleHealth()
            }
            return false
        }
    }

    private func emitParseTelemetrySuccess(response: ParseLogResponse, durationMs: Double, uiApplied: Bool) {
        TelemetryClient.shared.emit(
            TelemetryEvent(
                eventName: "parse_request",
                feature: "parse",
                outcome: .success,
                durationMs: durationMs,
                timestamp: TelemetryClient.shared.nowISO8601(),
                environment: appStore.configuration.environment.rawValue,
                backendRequestId: response.requestId,
                backendErrorCode: nil,
                httpStatusCode: nil,
                parseRequestId: response.parseRequestId,
                parseVersion: response.parseVersion,
                details: [
                    "route": .string(response.route),
                    "cacheHit": .bool(response.cacheHit),
                    "fallbackUsed": .bool(response.fallbackUsed),
                    "needsClarification": .bool(response.needsClarification),
                    "uiApplied": .bool(uiApplied)
                ]
            )
        )
    }

    private func emitParseTelemetryFailure(error: Error, durationMs: Double, uiApplied: Bool) {
        let metadata = telemetryErrorMetadata(error)
        TelemetryClient.shared.emit(
            TelemetryEvent(
                eventName: "parse_request",
                feature: "parse",
                outcome: .failure,
                durationMs: durationMs,
                timestamp: TelemetryClient.shared.nowISO8601(),
                environment: appStore.configuration.environment.rawValue,
                backendRequestId: metadata.backendRequestId,
                backendErrorCode: metadata.backendErrorCode,
                httpStatusCode: metadata.httpStatusCode,
                parseRequestId: parseResult?.parseRequestId,
                parseVersion: parseResult?.parseVersion,
                details: [
                    "uiApplied": .bool(uiApplied),
                    "errorMessage": .string((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                ]
            )
        )
    }

    private func emitSaveTelemetrySuccess(request: SaveLogRequest, durationMs: Double, isRetry: Bool, logId: String) {
        emitSaveTelemetrySuccess(request: request, durationMs: durationMs, isRetry: isRetry, logId: logId, timeToLogMs: nil)
    }

    private func emitSaveTelemetrySuccess(
        request: SaveLogRequest,
        durationMs: Double,
        isRetry: Bool,
        logId: String,
        timeToLogMs: Double?
    ) {
        var details: [String: TelemetryValue] = [
            "isRetry": .bool(isRetry),
            "itemsCount": .int(request.parsedLog.items.count),
            "rawTextLength": .int(request.parsedLog.rawText.count),
            "logId": .string(logId)
        ]
        if let timeToLogMs {
            details["timeToLogMs"] = .int(Int(timeToLogMs.rounded()))
        }

        TelemetryClient.shared.emit(
            TelemetryEvent(
                eventName: "save_log",
                feature: "save",
                outcome: .success,
                durationMs: durationMs,
                timestamp: TelemetryClient.shared.nowISO8601(),
                environment: appStore.configuration.environment.rawValue,
                backendRequestId: nil,
                backendErrorCode: nil,
                httpStatusCode: nil,
                parseRequestId: request.parseRequestId,
                parseVersion: request.parseVersion,
                details: details
            )
        )
    }

    private func emitSaveTelemetryFailure(request: SaveLogRequest, error: Error, durationMs: Double, isRetry: Bool) {
        let metadata = telemetryErrorMetadata(error)
        TelemetryClient.shared.emit(
            TelemetryEvent(
                eventName: "save_log",
                feature: "save",
                outcome: .failure,
                durationMs: durationMs,
                timestamp: TelemetryClient.shared.nowISO8601(),
                environment: appStore.configuration.environment.rawValue,
                backendRequestId: metadata.backendRequestId,
                backendErrorCode: metadata.backendErrorCode,
                httpStatusCode: metadata.httpStatusCode,
                parseRequestId: request.parseRequestId,
                parseVersion: request.parseVersion,
                details: [
                    "isRetry": .bool(isRetry),
                    "itemsCount": .int(request.parsedLog.items.count),
                    "rawTextLength": .int(request.parsedLog.rawText.count),
                    "errorMessage": .string((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                ]
            )
        )
    }

    private func telemetryErrorMetadata(_ error: Error) -> (backendRequestId: String?, backendErrorCode: String?, httpStatusCode: Int?) {
        guard let apiError = error as? APIClientError else {
            return (nil, nil, nil)
        }

        switch apiError {
        case let .server(statusCode, payload):
            return (payload.requestId, payload.code, statusCode)
        case let .unexpectedStatus(code):
            return (nil, "UNEXPECTED_STATUS", code)
        default:
            return (nil, nil, nil)
        }
    }

    private func elapsedMs(since startedAt: Date) -> Double {
        (Date().timeIntervalSince(startedAt) * 1000).rounded()
    }

    private func refreshDaySummary() {
        Task {
            await loadDaySummary()
        }
    }

    private func loadDaySummary(forcedDate: String? = nil) async {
        isLoadingDaySummary = true
        daySummaryError = nil
        defer { isLoadingDaySummary = false }

        let dateToLoad = forcedDate ?? summaryDateString
        guard appStore.isNetworkReachable else {
            daySummaryError = L10n.noNetworkSummary
            return
        }

        do {
            let response = try await appStore.apiClient.getDaySummary(date: dateToLoad)
            daySummary = response
            daySummaryError = nil
        } catch {
            handleAuthFailureIfNeeded(error)
            daySummaryError = userFriendlyDaySummaryError(error)
            if daySummary?.date != dateToLoad {
                daySummary = nil
            }
        }
    }

    private var summaryDateString: String {
        Self.summaryRequestFormatter.string(from: selectedSummaryDate)
    }

    private func userFriendlyDaySummaryError(_ error: Error) -> String {
        guard let apiError = error as? APIClientError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        if isAuthTokenError(apiError) {
            return L10n.authSessionExpired
        }

        switch apiError {
        case let .server(_, payload):
            switch payload.code {
            case "PROFILE_NOT_FOUND":
                return L10n.daySummaryProfileNotFound
            case "INVALID_INPUT":
                return L10n.daySummaryInvalidInput
            default:
                return payload.message
            }
        case .networkFailure(_):
            return L10n.daySummaryNetworkFailure
        default:
            return apiError.errorDescription ?? L10n.daySummaryFailure
        }
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

    private func clearPendingSaveContext() {
        pendingSaveRequest = nil
        pendingSaveFingerprint = nil
        pendingSaveIdempotencyKey = nil
        defaults.removeObject(forKey: Self.pendingSaveDefaultsKey)
    }

    private func saveRequestFingerprint(_ request: SaveLogRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(request) else {
            return UUID().uuidString
        }
        return data.base64EncodedString()
    }

    private func userFriendlySaveError(_ error: Error) -> String {
        guard let apiError = error as? APIClientError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        if isAuthTokenError(apiError) {
            return L10n.authSessionExpired
        }

        switch apiError {
        case let .server(_, payload):
            switch payload.code {
            case "IDEMPOTENCY_CONFLICT":
                return L10n.saveIdempotencyConflict
            case "INVALID_PARSE_REFERENCE":
                return L10n.saveInvalidParseReference
            case "MISSING_IDEMPOTENCY_KEY":
                return L10n.saveMissingIdempotency
            default:
                return payload.message
            }
        case .networkFailure(_):
            return L10n.saveNetworkFailure
        default:
            return apiError.errorDescription ?? L10n.saveFailure
        }
    }

    private func userFriendlyParseError(_ error: Error) -> String {
        guard let apiError = error as? APIClientError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        if isAuthTokenError(apiError) {
            return L10n.authSessionExpired
        }

        switch apiError {
        case .networkFailure(_):
            return L10n.parseNetworkFailure
        default:
            return apiError.errorDescription ?? L10n.parseFailure
        }
    }

    private func userFriendlyEscalationError(_ error: Error) -> (message: String, blockCode: String?) {
        guard let apiError = error as? APIClientError else {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return (message, nil)
        }

        if isAuthTokenError(apiError) {
            return (L10n.authSessionExpired, nil)
        }

        switch apiError {
        case let .server(_, payload):
            switch payload.code {
            case "ESCALATION_DISABLED":
                return (L10n.escalationDisabledNow, "ESCALATION_DISABLED")
            case "BUDGET_EXCEEDED":
                return (L10n.escalationBudgetExceeded, "BUDGET_EXCEEDED")
            case "ESCALATION_NOT_REQUIRED":
                return (L10n.escalationNoLongerNeeded, nil)
            case "INVALID_PARSE_REFERENCE":
                return (L10n.escalationInvalidParseReference, nil)
            default:
                return (payload.message, nil)
            }
        case .networkFailure(_):
            return (L10n.escalationNetworkFailure, nil)
        default:
            return (apiError.errorDescription ?? L10n.escalationFailure, nil)
        }
    }

    private func isAuthTokenError(_ apiError: APIClientError) -> Bool {
        switch apiError {
        case .missingAuthToken:
            return true
        case let .server(statusCode, payload):
            if statusCode == 401 || statusCode == 403 {
                return true
            }

            let code = payload.code.uppercased()
            if code == "UNAUTHORIZED" || code.contains("TOKEN") || code.contains("AUTH") {
                return true
            }

            let message = payload.message.lowercased()
            if message.contains("invalid token") ||
                message.contains("missing bearer token") ||
                message.contains("jwt") ||
                message.contains("unauthorized") {
                return true
            }
            return false
        default:
            return false
        }
    }

    private func handleAuthFailureIfNeeded(_ error: Error) {
        guard let apiError = error as? APIClientError else {
            return
        }
        guard isAuthTokenError(apiError) else {
            return
        }
        appStore.authService.signOut()
    }

    private func persistPendingSaveContext() {
        guard let pendingSaveRequest, let pendingSaveFingerprint, let pendingSaveIdempotencyKey else {
            return
        }
        let draft = PendingSaveDraft(
            request: pendingSaveRequest,
            fingerprint: pendingSaveFingerprint,
            idempotencyKey: pendingSaveIdempotencyKey.uuidString.lowercased()
        )
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(draft) else {
            return
        }
        defaults.set(data, forKey: Self.pendingSaveDefaultsKey)
    }

    private func restorePendingSaveContextIfNeeded() {
        guard pendingSaveRequest == nil, pendingSaveIdempotencyKey == nil else {
            return
        }
        guard let data = defaults.data(forKey: Self.pendingSaveDefaultsKey) else {
            return
        }
        let decoder = JSONDecoder()
        guard let draft = try? decoder.decode(PendingSaveDraft.self, from: data),
              let key = UUID(uuidString: draft.idempotencyKey) else {
            defaults.removeObject(forKey: Self.pendingSaveDefaultsKey)
            return
        }

        pendingSaveRequest = draft.request
        pendingSaveFingerprint = draft.fingerprint
        pendingSaveIdempotencyKey = key
    }

    private func saveDraftPreviewJSON() -> String {
        guard let request = buildSaveDraftRequest() else {
            return "{}"
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(request), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func roundOneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private static let loggedAtFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let summaryRequestFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let summaryDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let topDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let pendingSaveDefaultsKey = "app.pendingSaveDraft.v1"
}

private struct PendingSaveDraft: Codable {
    let request: SaveLogRequest
    let fingerprint: String
    let idempotencyKey: String
}

private struct RowCalorieDetails: Identifiable {
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

private struct PreparedImagePayload {
    let uploadData: Data
    let previewData: Data
    let mimeType: String
}

private struct HomeImagePicker: UIViewControllerRepresentable {
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

private struct LiquidGlassCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(configuration.isPressed ? 0.14 : 0.26),
                                        Color.white.opacity(configuration.isPressed ? 0.04 : 0.09)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(configuration.isPressed ? 0.52 : 0.68),
                                        Color.white.opacity(configuration.isPressed ? 0.16 : 0.28)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            }
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.10 : 0.20), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct EditableParsedItem: Identifiable {
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

#Preview {
    MainLoggingShellView()
        .environmentObject(AppStore())
}
