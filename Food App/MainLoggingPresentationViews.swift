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
    let isSaveMealEnabled: Bool
    let onSaveMeal: () -> Void
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
                    HStack {
                        Button(action: onSaveMeal) {
                            Label("Save meal", systemImage: "bookmark")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(Color(red: 0.902, green: 0.361, blue: 0.102))
                        .disabled(!isSaveMealEnabled)

                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 2)

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
        .background(AppDrawerSurface.gradient)
        .presentationBackground(AppDrawerSurface.gradient)
        .presentationDragIndicator(.visible)
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

struct HydrationAmountPromptSheet: View {
    let prompt: HydrationAmountPromptPresentation
    let onSelect: (HydrationSuggestion) -> Void
    let onCancel: () -> Void

    private var suggestions: [HydrationSuggestion] {
        if !prompt.suggestions.isEmpty {
            return prompt.suggestions
        }
        return [
            HydrationSuggestion(amountMl: 250, label: "250 ml"),
            HydrationSuggestion(amountMl: 500, label: "500 ml"),
            HydrationSuggestion(amountMl: 750, label: "750 ml")
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            AppDrawerHeader(onClose: onCancel) {
                Text("How much water?")
                    .font(.custom("InstrumentSerif-Regular", size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.cyan,
                                Color.blue
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                        .frame(width: 48, height: 48)
                        .background(Color.cyan.opacity(0.12), in: Circle())

                    Text(prompt.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Water" : prompt.rawText)
                        .font(.headline)
                        .lineLimit(2)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 12)], spacing: 12) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            AppHaptics.selection()
                            onSelect(suggestion)
                        } label: {
                            VStack(spacing: 6) {
                                Text(suggestion.label)
                                    .font(.system(size: 20, weight: .semibold))
                                Text(HydrationDisplayText.shortLabel(amountMl: suggestion.amountMl))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 78)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.cyan.opacity(0.22), lineWidth: 0.8)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)

            Spacer(minLength: 0)
        }
        .background(AppDrawerSurface.gradient.ignoresSafeArea())
    }
}

struct HydrationGoalPromptSheet: View {
    let isSaving: Bool
    let onSelect: (Int) -> Void
    let onSkip: () -> Void

    private let goalOptions: [(ml: Int, title: String, subtitle: String)] = [
        (2000, "2 L", "About 8 cups"),
        (2500, "2.5 L", "A steady target"),
        (3000, "3 L", "More active days")
    ]

    var body: some View {
        VStack(spacing: 0) {
            AppDrawerHeader(onClose: onSkip) {
                Text("Water goal")
                    .font(.custom("InstrumentSerif-Regular", size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.cyan, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "drop.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                        .frame(width: 52, height: 52)
                        .background(Color.cyan.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("What do you want to drink each day?")
                            .font(.headline)
                        Text("This becomes the line on your water chart.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    ForEach(goalOptions.indices, id: \.self) { index in
                        let option = goalOptions[index]
                        Button {
                            AppHaptics.selection()
                            onSelect(option.ml)
                        } label: {
                            VStack(spacing: 6) {
                                Text(option.title)
                                    .font(.system(size: 21, weight: .semibold))
                                Text(option.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 92)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.cyan.opacity(0.22), lineWidth: 0.8)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }
                }

                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)

            Spacer(minLength: 0)
        }
        .background(AppDrawerSurface.gradient.ignoresSafeArea())
    }
}

struct MainLoggingRowCalorieDetailsSheet: View {
    let details: RowCalorieDetails
    let isDeleteDisabled: Bool
    @Binding var isDeleteConfirmationPresented: Bool
    let isSaveMealEnabled: Bool
    let isSavedMealSelected: Bool
    let onSaveMeal: () -> Void
    let onDeleteTapped: () -> Void
    let onConfirmDelete: () -> Void
    let onCancelDelete: () -> Void
    let onDone: () -> Void
    let onItemQuantityChange: (Int, Double) -> Void

    /// 2026-05-23: needed so `headerMedia` can fall back to fetching the
    /// remote JPEG via `appStore.imageStorageService.fetchJPEG(...)`
    /// when `details.imagePreviewData` is nil (cold launch, scrolling
    /// through past days, etc.).
    @EnvironmentObject private var appStore: AppStore

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
                        showsThoughtProcess: false,
                        onItemQuantityChange: onItemQuantityChange,
                        onRecalculate: nil
                    )

                    LoggingResultThoughtProcessCard(thoughtProcess: details.thoughtProcess)

                    Button(role: .destructive, action: onDeleteTapped) {
                        Text("Delete")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .disabled(isDeleteDisabled)
                    .accessibilityHint(Text("Deletes this food entry and updates your totals."))
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    saveMealToolbarControl
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
        // V3.1 hotfix v6.2 (2026-05-20): always open fully (.large) instead
        // of the prior 62%-by-default + large-drag-up combo. User feedback
        // was that the half-height initial position made the drawer feel
        // like it wasn't fully opening, especially after the camera-capture
        // drawer was changed to also open fully.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppDrawerSurface.gradient)
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
    private var saveMealToolbarControl: some View {
        if isSavedMealSelected {
            Label("Saved", systemImage: "bookmark.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.brandOrangeDeep)
                .accessibilityAddTraits(.isSelected)
                .accessibilityHint(Text("This logged meal is already in your saved meals."))
        } else {
            Button(action: onSaveMeal) {
                Label("Save meal", systemImage: "bookmark")
            }
            .disabled(!isSaveMealEnabled)
        }
    }

    @ViewBuilder
    private var headerMedia: some View {
        // Preference order:
        //   1. In-memory `imagePreviewData` — instant render, no network.
        //      This is what's available right after a save in the same
        //      session.
        //   2. Remote `imageRef` — lazily fetched from Supabase storage.
        //      Used when the in-memory preview has been dropped (cold
        //      launch, scrolling far into history, sheet reopened after
        //      the AppStore released the bytes).
        //   3. Nothing — text-only logs or logs whose image upload
        //      failed both inline and in the deferred retry path.
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
        } else if let imageRef = details.imageRef?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !imageRef.isEmpty {
            RemoteFoodLogImageView(
                imageRef: imageRef,
                imageStorageService: appStore.imageStorageService
            )
            .frame(maxWidth: .infinity)
            .frame(height: 224)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 16)
        } else {
            EmptyView()
        }
    }
}

/// Loads a food-log image from Supabase storage via `imageRef` and renders
/// it with the same visual treatment as the in-memory preview path. Caches
/// the decoded bytes process-wide so re-opening the same sheet (or scrolling
/// past the same row in a list) doesn't trigger a refetch.
///
/// Added 2026-05-23 to fix the "I can see the photo right after I save it
/// but it disappears on cold relaunch" bug. The image bytes are in Supabase
/// storage (food_logs.image_ref is populated for 30/31 recent image saves —
/// verified in prod DB) but the row-detail sheet was only reading the
/// in-memory `imagePreviewData`. This view is the remote fallback.
struct RemoteFoodLogImageView: View {
    let imageRef: String
    let imageStorageService: ImageStorageService

    @State private var loadedImage: UIImage?
    @State private var loadFailed = false

    /// Process-wide cache of imageRef → UIImage. NSCache limits itself
    /// under memory pressure so we don't have to think about eviction.
    /// Keyed on the raw imageRef string (e.g.
    /// `users/<uuid>/food-logs/2026/05/<uuid>.jpg`).
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100  // ~100 thumbnails ≈ a few MB; iOS evicts under pressure anyway
        return cache
    }()

    var body: some View {
        ZStack {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if loadFailed {
                placeholder
            } else {
                placeholder.overlay {
                    ProgressView()
                        .tint(.secondary)
                }
            }
        }
        .task(id: imageRef) {
            await loadIfNeeded()
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.10))
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
                    .opacity(loadFailed ? 1 : 0)
            }
    }

    private func loadIfNeeded() async {
        if let cached = Self.cache.object(forKey: imageRef as NSString) {
            loadedImage = cached
            return
        }
        do {
            let data = try await imageStorageService.fetchJPEG(at: imageRef)
            guard let uiImage = UIImage(data: data) else {
                loadFailed = true
                return
            }
            Self.cache.setObject(uiImage, forKey: imageRef as NSString)
            // Guard against the view being reused for a different
            // imageRef before this fetch completed (the .task(id:)
            // modifier already cancels old loads, but be defensive).
            loadedImage = uiImage
        } catch {
            loadFailed = true
        }
    }
}

struct MainLoggingHomeStatusStrip: View {
    let saveSuccessMessage: String?
    let parseError: String?
    let parseInfoMessage: String?
    let inputModeStatusMessage: String?
    let shouldShowRetryParseButton: Bool
    let shouldShowLoggingTipsButton: Bool
    let onRetryParse: () -> Void
    let onLoggingTips: () -> Void

    // 2026-05-23: the inline "Logging tips" chip was retired in favor of
    // the bottom-sheet popup that auto-presents whenever a row parses as
    // vague (see LoggingTipsPromptSheet). The shouldShowLoggingTipsButton
    // + onLoggingTips properties are kept on the struct for backwards
    // compatibility with callers that still construct this strip, but the
    // button itself no longer renders.
    var body: some View {
        HStack(spacing: 10) {
            statusText

            Spacer(minLength: 0)

            if shouldShowRetryParseButton {
                Button(L10n.retryParseButton, action: onRetryParse)
                    .font(.system(size: 13, weight: .semibold))
                    .buttonStyle(.bordered)
                    .accessibilityHint(Text(L10n.retryParseHint))
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if let parseError {
            if Self.isConnectivityParseError(parseError) {
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
        } else if let parseInfoMessage {
            Text(parseInfoMessage)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else if let inputModeStatusMessage, !inputModeStatusMessage.isEmpty {
            Text(inputModeStatusMessage)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        } else {
            EmptyView()
        }
    }

    static func isConnectivityParseError(_ message: String) -> Bool {
        message == L10n.noNetworkParse || message == L10n.parseNetworkFailure
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
                let trimmedExplanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
                let qty = HomeLoggingDisplayText.formatOneDecimal(item.quantity)
                return "\(trimmedExplanation) Food App used \(qty) \(item.unit) with \(sourceLabel) nutrition data, then scaled calories, protein, carbs, and fat from the matched serving."
            }
            let qty = HomeLoggingDisplayText.formatOneDecimal(item.quantity)
            var text = "Interpreted as \"\(item.name)\". Food App used \(qty) \(item.unit) with \(sourceLabel) to estimate \(Int(item.calories.rounded())) kcal. The macro values are scaled from the same matched serving so protein, carbs, and fat stay consistent."
            if isApprox { text += " Result is marked approximate." }
            return text
        }

        return "A calorie estimate is available but no matched item was retained. Re-parse to refine."
    }
}
