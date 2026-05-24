import SwiftUI

private enum SavedMealsTokens {
    static let orange = AppColor.brandOrangeDeep
    static let orangeDeep = Color(red: 0.725, green: 0.306, blue: 0.071)
    static let orangeSoft = AppColor.brandOrangeSoft
    static let orangeWash = AppColor.surfaceWarm
    static let ink = AppColor.textPrimary
    static let muted = AppColor.textSecondary
    static let border = AppColor.borderHairline
    static let hairline = AppColor.borderHairline
    static let shadow = AppColor.shadow
    static let cardBackground = AppColor.surface
    static let cardTint = AppColor.surfaceWarm

    static let brandGradient = LinearGradient(
        colors: [AppColor.brandOrange, AppColor.brandOrangeDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let screenBackground = LinearGradient(
        colors: [AppColor.surfaceWarm, AppColor.surfaceWarm, AppColor.surfaceWarm],
        startPoint: .top,
        endPoint: .bottom
    )
}

struct SaveMealSheet: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    let draft: SaveLogRequest
    let onSaved: (SavedMeal) -> Void

    @State private var mealName: String
    @State private var collections: [SavedMealCollection] = []
    @State private var selectedCollectionId: String?
    @State private var isCreatingCollection = false
    @State private var newCollectionName = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(draft: SaveLogRequest, onSaved: @escaping (SavedMeal) -> Void) {
        self.draft = draft
        self.onSaved = onSaved
        _mealName = State(initialValue: SaveMealSheet.suggestedMealName(from: draft))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Meal name", text: $mealName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Name")
                } footer: {
                    Text("\(Int(draft.parsedLog.totals.calories.rounded())) calories · \(draft.parsedLog.items.count) item\(draft.parsedLog.items.count == 1 ? "" : "s")")
                }

                Section("Save to") {
                    ForEach(collections) { collection in
                        Button {
                            AppHaptics.selection()
                            selectedCollectionId = collection.id
                            isCreatingCollection = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(collection.name)
                                        .foregroundStyle(SavedMealsTokens.ink)
                                    Text("\(collection.mealCount) saved meal\(collection.mealCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedCollectionId == collection.id && !isCreatingCollection {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(SavedMealsTokens.orange)
                                }
                            }
                        }
                    }

                    Button {
                        AppHaptics.lightImpact()
                        isCreatingCollection = true
                        selectedCollectionId = nil
                    } label: {
                        Label("Create new collection", systemImage: "folder.badge.plus")
                    }
                    .foregroundStyle(SavedMealsTokens.orange)

                    if isCreatingCollection {
                        TextField("Collection name", text: $newCollectionName)
                            .textInputAutocapitalization(.words)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Save this meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        AppHaptics.lightImpact()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        AppHaptics.mediumImpact()
                        Task { await saveMeal() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving || !canSave)
                }
            }
            .task { await loadCollections() }
        }
    }

    private var canSave: Bool {
        let trimmedName = mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        if isCreatingCollection {
            return !newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return selectedCollectionId != nil || !collections.isEmpty
    }

    @MainActor
    private func loadCollections() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await appStore.apiClient.getSavedMeals()
            collections = response.collections
            selectedCollectionId = response.collections.first?.id
        } catch {
            errorMessage = userFacingError(error, fallback: "Couldn’t load saved meal collections.")
        }
        isLoading = false
    }

    @MainActor
    private func saveMeal() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        do {
            let response = try await appStore.apiClient.createSavedMeal(
                CreateSavedMealRequest(
                    name: mealName.trimmingCharacters(in: .whitespacesAndNewlines),
                    collectionId: isCreatingCollection ? nil : selectedCollectionId,
                    collectionName: isCreatingCollection ? newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                    mealPayload: draft.parsedLog
                )
            )
            AppHaptics.success()
            onSaved(response.meal)
            dismiss()
        } catch {
            AppHaptics.error()
            errorMessage = userFacingError(error, fallback: "Couldn’t save this meal.")
        }
        isSaving = false
    }

    private func userFacingError(_ error: Error, fallback: String) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return fallback
    }

    private static func suggestedMealName(from draft: SaveLogRequest) -> String {
        let first = draft.parsedLog.items.first?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first, !first.isEmpty {
            if draft.parsedLog.items.count > 1 {
                return "\(first) meal"
            }
            return first
        }
        return draft.parsedLog.rawText
            .split(separator: ",")
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).capitalized } ?? "Saved meal"
    }
}

struct SavedMealsScreen: View {
    enum PresentationStyle {
        case pushed
        case sheet(onClose: () -> Void)
    }

    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    let presentationStyle: PresentationStyle

    @State private var collections: [SavedMealCollection] = []
    @State private var meals: [SavedMeal] = []
    @State private var searchText = ""
    @State private var selectedCollectionId: String?
    @State private var isLoading = true
    @State private var loggingMealId: String?
    @State private var deletingMealId: String?
    @State private var mealPendingDeletion: SavedMeal?
    @State private var errorMessage: String?
    @State private var actionErrorMessage: String?
    @State private var confirmationMessage: String?

    init(presentationStyle: PresentationStyle = .pushed) {
        self.presentationStyle = presentationStyle
    }

    var body: some View {
        Group {
            switch presentationStyle {
            case .pushed:
                content
                    .navigationTitle("Saved meals")
                    .navigationBarTitleDisplayMode(.inline)
            case .sheet(let onClose):
                NavigationStack {
                    content
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Text("Saved meals")
                                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 28))
                                    .foregroundStyle(SavedMealsTokens.orangeDeep)
                            }
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    AppHaptics.lightImpact()
                                    onClose()
                                }
                            }
                        }
                }
            }
        }
        .background(SavedMealsTokens.screenBackground.ignoresSafeArea())
        .task { await loadSavedMeals() }
        .refreshable { await loadSavedMeals() }
        .confirmationDialog(
            "Delete saved meal?",
            isPresented: Binding(
                get: { mealPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        mealPendingDeletion = nil
                    }
                }
            ),
            presenting: mealPendingDeletion
        ) { meal in
            Button("Delete saved meal", role: .destructive) {
                AppHaptics.warning()
                Task { await deleteMeal(meal) }
            }
            Button("Cancel", role: .cancel) {
                AppHaptics.lightImpact()
                mealPendingDeletion = nil
            }
        } message: { meal in
            Text("This removes \(meal.name) from Saved Meals. Past food logs stay in your history.")
        }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if showsHero {
                    hero
                }
                searchField

                if isLoading {
                    SavedMealsLoadingCard()
                } else if let errorMessage {
                    SavedMealsStatusCard(
                        icon: "exclamationmark.triangle.fill",
                        title: "Couldn’t load saved meals",
                        message: errorMessage,
                        tint: .red
                    )
                } else if meals.isEmpty {
                    SavedMealsStatusCard(
                        icon: "bookmark.fill",
                        title: "No saved meals yet",
                        message: "Save repeat meals from the food details drawer and they’ll stay ready here.",
                        tint: SavedMealsTokens.orange
                    )
                } else {
                    if let actionErrorMessage {
                        SavedMealsActionErrorCard(message: actionErrorMessage)
                    }

                    if let confirmationMessage {
                        SavedMealsConfirmationCard(message: confirmationMessage)
                    }

                    if showsCollectionsSection {
                        collectionsSection
                    }

                    mealsSection
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, showsHero ? 18 : 14)
            .padding(.bottom, 36)
        }
        .background(SavedMealsTokens.screenBackground)
    }

    private var showsHero: Bool {
        if case .pushed = presentationStyle {
            return true
        }
        return false
    }

    private var showsCollectionsSection: Bool {
        !collections.isEmpty
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Keep repeats ")
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 42))
                + Text("one tap away.")
                    .font(OnboardingTypography.instrumentSerif(style: .italic, size: 42))
                    .foregroundStyle(SavedMealsTokens.orangeDeep)
            }
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(-4)
            .foregroundStyle(SavedMealsTokens.ink)

            Text("Collections organize your usual foods so logging dessert, breakfast, or favorites feels quick instead of repetitive.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(SavedMealsTokens.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SavedMealsTokens.muted)
            TextField("Search Saved Meals", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(SavedMealsTokens.ink)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(SavedMealsTokens.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SavedMealsTokens.hairline, lineWidth: 1)
        }
        .shadow(color: SavedMealsTokens.shadow, radius: 14, y: 6)
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SavedMealsSectionTitle("Collections")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    collectionFilterChip(
                        title: "All",
                        count: meals.count,
                        isSelected: selectedCollectionId == nil
                    ) {
                        selectedCollectionId = nil
                    }

                    ForEach(collections) { collection in
                        collectionFilterChip(
                            title: collection.name,
                            count: collection.mealCount,
                            isSelected: selectedCollectionId == collection.id
                        ) {
                            selectedCollectionId = collection.id
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SavedMealsSectionTitle(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Meals" : "Results")

            if filteredMeals.isEmpty {
                SavedMealsStatusCard(
                    icon: "magnifyingglass",
                    title: "No matching meals",
                    message: "Try searching by collection, food name, or ingredient.",
                    tint: SavedMealsTokens.orange
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredMeals) { meal in
                        SavedMealRow(
                            meal: meal,
                            isLogging: loggingMealId == meal.id,
                            isDeleting: deletingMealId == meal.id,
                            onLog: {
                                Task { await logMeal(meal) }
                            },
                            onDeleteRequest: {
                                mealPendingDeletion = meal
                            }
                        )
                    }
                }
            }
        }
    }

    private var filteredMeals: [SavedMeal] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return meals.filter { meal in
            let matchesCollection = selectedCollectionId == nil || meal.collectionId == selectedCollectionId
            let matchesQuery = query.isEmpty ||
                meal.name.lowercased().contains(query) ||
                meal.rawText.lowercased().contains(query) ||
                meal.collectionName.lowercased().contains(query)
            return matchesCollection && matchesQuery
        }
    }

    @MainActor
    private func loadSavedMeals() async {
        isLoading = true
        errorMessage = nil
        actionErrorMessage = nil
        do {
            let response = try await appStore.apiClient.getSavedMeals()
            collections = response.collections
            meals = response.meals
            if let selectedCollectionId,
               !response.collections.contains(where: { $0.id == selectedCollectionId }) {
                self.selectedCollectionId = nil
            }
        } catch is CancellationError {
            // 2026-05-24: pull-to-refresh while the initial `.task` is
            // still in flight cancels the prior request — that surfaces
            // as a CancellationError here. Treat it as a no-op so the
            // "Couldn't load saved meals" error card doesn't flash for
            // a request that was simply superseded.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Same situation when the cancellation comes through URLSession.
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Please try again."
        }
        isLoading = false
    }

    @MainActor
    private func logMeal(_ meal: SavedMeal) async {
        guard loggingMealId == nil else { return }
        loggingMealId = meal.id
        actionErrorMessage = nil
        confirmationMessage = nil
        do {
            let loggedAt = HomeLoggingDateUtils.loggedAtFormatter.string(from: Date())
            let response = try await appStore.apiClient.logSavedMeal(
                id: meal.id,
                request: LogSavedMealRequest(loggedAt: loggedAt)
            )
            AppHaptics.success()
            confirmationMessage = "Logged \(meal.name)"
            NotificationCenter.default.post(
                name: .savedMealDidLog,
                object: nil,
                userInfo: [
                    "meal": meal,
                    "logId": response.logId,
                    "loggedAt": loggedAt,
                    "savedDay": HomeLoggingDateUtils.summaryDayString(fromLoggedAt: loggedAt)
                ]
            )
            closeSheetAfterSuccessfulLog()
            Task {
                await appStore.refreshProfileDashboardSnapshot()
            }
        } catch {
            AppHaptics.error()
            actionErrorMessage = savedMealActionError(error, fallback: "Couldn’t log this meal.")
        }
        loggingMealId = nil
    }

    @MainActor
    private func deleteMeal(_ meal: SavedMeal) async {
        guard deletingMealId == nil, loggingMealId != meal.id else { return }
        deletingMealId = meal.id
        mealPendingDeletion = nil
        actionErrorMessage = nil
        confirmationMessage = nil
        do {
            _ = try await appStore.apiClient.deleteSavedMeal(id: meal.id)
            removeDeletedMealFromLocalState(meal)
            AppHaptics.success()
            confirmationMessage = "Deleted \(meal.name)"
        } catch {
            AppHaptics.error()
            actionErrorMessage = savedMealActionError(error, fallback: "Couldn’t delete this saved meal.")
        }
        deletingMealId = nil
    }

    private func savedMealActionError(_ error: Error, fallback: String) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? fallback
        if message.localizedCaseInsensitiveContains("endpoint not found") {
            return "This saved meal action is not available on the current backend yet. Please try again after the backend deploy finishes."
        }
        return message
    }

    private func removeDeletedMealFromLocalState(_ meal: SavedMeal) {
        meals.removeAll { $0.id == meal.id }
        collections = collections.map { collection in
            guard collection.id == meal.collectionId else { return collection }
            return SavedMealCollection(
                id: collection.id,
                name: collection.name,
                mealCount: max(collection.mealCount - 1, 0),
                createdAt: collection.createdAt,
                updatedAt: collection.updatedAt
            )
        }
        if let selectedCollectionId,
           !meals.contains(where: { $0.collectionId == selectedCollectionId }) {
            self.selectedCollectionId = nil
        }
    }

    private func closeSheetAfterSuccessfulLog() {
        guard case .sheet(let onClose) = presentationStyle else { return }
        onClose()
    }

    private func collectionFilterChip(
        title: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            if !isSelected {
                AppHaptics.selection()
            }
            action()
        }) {
            HStack(spacing: 8) {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isSelected ? .white : SavedMealsTokens.muted)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(isSelected ? SavedMealsTokens.orange : AppColor.surfaceChip)
                    )

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? SavedMealsTokens.orangeDeep : SavedMealsTokens.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? SavedMealsTokens.orangeWash : SavedMealsTokens.cardBackground)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? SavedMealsTokens.border : SavedMealsTokens.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SavedMealRow: View {
    let meal: SavedMeal
    let isLogging: Bool
    let isDeleting: Bool
    let onLog: () -> Void
    let onDeleteRequest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(meal.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SavedMealsTokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text("\(Int(meal.totals.calories.rounded())) kcal")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SavedMealsTokens.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppColor.surfaceChip, in: Capsule())

                Menu {
                    Button(role: .destructive, action: onDeleteRequest) {
                        Label("Delete saved meal", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SavedMealsTokens.muted)
                        .frame(width: 34, height: 34)
                        .background(AppColor.surfaceChip, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(SavedMealsTokens.hairline, lineWidth: 1)
                        }
                }
                .disabled(isLogging || isDeleting)
            }

            Text(meal.rawText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SavedMealsTokens.muted)
                .lineLimit(2)

            HStack(spacing: 8) {
                metadataPill(
                    "\(meal.collectionName)",
                    systemImage: "folder.fill"
                )
                metadataPill("\(meal.itemCount) item\(meal.itemCount == 1 ? "" : "s")")
                metadataPill("P \(Int(meal.totals.protein.rounded()))g")
                metadataPill("C \(Int(meal.totals.carbs.rounded()))g")
                metadataPill("F \(Int(meal.totals.fat.rounded()))g")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                AppHaptics.mediumImpact()
                onLog()
            }) {
                HStack {
                    if isLogging || isDeleting {
                        ProgressView()
                    }
                    Text(isDeleting ? "Deleting…" : (isLogging ? "Logging…" : "Log meal"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(SavedMealsTokens.orange)
            .disabled(isLogging || isDeleting)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [SavedMealsTokens.cardBackground, SavedMealsTokens.cardTint],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SavedMealsTokens.hairline, lineWidth: 1)
        }
        .shadow(color: SavedMealsTokens.shadow, radius: 14, y: 6)
    }

    private func metadataPill(_ text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(SavedMealsTokens.muted)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(AppColor.surfaceChip, in: Capsule())
    }
}

private struct SavedMealsSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(SavedMealsTokens.ink.opacity(0.82))
            .padding(.horizontal, 4)
    }
}

private struct SavedMealsConfirmationCard: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color(red: 0.122, green: 0.561, blue: 0.384))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(red: 0.943, green: 0.983, blue: 0.958), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(red: 0.122, green: 0.561, blue: 0.384).opacity(0.12), lineWidth: 1)
            }
    }
}

private struct SavedMealsActionErrorCard: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color(red: 0.82, green: 0.18, blue: 0.16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(red: 1.0, green: 0.945, blue: 0.925), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(red: 0.82, green: 0.18, blue: 0.16).opacity(0.12), lineWidth: 1)
            }
    }
}

private struct SavedMealsStatusCard: View {
    let icon: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(tint, in: Circle())

            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(SavedMealsTokens.ink)

            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SavedMealsTokens.muted)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(SavedMealsTokens.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SavedMealsTokens.hairline, lineWidth: 1)
        }
        .shadow(color: SavedMealsTokens.shadow, radius: 14, y: 6)
    }
}

private struct SavedMealsLoadingCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(SavedMealsTokens.orange)
            Text("Loading saved meals…")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SavedMealsTokens.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(SavedMealsTokens.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SavedMealsTokens.hairline, lineWidth: 1)
        }
        .shadow(color: SavedMealsTokens.shadow, radius: 14, y: 6)
    }
}
