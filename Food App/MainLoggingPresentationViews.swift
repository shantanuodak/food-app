import SwiftUI
import Foundation
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
    let loggedAt: Date
    let mealTag: FoodLogMealTag?
    let onSaveMeal: () -> Void
    let onManualAddBackToText: () -> Void
    let onItemQuantityChange: (Int, Double) -> Void
    let onMealTagChange: (FoodLogMealTag) -> Void
    let onLoggedAtChange: (Date) -> Void
    let onRecalculate: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
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
                            loggedAt: loggedAt,
                            mealTag: mealTag,
                            onItemQuantityChange: onItemQuantityChange,
                            onMealTagChange: onMealTagChange,
                            onLoggedAtChange: onLoggedAtChange,
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
                .frame(width: proxy.size.width, alignment: .topLeading)
                .clipped()
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .scrollIndicators(.visible, axes: .vertical)
            .clipped()
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

struct HydrationServingOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let amountMl: Double
    let inputAmount: Double?
    let inputUnit: String?
    let rawText: String

    static let common: [HydrationServingOption] = [
        HydrationServingOption(
            id: "ml-250",
            title: "250 ml",
            subtitle: "8.5 fl oz",
            amountMl: 250,
            inputAmount: 250,
            inputUnit: "ml",
            rawText: "250 ml water"
        ),
        HydrationServingOption(
            id: "ml-500",
            title: "500 ml",
            subtitle: "16.9 fl oz",
            amountMl: 500,
            inputAmount: 500,
            inputUnit: "ml",
            rawText: "500 ml water"
        ),
        HydrationServingOption(
            id: "ml-750",
            title: "750 ml",
            subtitle: "25.4 fl oz",
            amountMl: 750,
            inputAmount: 750,
            inputUnit: "ml",
            rawText: "750 ml water"
        ),
        HydrationServingOption(
            id: "liter-1000",
            title: "1 L",
            subtitle: "33.8 fl oz",
            amountMl: 1000,
            inputAmount: 1,
            inputUnit: "l",
            rawText: "1 liter of water"
        )
    ]

    static func from(suggestion: HydrationSuggestion, index: Int) -> HydrationServingOption {
        if let option = common.first(where: { abs($0.amountMl - suggestion.amountMl) < 0.5 }) {
            return option
        }

        return HydrationServingOption(
            id: "suggestion-\(index)-\(Int(suggestion.amountMl.rounded()))",
            title: HydrationDisplayText.shortLabel(amountMl: suggestion.amountMl),
            subtitle: "\(String(format: "%.1f", suggestion.amountMl / 29.5735)) fl oz",
            amountMl: suggestion.amountMl,
            inputAmount: suggestion.amountMl,
            inputUnit: "ml",
            rawText: suggestion.label.lowercased().contains("water")
                ? suggestion.label
                : "\(suggestion.label) water"
        )
    }
}

struct HydrationAmountPromptSheet: View {
    let prompt: HydrationAmountPromptPresentation
    let onSelect: (HydrationServingOption) -> Void
    let onCancel: () -> Void

    private var servingOptions: [HydrationServingOption] {
        var options = HydrationServingOption.common
        for (index, suggestion) in prompt.suggestions.enumerated() {
            let option = HydrationServingOption.from(suggestion: suggestion, index: index)
            if !options.contains(where: { abs($0.amountMl - option.amountMl) < 0.5 }) {
                options.append(option)
            }
        }
        return options
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 12)], spacing: 12) {
                    ForEach(servingOptions) { option in
                        Button {
                            AppHaptics.selection()
                            onSelect(option)
                        } label: {
                            VStack(spacing: 6) {
                                Text(option.title)
                                    .font(.system(size: 20, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                                Text(option.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                HStack(alignment: .center, spacing: 16) {
                    HydrationGoalDropletPreview(reduceMotion: reduceMotion)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pick your daily water goal")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("We'll use it as your progress line.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 10)], spacing: 10) {
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
                            .glassyBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous), tint: Color.cyan.opacity(0.10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.cyan.opacity(0.22), lineWidth: 0.8)
                            }
                        }
                        .buttonStyle(HydrationGoalOptionButtonStyle())
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
    let hydrationQuickLogSavingOptionIDs: Set<String>
    let hydrationQuickLogPendingAmountMl: Double
    let canDeleteLastHydrationLog: Bool
    let isDeletingLastHydrationLog: Bool
    let onSaveMeal: () -> Void
    let onHydrationQuickLog: (HydrationServingOption) -> Void
    let onHydrationGoalTapped: () -> Void
    let onDeleteLastHydrationLog: () -> Void
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
            GeometryReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        if details.isHydration {
                            hydrationDetailsBody
                        } else {
                            headerMedia

                            LoggingResultDrawerBody(
                                foodName: details.displayName,
                                totals: totals,
                                items: details.parsedItems,
                                thoughtProcess: details.thoughtProcess,
                                showsThoughtProcess: false,
                                loggedAt: HomeLoggingDateUtils.date(fromLoggedAt: details.loggedAt) ?? Date(),
                                mealTag: FoodLogMealTag.normalized(details.mealType),
                                onItemQuantityChange: onItemQuantityChange,
                                onRecalculate: nil
                            )

                            LoggingResultThoughtProcessCard(thoughtProcess: details.thoughtProcess)
                        }

                        if !details.isHydration {
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
                    .frame(width: proxy.size.width, alignment: .topLeading)
                    .clipped()
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .scrollIndicators(.visible, axes: .vertical)
                .clipped()
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
        .alert(details.isHydration ? "Delete this water entry?" : "How sure are you that you want to delete this entry?", isPresented: $isDeleteConfirmationPresented) {
            Button("Delete", role: .destructive, action: onConfirmDelete)
            Button("Cancel", role: .cancel, action: onCancelDelete)
        } message: {
            Text(details.isHydration ? "This removes the water from your log, updates hydration progress, and deletes the database row when it has already synced." : "This removes the food from your log, updates your calories, and deletes the database row when it has already synced.")
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
            calories: Double(details.calories ?? 0),
            protein: details.protein ?? 0,
            carbs: details.carbs ?? 0,
            fat: details.fat ?? 0
        )
    }

    @ViewBuilder
    private var saveMealToolbarControl: some View {
        if details.isHydration {
            EmptyView()
        } else if isSavedMealSelected {
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

    private var hydrationDetailsBody: some View {
        HydrationDropletDetailsBody(
            details: details,
            savingOptionIDs: hydrationQuickLogSavingOptionIDs,
            pendingQuickLogAmountMl: hydrationQuickLogPendingAmountMl,
            canDeleteLastLog: canDeleteLastHydrationLog,
            isDeletingLastLog: isDeletingLastHydrationLog,
            onQuickLog: onHydrationQuickLog,
            onGoalTapped: onHydrationGoalTapped,
            onDeleteLastLog: onDeleteLastHydrationLog
        )
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

private struct HydrationDropletDetailsBody: View {
    let details: RowCalorieDetails
    let savingOptionIDs: Set<String>
    let pendingQuickLogAmountMl: Double
    let canDeleteLastLog: Bool
    let isDeletingLastLog: Bool
    let onQuickLog: (HydrationServingOption) -> Void
    let onGoalTapped: () -> Void
    let onDeleteLastLog: () -> Void

    private var totalMl: Double {
        max(0, details.hydrationDayTotalMl ?? details.hydrationAmountMl ?? 0)
    }

    private var goalMl: Double? {
        guard let goal = details.hydrationGoalMl, goal > 0 else { return nil }
        return goal
    }

    private var displayedTotalMl: Double {
        totalMl + pendingQuickLogAmountMl
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer(minLength: 0)
                HydrationLiquidDropletView(
                    totalMl: displayedTotalMl,
                    goalMl: goalMl,
                    isAdding: !savingOptionIDs.isEmpty
                )
                Spacer(minLength: 0)
            }

            HydrationQuickLogPanel(
                options: HydrationServingOption.common,
                savingOptionIDs: savingOptionIDs,
                canDeleteLastLog: canDeleteLastLog,
                isDeletingLastLog: isDeletingLastLog,
                onQuickLog: onQuickLog,
                onDeleteLastLog: onDeleteLastLog
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }
}

private struct HydrationQuickLogPanel: View {
    let options: [HydrationServingOption]
    let savingOptionIDs: Set<String>
    let canDeleteLastLog: Bool
    let isDeletingLastLog: Bool
    let onQuickLog: (HydrationServingOption) -> Void
    let onDeleteLastLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Log more water")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Choose a serving")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(options) { option in
                    Button {
                        AppHaptics.selection()
                        onQuickLog(option)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Text(option.subtitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            if savingOptionIDs.contains(option.id) {
                                ProgressView()
                                    .controlSize(.mini)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 62)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppColor.borderSubtle, lineWidth: 1)
                        }
                    }
                    .buttonStyle(HydrationGoalOptionButtonStyle())
                    .accessibilityLabel(Text("Log \(option.title), \(option.subtitle) of water"))
                }
            }

            Button(role: .destructive) {
                AppHaptics.selection()
                onDeleteLastLog()
            } label: {
                HStack(spacing: 10) {
                    if isDeletingLastLog {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(isDeletingLastLog ? "Deleting last water" : "Delete last water")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.red.opacity(canDeleteLastLog ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.red.opacity(canDeleteLastLog ? 0.25 : 0.10), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(canDeleteLastLog ? Color.red : Color.secondary)
            .disabled(!canDeleteLastLog || isDeletingLastLog)
            .accessibilityHint(Text("Deletes the most recent water entry for this day."))
        }
    }
}

private struct HydrationLiquidDropletView: View {
    let totalMl: Double
    let goalMl: Double?
    let isAdding: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var progress: Double {
        if let goalMl, goalMl > 0 {
            return min(max(totalMl / goalMl, 0.05), 1.0)
        }
        return min(max(totalMl / 2500, 0.16), 0.88)
    }

    private var goalLabel: String {
        if let goalMl {
            return "of \(HydrationDisplayText.shortLabel(amountMl: goalMl))"
        }
        return "logged today"
    }

    private var waterGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.58, green: 0.94, blue: 1.00).opacity(colorScheme == .dark ? 0.88 : 0.76),
                Color(red: 0.16, green: 0.68, blue: 0.98).opacity(colorScheme == .dark ? 0.95 : 0.86),
                Color(red: 0.02, green: 0.38, blue: 0.86).opacity(colorScheme == .dark ? 0.90 : 0.74)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var glassShellGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.18 : 0.86),
                Color(red: 0.73, green: 0.96, blue: 1.00).opacity(colorScheme == .dark ? 0.10 : 0.34),
                Color(red: 0.02, green: 0.30, blue: 0.70).opacity(colorScheme == .dark ? 0.16 : 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let phase = reduceMotion ? 0 : seconds * 1.05
            let breathingPulse = reduceMotion ? 1 : 1 + CGFloat(sin(seconds * 0.82)) * 0.007
            let addPulse: CGFloat = isAdding && !reduceMotion ? 1.018 : 1

            ZStack {
                dropletGlow

                ZStack {
                    HydrationDropletShape()
                        .fill(glassShellGradient)

                    HydrationDropletWaterLayer(
                        progress: progress,
                        phase: phase,
                        reduceMotion: reduceMotion,
                        waterGradient: waterGradient
                    )

                    HydrationDropletDepthOverlay(phase: phase)

                    HydrationDropletHighlights(phase: phase)

                    HydrationDropletShape()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.48 : 0.84),
                                    Color.cyan.opacity(colorScheme == .dark ? 0.26 : 0.34),
                                    Color.blue.opacity(colorScheme == .dark ? 0.36 : 0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.1
                        )

                    VStack(spacing: 5) {
                        Text(HydrationDisplayText.shortLabel(amountMl: totalMl))
                            .font(.system(size: 35, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.black.opacity(0.20), radius: 8, y: 3)
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                        Text(goalLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
                    }
                    .padding(.horizontal, 28)
                    .offset(y: 26)
                }
                .clipShape(HydrationDropletShape())
                .compositingGroup()
            }
            .frame(width: 232, height: 294)
            .scaleEffect(breathingPulse * addPulse)
            .animation(.spring(response: 0.34, dampingFraction: 0.72), value: totalMl)
            .animation(.spring(response: 0.22, dampingFraction: 0.70), value: isAdding)
        }
        .frame(width: 240, height: 302)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Water logged \(HydrationDisplayText.shortLabel(amountMl: totalMl)) \(goalLabel)"))
    }

    private var dropletGlow: some View {
        ZStack {
            HydrationDropletShape()
                .fill(Color.cyan.opacity(colorScheme == .dark ? 0.16 : 0.10))
                .frame(width: 200, height: 254)
                .blur(radius: 24)
                .offset(y: 16)

            HydrationDropletShape()
                .fill(Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08))
                .frame(width: 190, height: 244)
                .blur(radius: 18)
                .offset(y: 22)
        }
        .allowsHitTesting(false)
    }
}

private struct HydrationDropletWaterLayer: View {
    let progress: Double
    let phase: Double
    let reduceMotion: Bool
    let waterGradient: LinearGradient

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                HydrationWaveShape(
                    progress: progress,
                    phase: phase,
                    amplitude: reduceMotion ? 0 : max(3, size.width * 0.022)
                )
                .fill(waterGradient)

                HydrationWaveShape(
                    progress: min(0.98, progress + 0.018),
                    phase: phase + 1.7,
                    amplitude: reduceMotion ? 0 : max(1.5, size.width * 0.011)
                )
                .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18))

                Ellipse()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18), lineWidth: 1)
                    .frame(width: size.width * 0.68, height: size.height * 0.12)
                    .offset(x: size.width * 0.06, y: size.height * (0.56 - CGFloat(progress) * 0.46))
                    .blur(radius: 0.4)
            }
            .clipShape(HydrationDropletShape())
        }
        .allowsHitTesting(false)
    }
}

private struct HydrationGoalDropletPreview: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let phase = reduceMotion ? 0 : seconds * 1.25

            ZStack {
                HydrationDropletShape()
                    .fill(.ultraThinMaterial)

                HydrationWaveShape(
                    progress: 0.62,
                    phase: phase,
                    amplitude: reduceMotion ? 0 : 3.2
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(0.82),
                            Color.blue.opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(HydrationDropletShape())

                HydrationDropletShape()
                    .stroke(Color.white.opacity(0.38), lineWidth: 1)

                Image(systemName: "drop.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.90))
                    .offset(y: 12)
            }
            .frame(width: 72, height: 92)
            .drawingGroup()
        }
        .frame(width: 78, height: 98)
        .accessibilityHidden(true)
    }
}

private struct HydrationGoalOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

private struct HydrationDropletDepthOverlay: View {
    let phase: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let shimmerOffset = CGFloat(sin(phase * 0.7)) * size.width * 0.018

            ZStack {
                RadialGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(colorScheme == .dark ? 0.10 : 0.045),
                        Color.black.opacity(colorScheme == .dark ? 0.24 : 0.10)
                    ],
                    center: UnitPoint(x: 0.58, y: 0.72),
                    startRadius: size.width * 0.15,
                    endRadius: size.width * 0.70
                )

                Ellipse()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.20 : 0.40),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
                    .frame(width: size.width * 0.58, height: size.height * 0.15)
                    .rotationEffect(.degrees(-12))
                    .offset(x: size.width * 0.09 + shimmerOffset, y: size.height * 0.23)
                    .blur(radius: 0.5)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.12 : 0.22),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: size.width * 0.46, height: size.height * 0.05)
                    .rotationEffect(.degrees(-18))
                    .offset(x: size.width * 0.18 - shimmerOffset, y: size.height * 0.68)
                    .blur(radius: 2.4)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct HydrationDropletHighlights: View {
    let phase: Double
    @Environment(\.colorScheme) private var colorScheme

    init(phase: Double = 0) {
        self.phase = phase
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let shimmer = CGFloat((sin(phase * 0.82) + 1) * 0.5)
            ZStack(alignment: .topLeading) {
                Ellipse()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.58 : 0.74),
                                Color.white.opacity(colorScheme == .dark ? 0.16 : 0.26),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
                    .frame(width: size.width * 0.26, height: size.height * 0.48)
                    .rotationEffect(.degrees(28))
                    .offset(x: size.width * (0.24 + shimmer * 0.018), y: size.height * 0.09)
                    .blur(radius: 0.35)

                Capsule()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.26 : 0.34))
                    .frame(width: size.width * 0.055, height: size.height * 0.20)
                    .rotationEffect(.degrees(29))
                    .offset(x: size.width * 0.34, y: size.height * 0.15)
                    .blur(radius: 0.45)

                Ellipse()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.23))
                    .frame(width: size.width * 0.18, height: size.width * 0.10)
                    .rotationEffect(.degrees(-18))
                    .offset(x: size.width * 0.52, y: size.height * 0.17)
                    .blur(radius: 1.2)

                HydrationDropletShape()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.22), lineWidth: 7)
                    .blur(radius: 3)
                    .offset(x: -size.width * 0.015, y: -size.height * 0.01)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct HydrationDropletShape: Shape {
    func path(in rect: CGRect) -> Path {
        let minX = rect.minX
        let minY = rect.minY
        let width = rect.width
        let height = rect.height
        let top = CGPoint(x: minX + width * 0.50, y: minY + height * 0.015)
        let rightShoulder = CGPoint(x: minX + width * 0.95, y: minY + height * 0.58)
        let bottom = CGPoint(x: minX + width * 0.50, y: minY + height * 0.985)
        let leftShoulder = CGPoint(x: minX + width * 0.05, y: minY + height * 0.58)

        var path = Path()
        path.move(to: top)
        path.addCurve(
            to: rightShoulder,
            control1: CGPoint(x: minX + width * 0.70, y: minY + height * 0.16),
            control2: CGPoint(x: minX + width * 0.96, y: minY + height * 0.36)
        )
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: minX + width * 0.95, y: minY + height * 0.82),
            control2: CGPoint(x: minX + width * 0.73, y: minY + height * 0.985)
        )
        path.addCurve(
            to: leftShoulder,
            control1: CGPoint(x: minX + width * 0.27, y: minY + height * 0.985),
            control2: CGPoint(x: minX + width * 0.05, y: minY + height * 0.82)
        )
        path.addCurve(
            to: top,
            control1: CGPoint(x: minX + width * 0.04, y: minY + height * 0.36),
            control2: CGPoint(x: minX + width * 0.30, y: minY + height * 0.16)
        )
        path.closeSubpath()
        return path
    }
}

private struct HydrationWaveShape: Shape {
    var progress: Double
    var phase: Double
    var amplitude: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, phase) }
        set {
            progress = newValue.first
            phase = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0.0), 1.0)
        let baseline = rect.height * CGFloat(1.0 - clampedProgress)
        let width = max(rect.width, 1)
        let step = max(width / 56, 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: baseline))

        var x = rect.minX
        while x <= rect.maxX + step {
            let normalizedX = (x - rect.minX) / width
            let primary = sin(Double(normalizedX) * 2.0 * .pi + phase)
            let secondary = sin(Double(normalizedX) * 4.0 * .pi + phase * 0.62)
            let y = baseline + CGFloat(primary) * amplitude + CGFloat(secondary) * amplitude * 0.18
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
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
