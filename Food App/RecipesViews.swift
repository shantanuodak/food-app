import SwiftUI
import UIKit
import WebKit

private enum RecipesTokens {
    static let orange = AppColor.brandOrangeDeep
    static let orangeSoft = AppColor.brandOrangeSoft
    static let ink = AppColor.textPrimary
    static let muted = AppColor.textSecondary
    static let border = AppColor.borderHairline
    static let shadow = AppColor.shadow
    static let cardBackground = AppColor.surface
    static let cardTint = AppColor.surfaceWarm
    static let screenBackground = AppColor.surfaceWarm
    static let fieldBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.070, green: 0.070, blue: 0.072, alpha: 1)
            : UIColor.white
    })
    static let fieldBorder = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.16)
            : UIColor(red: 0.278, green: 0.176, blue: 0.098, alpha: 0.18)
    })
    static let insetSurface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.095, green: 0.095, blue: 0.100, alpha: 1)
            : UIColor(red: 0.988, green: 0.974, blue: 0.955, alpha: 1)
    })
    static let pressSurface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.07)
            : UIColor(red: 0.278, green: 0.176, blue: 0.098, alpha: 0.055)
    })
}

struct RecipesScreen: View {
    @EnvironmentObject private var appStore: AppStore

    private let pendingDraft: RecipeImportDraft?

    @State private var recipes: [SavedRecipe] = []
    @State private var importURL = ""
    @State private var isLoading = true
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var importErrorMessage: String?
    @State private var draftForReview: RecipeImportDraft?
    @State private var browserImportSession: RecipeBrowserImportSession?
    @State private var pendingAudioImport: RecipePendingAudioImport?
    @State private var selectedRecipe: SavedRecipe?
    @State private var recipePendingDeletion: SavedRecipe?
    @State private var didPresentPendingDraft = false

    init(pendingDraft: RecipeImportDraft? = nil, initialImportURL: String = "") {
        self.pendingDraft = pendingDraft
        _importURL = State(initialValue: initialImportURL)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                hero
                importCard

                if isLoading {
                    RecipesLoadingCard()
                } else if let errorMessage {
                    RecipesStatusCard(
                        icon: "exclamationmark.triangle.fill",
                        title: "Couldn’t load recipes",
                        message: errorMessage,
                        tint: .red
                    )
                } else if recipes.isEmpty {
                    RecipesStatusCard(
                        icon: "book.closed.fill",
                        title: "No recipes yet",
                        message: "Import a recipe page, review the ingredients and steps, then save it here.",
                        tint: RecipesTokens.orange
                    )
                } else {
                    recipesSection
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(RecipesTokens.screenBackground.ignoresSafeArea())
        .navigationTitle("Recipes")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadRecipes()
            presentPendingDraftIfNeeded()
            await importPendingRecipeURLIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recipeImportPendingURLDidChange)) { _ in
            Task { await importPendingRecipeURLIfNeeded() }
        }
        .refreshable { await loadRecipes() }
        .sheet(item: $draftForReview) { draft in
            RecipeReviewSheet(draft: draft) { savedRecipe in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    upsert(savedRecipe)
                    importURL = ""
                    draftForReview = nil
                }
            } onCancel: {
                draftForReview = nil
            }
            .environmentObject(appStore)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
        .sheet(item: $browserImportSession) { session in
            RecipeBrowserImportSheet(
                url: session.url,
                sourceHint: session.sourceHint,
                sharedText: session.sharedText
            ) { draft in
                if session.clearPendingURLOnSuccess {
                    RecipeImportPendingStore.clearPendingURL()
                }
                importURL = draft.sourceUrl
                browserImportSession = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    draftForReview = draft
                }
            } onCancel: {
                if session.clearPendingURLOnSuccess {
                    RecipeImportPendingStore.clearPendingURL()
                }
                browserImportSession = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
        .sheet(item: $selectedRecipe) { recipe in
            RecipeDetailView(recipe: recipe) {
                selectedRecipe = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
        .confirmationDialog(
            "Delete recipe?",
            isPresented: Binding(
                get: { recipePendingDeletion != nil },
                set: { if !$0 { recipePendingDeletion = nil } }
            ),
            presenting: recipePendingDeletion
        ) { recipe in
            Button("Delete recipe", role: .destructive) {
                AppHaptics.warning()
                Task { await deleteRecipe(recipe) }
            }
            Button("Cancel", role: .cancel) {
                AppHaptics.lightImpact()
                recipePendingDeletion = nil
            }
        } message: { recipe in
            Text("“\(recipe.title)” will be removed from your recipes. This can’t be undone.")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recipes")
                .font(OnboardingTypography.instrumentSerif(style: .regular, size: 44))
                .foregroundStyle(RecipesTokens.ink)

            Text("Save recipes you find online, then review the ingredients and steps before they land in your library.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(RecipesTokens.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Import from web page", systemImage: "safari")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(RecipesTokens.ink)

            HStack(spacing: 10) {
                TextField("Paste recipe URL", text: $importURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RecipesTokens.ink)

                Button {
                    AppHaptics.lightImpact()
                    pasteAndImport()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(RecipesTokens.orange, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paste recipe URL and review")
                .disabled(isImporting)
                .opacity(isImporting ? 0.55 : 1)
            }
            .padding(.leading, 16)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .background(RecipesTokens.fieldBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(RecipesTokens.orange)
                    .frame(width: 4)
                    .clipShape(Capsule())
                    .padding(.vertical, 11)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(RecipesTokens.fieldBorder, lineWidth: 1.25)
            }
            .shadow(color: RecipesTokens.shadow.opacity(0.65), radius: 8, y: 4)

            if let importErrorMessage {
                Text(importErrorMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
            }

            if let pendingAudioImport {
                sharedAudioImportCard(pendingAudioImport)
            }

            Button {
                AppHaptics.lightImpact()
                Task { await importRecipe() }
            } label: {
                HStack(spacing: 8) {
                    if isImporting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isImporting ? "Reading recipe" : "Review recipe")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RecipesTokens.orange, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isImporting || normalizedImportURL.isEmpty)
            .opacity(isImporting || normalizedImportURL.isEmpty ? 0.55 : 1)

            if let browserURL = URL(string: normalizedImportURL), isSupportedRecipeURL(normalizedImportURL) {
                let sourceHint = RecipeImportSourceHint.infer(url: browserURL)
                Button {
                    AppHaptics.lightImpact()
                    browserImportSession = RecipeBrowserImportSession(
                        url: browserURL,
                        sourceHint: sourceHint
                    )
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "safari")
                        Text(sourceHint.prefersBrowserImport ? "Open post to import" : "Open page to import")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(RecipesTokens.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RecipesTokens.cardTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(RecipesTokens.cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(RecipesTokens.border, lineWidth: 1)
        }
        .shadow(color: RecipesTokens.shadow, radius: 14, y: 6)
    }

    private func sharedAudioImportCard(_ pendingImport: RecipePendingAudioImport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(RecipesTokens.orange, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Shared video captured")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(RecipesTokens.ink)

                    Text("\(pendingImport.sourceHint.displayName) sent \(pendingImport.fileSummary). Use this only if the recipe is spoken in the video.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RecipesTokens.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                AppHaptics.lightImpact()
                Task { await importSharedAudio(pendingImport) }
            } label: {
                HStack(spacing: 8) {
                    if isImporting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "text.bubble.fill")
                    }
                    Text(isImporting ? "Transcribing audio" : "Import from shared audio")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RecipesTokens.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isImporting || pendingImport.sourceURL == nil)
            .opacity(isImporting || pendingImport.sourceURL == nil ? 0.55 : 1)

            if pendingImport.sourceURL == nil {
                Text("This share included media but not the original post link, so it cannot be imported yet.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(RecipesTokens.insetSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(RecipesTokens.fieldBorder, lineWidth: 1)
        }
    }

    private var recipesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let featured = recipes.first {
                Button {
                    AppHaptics.lightImpact()
                    selectedRecipe = featured
                } label: {
                    RecipeFeaturedCard(recipe: featured)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        recipePendingDeletion = featured
                    } label: {
                        Label("Delete recipe", systemImage: "trash")
                    }
                }
            }

            if recipes.count > 1 {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your library")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(RecipesTokens.ink)
                    Spacer()
                    Text("\(recipes.count)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(RecipesTokens.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(RecipesTokens.orangeSoft, in: Capsule())
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(Array(recipes.dropFirst())) { recipe in
                        Button {
                            AppHaptics.lightImpact()
                            selectedRecipe = recipe
                        } label: {
                            RecipeLibraryCard(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                recipePendingDeletion = recipe
                            } label: {
                                Label("Delete recipe", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var normalizedImportURL: String {
        RecipeImportURL.normalized(importURL)
    }

    private func loadRecipes() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await appStore.apiClient.getRecipes()
            recipes = response.recipes
                .sorted { ($0.updatedAt ?? $0.createdAt ?? "") > ($1.updatedAt ?? $1.createdAt ?? "") }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func importRecipe(
        clearPendingURLOnSuccess: Bool = false,
        sourceHint explicitSourceHint: RecipeImportSourceHint? = nil,
        sharedText: String? = nil
    ) async {
        let url = normalizedImportURL
        guard !url.isEmpty else { return }
        guard isSupportedRecipeURL(url) else {
            importErrorMessage = "Paste the full recipe link, including the website."
            return
        }

        guard let importURL = URL(string: url) else {
            importErrorMessage = "Paste the full recipe link, including the website."
            return
        }

        let sourceHint = explicitSourceHint ?? RecipeImportSourceHint.infer(url: importURL, text: sharedText)
        if sourceHint.prefersBrowserImport {
            importErrorMessage = "\(sourceHint.displayName) works best through the browser import path."
            browserImportSession = RecipeBrowserImportSession(
                url: importURL,
                clearPendingURLOnSuccess: clearPendingURLOnSuccess,
                sourceHint: sourceHint,
                sharedText: sharedText
            )
            return
        }

        isImporting = true
        importErrorMessage = nil

        do {
            let response = try await appStore.apiClient.importRecipeFromURL(RecipeImportRequest(url: url))
            if clearPendingURLOnSuccess {
                RecipeImportPendingStore.clearPendingURL()
            }
            draftForReview = response.draft
            isImporting = false
        } catch {
            if shouldUseBrowserImportFallback(error),
               let fallbackURL = URL(string: url) {
                importErrorMessage = "This site blocked direct import. Open it once, then tap Import from page."
                browserImportSession = RecipeBrowserImportSession(
                    url: fallbackURL,
                    clearPendingURLOnSuccess: clearPendingURLOnSuccess,
                    sourceHint: sourceHint,
                    sharedText: sharedText
                )
            } else {
                importErrorMessage = RecipeImportFailure.friendlyMessage(error)
                // Terminal failure (not a browser-import fallback): drop the
                // pending share payload so it doesn't silently retry on every
                // foreground. The user can re-share to try again.
                if clearPendingURLOnSuccess {
                    RecipeImportPendingStore.clearPendingURL()
                }
            }
            isImporting = false
        }
    }

    private func shouldUseBrowserImportFallback(_ error: Error) -> Bool {
        RecipeImportFailure.shouldFallBackToBrowser(error)
    }

    private func pasteAndImport() {
        guard let clipboardText = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardText.isEmpty else {
            importErrorMessage = "Copy a recipe link first, then tap Paste."
            return
        }

        if let embeddedURL = firstSupportedWebURL(in: clipboardText) {
            importURL = embeddedURL.absoluteString
        } else {
            importURL = clipboardText
        }

        let normalizedURL = normalizedImportURL
        guard isSupportedRecipeURL(normalizedURL) else {
            importErrorMessage = "Clipboard doesn’t look like a recipe link."
            return
        }

        Task { await importRecipe() }
    }

    private func importSharedAudio(_ pendingImport: RecipePendingAudioImport) async {
        guard !isImporting else { return }
        guard let sourceURL = pendingImport.sourceURL else {
            importErrorMessage = "This share did not include the original post link."
            return
        }

        isImporting = true
        importErrorMessage = nil

        do {
            let mediaAttachment = pendingImport.mediaAttachment
            let fileData = try Data(contentsOf: mediaAttachment.fileURL, options: .mappedIfSafe)
            let response = try await appStore.apiClient.importRecipeFromAudioFile(
                fileData: fileData,
                filename: mediaAttachment.originalFilename ?? mediaAttachment.fileURL.lastPathComponent,
                mimeType: mediaAttachment.mimeType ?? "application/octet-stream",
                sourceUrl: sourceURL.absoluteString,
                sourceName: pendingImport.sourceHint.displayName
            )
            importURL = sourceURL.absoluteString
            pendingAudioImport = nil
            draftForReview = response.draft
            isImporting = false
        } catch {
            importErrorMessage = error.localizedDescription
            isImporting = false
        }
    }

    private func presentPendingDraftIfNeeded() {
        guard !didPresentPendingDraft, let pendingDraft else { return }
        didPresentPendingDraft = true
        draftForReview = pendingDraft
    }

    private func importPendingRecipeURLIfNeeded() async {
        guard !isImporting,
              browserImportSession == nil,
              draftForReview == nil,
              let pendingPayload = RecipeImportPendingStore.pendingPayload() else {
            return
        }

        // Dedupe concurrent observers: a RecipesScreen already on-screen plus a
        // second one presented on a fresh share would otherwise both import the
        // same payload. Released on exit so a later re-trigger (e.g. after the
        // user signs in) can still run.
        guard RecipeImportPendingStore.beginProcessing(pendingPayload) else { return }
        defer { RecipeImportPendingStore.endProcessing() }

        if let mediaAttachment = pendingPayload.mediaAttachment {
            pendingAudioImport = RecipePendingAudioImport(
                sourceURL: pendingPayload.url,
                sourceHint: pendingPayload.sourceHint,
                mediaAttachment: mediaAttachment
            )
            if let pendingURL = pendingPayload.url {
                importURL = pendingURL.absoluteString
            }
            importErrorMessage = nil
            RecipeImportPendingStore.clearPendingURL()
            return
        }

        guard let pendingURL = pendingPayload.url else {
            importErrorMessage = "Received a share, but it did not include a recipe link."
            RecipeImportPendingStore.clearPendingURL()
            return
        }

        // Logged-out guard: don't dead-end on a "sign in required" error. KEEP
        // the pending payload so it imports automatically once the user signs
        // in — Food_AppApp re-posts .recipeImportPendingURLDidChange when
        // onboarding completes.
        guard appStore.authSessionStore.session != nil else {
            importURL = pendingURL.absoluteString
            importErrorMessage = "Sign in to import this recipe — it’ll be saved and ready as soon as you’re back in."
            return
        }

        importURL = pendingURL.absoluteString
        await importRecipe(
            clearPendingURLOnSuccess: true,
            sourceHint: pendingPayload.sourceHint,
            sharedText: pendingPayload.rawText
        )
    }

    private func upsert(_ recipe: SavedRecipe) {
        recipes.removeAll { $0.id == recipe.id }
        recipes.insert(recipe, at: 0)
    }

    private func deleteRecipe(_ recipe: SavedRecipe) async {
        do {
            try await appStore.apiClient.deleteRecipe(id: recipe.id)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                recipes.removeAll { $0.id == recipe.id }
            }
            if selectedRecipe?.id == recipe.id { selectedRecipe = nil }
        } catch {
            importErrorMessage = RecipeImportFailure.friendlyMessage(error)
        }
        recipePendingDeletion = nil
    }

    private func isSupportedRecipeURL(_ rawURL: String) -> Bool {
        RecipeImportURL.isSupported(rawURL)
    }

    private func firstSupportedWebURL(in text: String) -> URL? {
        RecipeImportURL.firstSupportedWebURL(in: text)
    }
}

struct RecipeBrowserImportSession: Identifiable {
    let id = UUID()
    let url: URL
    var clearPendingURLOnSuccess = false
    var sourceHint: RecipeImportSourceHint = .genericWeb
    var sharedText: String?
}

private struct RecipePendingAudioImport: Identifiable {
    let id = UUID()
    let sourceURL: URL?
    let sourceHint: RecipeImportSourceHint
    let mediaAttachment: RecipeImportPendingMediaAttachment

    var fileSummary: String {
        let type = mediaAttachment.mimeType ?? mediaAttachment.typeIdentifier ?? "media file"
        guard let byteCount = mediaAttachment.byteCount else {
            return type
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(byteCount))) \(type)"
    }
}

struct RecipeBrowserImportSheet: View {
    let url: URL
    let sourceHint: RecipeImportSourceHint
    let sharedText: String?
    let onImported: (RecipeImportDraft) -> Void
    let onCancel: () -> Void

    @State private var webView = WKWebView()
    @State private var isExtracting = false
    @State private var errorMessage: String?
    @State private var isTextFallbackExpanded: Bool
    @State private var manualRecipeText: String
    @State private var textFallbackErrorMessage: String?

    init(
        url: URL,
        sourceHint: RecipeImportSourceHint = .genericWeb,
        sharedText: String? = nil,
        onImported: @escaping (RecipeImportDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.url = url
        self.sourceHint = sourceHint
        self.sharedText = sharedText
        self.onImported = onImported
        self.onCancel = onCancel
        _manualRecipeText = State(initialValue: sharedText ?? "")
        _isTextFallbackExpanded = State(initialValue: sharedText?.isEmpty == false)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RecipeBrowserView(webView: webView, url: url)

                VStack(alignment: .leading, spacing: 12) {
                    Text(sourceHint.browserImportInstruction)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RecipesTokens.muted)

                    if let errorMessage {
                        RecipeBrowserImportInlineError(message: errorMessage)
                    }

                    Button {
                        AppHaptics.lightImpact()
                        Task { await importFromLoadedPage() }
                    } label: {
                        HStack(spacing: 8) {
                            if isExtracting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isExtracting ? "Reading page" : "Import from page")
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RecipesTokens.orange, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isExtracting)
                    .opacity(isExtracting ? 0.65 : 1)

                    if sourceHint.prefersBrowserImport || errorMessage != nil || !manualRecipeText.isEmpty {
                        textFallbackCard
                    }
                }
                .padding(16)
                .background(RecipesTokens.cardBackground)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(RecipesTokens.border)
                        .frame(height: 1)
                }
            }
            .background(RecipesTokens.screenBackground.ignoresSafeArea())
            .navigationTitle(sourceHint.browserImportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        AppHaptics.lightImpact()
                        onCancel()
                    }
                }
            }
        }
    }

    private var textFallbackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                AppHaptics.lightImpact()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    isTextFallbackExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(RecipesTokens.orange)
                        .frame(width: 32, height: 32)
                        .background(RecipesTokens.orangeSoft, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Caption or recipe text")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(RecipesTokens.ink)

                        Text("Paste text if the recipe is in the post or video.")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(RecipesTokens.muted)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isTextFallbackExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(RecipesTokens.muted)
                }
            }
            .buttonStyle(.plain)

            if isTextFallbackExpanded {
                TextEditor(text: $manualRecipeText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(RecipesTokens.ink)
                    .frame(minHeight: 104)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(RecipesTokens.fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(RecipesTokens.fieldBorder, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if manualRecipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Paste caption, ingredients, or a quick transcript...")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(RecipesTokens.muted.opacity(0.72))
                                .padding(.horizontal, 15)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }

                if let textFallbackErrorMessage {
                    Text(textFallbackErrorMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button {
                        AppHaptics.lightImpact()
                        pasteRecipeText()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(RecipesTokens.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RecipesTokens.pressSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        AppHaptics.lightImpact()
                        importFromRecipeText()
                    } label: {
                        Label("Review text", systemImage: "sparkles")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RecipesTokens.orange, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(manualRecipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(manualRecipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
                }
            }
        }
        .padding(12)
        .background(RecipesTokens.insetSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(RecipesTokens.fieldBorder, lineWidth: 1)
        }
    }

    @MainActor
    private func importFromLoadedPage() async {
        isExtracting = true
        errorMessage = nil

        do {
            let result = try await webView.evaluateJavaScript(RecipeBrowserImportJavaScript.extractRecipe)
            guard let json = result as? String,
                  let data = json.data(using: .utf8) else {
                throw RecipeBrowserImportError.unreadableResponse
            }

            let payload = try JSONDecoder().decode(RecipeBrowserExtractionPayload.self, from: data)
            if payload.error != nil {
                if let draft = sharedTextFallbackDraft() {
                    isExtracting = false
                    onImported(draft)
                    return
                }
                throw RecipeBrowserImportError.noRecipeData
            }

            let draft = try payload.draft(fallbackURL: url)
            isExtracting = false
            onImported(draft)
        } catch let error as RecipeBrowserImportError {
            if let draft = sharedTextFallbackDraft() {
                isExtracting = false
                onImported(draft)
            } else {
                errorMessage = browserImportErrorMessage(for: error)
                isExtracting = false
            }
        } catch {
            if let draft = sharedTextFallbackDraft() {
                isExtracting = false
                onImported(draft)
            } else {
                errorMessage = "Couldn’t read this page yet. Wait for it to finish loading, then try again."
                isExtracting = false
            }
        }
    }

    private func browserImportErrorMessage(for error: RecipeBrowserImportError) -> String {
        if sourceHint.prefersBrowserImport,
           error == .noRecipeData || error == .missingTitleOrIngredients {
            return "\(sourceHint.displayName) didn’t expose ingredients or steps. Paste the caption or recipe text below if you have it."
        }
        return error.localizedDescription
    }

    private func sharedTextFallbackDraft() -> RecipeImportDraft? {
        RecipeSharedTextParser.draft(
            from: manualRecipeText.isEmpty ? sharedText : manualRecipeText,
            fallbackURL: url,
            sourceHint: sourceHint
        )
    }

    private func pasteRecipeText() {
        guard let clipboardText = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardText.isEmpty else {
            textFallbackErrorMessage = "Copy the caption or recipe text first."
            return
        }

        manualRecipeText = clipboardText
        textFallbackErrorMessage = nil
    }

    private func importFromRecipeText() {
        guard let draft = RecipeSharedTextParser.draft(
            from: manualRecipeText,
            fallbackURL: url,
            sourceHint: sourceHint
        ) else {
            textFallbackErrorMessage = "Couldn’t find enough ingredient lines. Paste the full caption or typed recipe."
            return
        }

        textFallbackErrorMessage = nil
        onImported(draft)
    }
}

private struct RecipeBrowserImportInlineError: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.red)
                .padding(.top, 1)

            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RecipesTokens.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.red.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct RecipeBrowserView: UIViewRepresentable {
    let webView: WKWebView
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = true
        if webView.url == nil {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url == nil {
            uiView.load(URLRequest(url: url))
        }
    }
}

private enum RecipeBrowserImportError: LocalizedError, Equatable {
    case unreadableResponse
    case noRecipeData
    case missingTitleOrIngredients

    var errorDescription: String? {
        switch self {
        case .unreadableResponse:
            return "The page response could not be read. Reload the page, then try again."
        case .noRecipeData:
            return "Couldn’t find recipe data on this page. Open the full recipe page, wait for it to load, then try again."
        case .missingTitleOrIngredients:
            return "This page did not expose enough recipe details to import safely."
        }
    }
}

private struct RecipeBrowserExtractionPayload: Decodable {
    let error: String?
    let title: String?
    let sourceUrl: String?
    let sourceDomain: String?
    let sourceName: String?
    let heroImageUrl: String?
    let servings: String?
    let ingredients: [String]?
    let steps: [String]?
    let confidence: Double?
    let warnings: [String]?

    func draft(fallbackURL: URL) throws -> RecipeImportDraft {
        let cleanedTitle = Self.clean(title)
        let cleanedIngredients = Self.cleanLines(ingredients ?? [])
        guard let cleanedTitle, !cleanedIngredients.isEmpty else {
            throw RecipeBrowserImportError.missingTitleOrIngredients
        }

        let cleanedSteps = Self.cleanLines(steps ?? [])
        var warningMessages = Self.cleanLines(warnings ?? [])
        if cleanedSteps.isEmpty {
            warningMessages.append("No instructions were found. Add them before saving if needed.")
        }

        return RecipeImportDraft(
            title: cleanedTitle,
            sourceUrl: Self.clean(sourceUrl) ?? fallbackURL.absoluteString,
            sourceDomain: Self.clean(sourceDomain) ?? fallbackURL.host,
            sourceName: Self.clean(sourceName),
            heroImageUrl: RecipeBrowserExtractionPayload.cleanHTTPURL(heroImageUrl),
            servings: Self.clean(servings),
            ingredients: cleanedIngredients,
            steps: cleanedSteps,
            confidence: confidence,
            warnings: warningMessages
        )
    }

    nonisolated private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    nonisolated private static func cleanLines(_ values: [String]) -> [String] {
        values
            .compactMap(Self.clean)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }
            .filter { !$0.isEmpty }
    }

    nonisolated private static func cleanHTTPURL(_ value: String?) -> String? {
        guard let value = Self.clean(value),
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url.absoluteString
    }
}

private enum RecipeSharedTextParser {
    static func draft(
        from rawText: String?,
        fallbackURL: URL,
        sourceHint: RecipeImportSourceHint
    ) -> RecipeImportDraft? {
        guard let rawText else { return nil }

        let lines = splitLines(rawText)
        let contentLines = lines.filter { !isURLLine($0) && !isNoiseLine($0) }
        guard !contentLines.isEmpty else { return nil }

        let ingredients = ingredientLines(from: contentLines)
        guard ingredients.count >= 2 else { return nil }

        let steps = stepLines(from: contentLines)
        let title = title(from: contentLines) ?? "\(sourceHint.displayName) recipe"
        var warnings = ["Imported from shared text. Review before saving."]
        if steps.isEmpty {
            warnings.append("No clear instructions were found in the shared text.")
        }

        return RecipeImportDraft(
            title: title,
            sourceUrl: fallbackURL.absoluteString,
            sourceDomain: fallbackURL.host,
            sourceName: sourceHint.displayName,
            heroImageUrl: nil,
            servings: nil,
            ingredients: ingredients,
            steps: steps,
            confidence: 0.48,
            warnings: warnings
        )
    }

    nonisolated private static func splitLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\u{2022}", with: "\n")
            .replacingOccurrences(of: "•", with: "\n")
            .replacingOccurrences(of: "·", with: "\n")
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: "  ") }
            .map(cleanLine)
            .filter { !$0.isEmpty }
    }

    nonisolated private static func ingredientLines(from lines: [String]) -> [String] {
        let lowercased = lines.map { $0.lowercased() }
        let ingredientStart = lowercased.firstIndex { $0.contains("ingredient") }
        let stepStart = lowercased.firstIndex { isStepHeader($0) }

        let sectionLines: [String]
        if let ingredientStart {
            let start = lines.index(after: ingredientStart)
            let end = stepStart.map { max(start, $0) } ?? lines.endIndex
            sectionLines = start < end ? Array(lines[start..<end]) : []
        } else {
            sectionLines = lines
        }

        return unique(
            sectionLines
                .map { stripListMarker($0) }
                .filter(looksLikeIngredient)
        )
    }

    nonisolated private static func stepLines(from lines: [String]) -> [String] {
        let lowercased = lines.map { $0.lowercased() }
        let stepStart = lowercased.firstIndex { isStepHeader($0) }

        let sectionLines: [String]
        if let stepStart {
            let start = lines.index(after: stepStart)
            sectionLines = start < lines.endIndex ? Array(lines[start..<lines.endIndex]) : []
        } else {
            sectionLines = lines.filter { $0.range(of: #"^\s*\d+[\.)]\s+"#, options: .regularExpression) != nil }
        }

        return unique(
            sectionLines
                .map { stripListMarker($0) }
                .filter { line in
                    !line.isEmpty &&
                    !looksLikeIngredient(line) &&
                    line.count >= 12
                }
        )
    }

    nonisolated private static func title(from lines: [String]) -> String? {
        lines.first { line in
            !line.localizedCaseInsensitiveContains("ingredient") &&
            !isStepHeader(line.lowercased()) &&
            !looksLikeIngredient(line) &&
            line.count <= 80
        }
    }

    nonisolated private static func looksLikeIngredient(_ line: String) -> Bool {
        guard line.count <= 120 else { return false }
        let lower = line.lowercased()
        if lower.range(of: #"(^|\s)(\d+|[¼½¾⅓⅔⅛⅜⅝⅞])"#, options: .regularExpression) != nil {
            return true
        }
        return lower.range(
            of: #"\b(cup|cups|tbsp|tablespoon|tablespoons|tsp|teaspoon|teaspoons|gram|grams|kg|g|ml|liter|litre|oz|ounce|ounces|lb|lbs|pound|pounds|pinch|clove|cloves|can|cans|packet|packets|stick|sticks|slice|slices)\b"#,
            options: .regularExpression
        ) != nil
    }

    nonisolated private static func isStepHeader(_ line: String) -> Bool {
        line.contains("instruction") ||
        line.contains("direction") ||
        line.contains("method") ||
        line.contains("preparation") ||
        line == "steps" ||
        line == "step"
    }

    nonisolated private static func isURLLine(_ line: String) -> Bool {
        line.lowercased().hasPrefix("http://") || line.lowercased().hasPrefix("https://")
    }

    nonisolated private static func isNoiseLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.hasPrefix("#") ||
        lower.hasPrefix("@") ||
        lower == "recipe" ||
        lower == "link in bio"
    }

    nonisolated private static func stripListMarker(_ line: String) -> String {
        cleanLine(
            line.replacingOccurrences(
                of: #"^\s*([-*]|\d+[\.)])\s*"#,
                with: "",
                options: .regularExpression
            )
        )
    }

    nonisolated private static func cleanLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func unique(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.filter { line in
            let key = line.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}

private enum RecipeBrowserImportJavaScript {
    static let extractRecipe = #"""
(() => {
  const clean = (value) => {
    if (value === null || value === undefined) return "";
    if (typeof value === "number" || typeof value === "boolean") return String(value);
    if (typeof value !== "string") return "";
    return value.replace(/\u00a0/g, " ").replace(/\s+/g, " ").trim();
  };

  const asArray = (value) => {
    if (value === null || value === undefined) return [];
    return Array.isArray(value) ? value : [value];
  };

  const uniqueClean = (values) => {
    const seen = new Set();
    return values
      .map(clean)
      .filter(Boolean)
      .filter((value) => {
        const key = value.toLowerCase();
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
      });
  };

  const host = window.location.hostname.replace(/^www\./, "");
  const sourceName = host
    .split(".")
    .filter(Boolean)
    .slice(0, -1)
    .join(" ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase()) || host;

  const recipeType = (value) => asArray(value).some((type) => clean(type).toLowerCase() === "recipe");

  const collectRecipeNodes = (node, output = []) => {
    if (!node || typeof node !== "object") return output;
    if (Array.isArray(node)) {
      node.forEach((child) => collectRecipeNodes(child, output));
      return output;
    }
    if (recipeType(node["@type"])) output.push(node);
    collectRecipeNodes(node["@graph"], output);
    collectRecipeNodes(node.mainEntity, output);
    return output;
  };

  const imageURL = (value) => {
    for (const item of asArray(value)) {
      if (typeof item === "string") {
        const url = clean(item);
        if (url) return url;
      }
      if (item && typeof item === "object") {
        const url = clean(item.url || item.contentUrl || item.src);
        if (url) return url;
      }
    }
    return "";
  };

  const instructionLines = (value) => {
    if (typeof value === "string" || typeof value === "number") return [clean(value)].filter(Boolean);
    if (Array.isArray(value)) return value.flatMap(instructionLines);
    if (!value || typeof value !== "object") return [];
    if (value.itemListElement) return instructionLines(value.itemListElement);
    if (value.steps) return instructionLines(value.steps);
    return [clean(value.text || value.name)].filter(Boolean);
  };

  const ingredientLines = (value) => {
    if (typeof value === "string" || typeof value === "number") return [clean(value)].filter(Boolean);
    if (Array.isArray(value)) return value.flatMap(ingredientLines);
    if (!value || typeof value !== "object") return [];
    return [clean(value.text || value.name || value.rawText)].filter(Boolean);
  };

  const fromRecipeNode = (recipe) => ({
    title: clean(recipe.name || recipe.headline || document.querySelector("h1")?.innerText || document.title),
    sourceUrl: window.location.href,
    sourceDomain: host,
    sourceName,
    heroImageUrl: imageURL(recipe.image || recipe.thumbnailUrl),
    servings: clean(recipe.recipeYield || recipe.yield || recipe.servings),
    ingredients: uniqueClean(ingredientLines(recipe.recipeIngredient || recipe.ingredients)),
    steps: uniqueClean(instructionLines(recipe.recipeInstructions || recipe.instructions)),
    confidence: 0.9,
    warnings: []
  });

  const textFromSelector = (selector) =>
    Array.from(document.querySelectorAll(selector))
      .map((node) => clean(node.innerText || node.textContent))
      .filter(Boolean);

  const visibleFallback = () => {
    const ingredientSelectors = [
      "[itemprop='recipeIngredient']",
      "[data-ingredient-name]",
      ".wprm-recipe-ingredient",
      ".tasty-recipes-ingredients li",
      ".recipe-ingredients li",
      ".ingredients li",
      ".ingredient-list li"
    ];
    const stepSelectors = [
      "[itemprop='recipeInstructions'] [itemprop='text']",
      ".wprm-recipe-instruction",
      ".tasty-recipes-instructions li",
      ".recipe-instructions li",
      ".instructions li",
      ".directions li",
      ".method li"
    ];
    const ingredients = uniqueClean(ingredientSelectors.flatMap(textFromSelector));
    const steps = uniqueClean(stepSelectors.flatMap(textFromSelector));
    return {
      title: clean(document.querySelector("h1")?.innerText || document.title),
      sourceUrl: window.location.href,
      sourceDomain: host,
      sourceName,
      heroImageUrl: clean(document.querySelector("meta[property='og:image']")?.content || ""),
      servings: clean(document.querySelector("[itemprop='recipeYield']")?.innerText || ""),
      ingredients,
      steps,
      confidence: ingredients.length > 0 ? 0.68 : 0,
      warnings: steps.length === 0 ? ["Review the steps; this page did not expose clear instructions."] : []
    };
  };

  const cleanLine = (value) => {
    if (value === null || value === undefined) return "";
    return String(value).replace(/\u00a0/g, " ").replace(/[ \t]+/g, " ").trim();
  };

  const splitRecipeText = (text) =>
    String(text || "")
      .replace(/[•·]/g, "\n")
      .split(/\n+| {2,}/)
      .map(cleanLine)
      .filter(Boolean)
      .filter((line) => !/^https?:\/\//i.test(line) && !/^[@#]/.test(line));

  const stripListMarker = (line) => cleanLine(line.replace(/^\s*([-*]|\d+[\.)])\s*/, ""));

  const looksLikeIngredient = (line) => {
    const value = cleanLine(line).toLowerCase();
    if (!value || value.length > 120) return false;
    if (/(^|\s)(\d+|[¼½¾⅓⅔⅛⅜⅝⅞])/.test(value)) return true;
    return /\b(cup|cups|tbsp|tablespoon|tablespoons|tsp|teaspoon|teaspoons|gram|grams|kg|g|ml|liter|litre|oz|ounce|ounces|lb|lbs|pound|pounds|pinch|clove|cloves|can|cans|packet|packets|stick|sticks|slice|slices)\b/.test(value);
  };

  const isStepHeader = (line) => /instruction|direction|method|preparation|^steps?$/.test(cleanLine(line).toLowerCase());

  const parseRecipeTextBlock = (text) => {
    const lines = splitRecipeText(text).slice(0, 140);
    const lower = lines.map((line) => line.toLowerCase());
    const ingredientStart = lower.findIndex((line) => line.includes("ingredient"));
    const stepStart = lower.findIndex(isStepHeader);
    const ingredientSection = ingredientStart >= 0
      ? lines.slice(ingredientStart + 1, stepStart >= ingredientStart ? stepStart : lines.length)
      : lines;
    const stepSection = stepStart >= 0
      ? lines.slice(stepStart + 1)
      : lines.filter((line) => /^\s*\d+[\.)]\s+/.test(line));
    const ingredients = uniqueClean(ingredientSection.map(stripListMarker).filter(looksLikeIngredient));
    const steps = uniqueClean(stepSection.map(stripListMarker).filter((line) => line.length >= 12 && !looksLikeIngredient(line)));
    const title = clean(lines.find((line) =>
      line.length <= 80 &&
      !line.toLowerCase().includes("ingredient") &&
      !isStepHeader(line) &&
      !looksLikeIngredient(line)
    ) || document.querySelector("h1")?.innerText || document.title);

    return {
      title,
      sourceUrl: window.location.href,
      sourceDomain: host,
      sourceName,
      heroImageUrl: clean(document.querySelector("meta[property='og:image']")?.content || ""),
      servings: "",
      ingredients,
      steps,
      confidence: ingredients.length >= 2 ? 0.42 : 0,
      warnings: ["Imported from visible page text. Review before saving."]
    };
  };

  const socialTextFallback = () => {
    const blocks = [
      document.querySelector("meta[property='og:description']")?.content,
      document.querySelector("meta[name='description']")?.content,
      ...Array.from(document.querySelectorAll("[data-e2e='browse-video-desc'], [data-testid='post_message'], article, [role='article']"))
        .map((node) => node.innerText || node.textContent)
    ].filter(Boolean);
    return blocks
      .map((text) => parseRecipeTextBlock(String(text).slice(0, 6000)))
      .sort((left, right) => right.ingredients.length - left.ingredients.length)[0] || parseRecipeTextBlock("");
  };

  const candidates = [];
  document.querySelectorAll("script[type='application/ld+json']").forEach((script) => {
    try {
      const parsed = JSON.parse(script.textContent || "");
      collectRecipeNodes(parsed).forEach((node) => candidates.push(fromRecipeNode(node)));
    } catch (_) {}
  });
  candidates.push(visibleFallback());
  candidates.push(socialTextFallback());

  const score = (candidate) =>
    (candidate.title ? 10 : 0) +
    Math.min(candidate.ingredients.length, 20) * 3 +
    Math.min(candidate.steps.length, 12) * 2 +
    (candidate.heroImageUrl ? 2 : 0);

  const best = candidates
    .filter((candidate) => candidate && candidate.title && candidate.ingredients.length > 0)
    .sort((left, right) => score(right) - score(left))[0];

  if (!best) return JSON.stringify({ error: "NO_RECIPE_DATA" });
  return JSON.stringify(best);
})()
"""#
}

private struct SavedRecipeCard: View {
    let recipe: SavedRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail

                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(RecipesTokens.ink)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let sourceLabel {
                            Label(sourceLabel, systemImage: "link")
                        }

                        if let servings = recipe.servings, !servings.isEmpty {
                            Label(servings, systemImage: "person.2")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RecipesTokens.muted)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(RecipesTokens.muted)
                    .frame(width: 30, height: 30)
                    .background(RecipesTokens.pressSurface, in: Circle())
            }

            HStack(spacing: 10) {
                RecipeCountPill(value: recipe.ingredients.count, label: "ingredients")
                RecipeCountPill(value: recipe.steps.count, label: "steps")
            }
        }
        .padding(14)
        .background(RecipesTokens.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(RecipesTokens.border, lineWidth: 1)
        }
        .shadow(color: RecipesTokens.shadow, radius: 14, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var thumbnail: some View {
        Group {
            if let heroImageUrl = recipe.heroImageUrl,
               let url = URL(string: heroImageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholderThumbnail
                    }
                }
            } else {
                placeholderThumbnail
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var placeholderThumbnail: some View {
        ZStack {
            RecipesTokens.cardTint
            Image(systemName: "book.closed.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(RecipesTokens.orange)
        }
    }

    private var sourceLabel: String? {
        if let sourceName = recipe.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceName.isEmpty {
            return sourceName
        }
        if let sourceDomain = recipe.sourceDomain?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceDomain.isEmpty {
            return sourceDomain
        }
        return nil
    }
}

private struct SavedRecipeDetailSheet: View {
    let recipe: SavedRecipe
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    summaryCard
                    RecipeReadOnlyLineSection(
                        title: "Ingredients",
                        icon: "carrot.fill",
                        lines: recipe.ingredients.map(\.text)
                    )
                    RecipeReadOnlyLineSection(
                        title: "Steps",
                        icon: "list.number",
                        lines: recipe.steps.map(\.text)
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .background(RecipesTokens.screenBackground.ignoresSafeArea())
            .navigationTitle("Saved recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        AppHaptics.lightImpact()
                        onClose()
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let sourceLabel {
                Label(sourceLabel, systemImage: "link")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RecipesTokens.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RecipesTokens.orangeSoft, in: Capsule())
            }

            Text(recipe.title)
                .font(OnboardingTypography.instrumentSerif(style: .regular, size: 40))
                .foregroundStyle(RecipesTokens.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCard: some View {
        HStack(spacing: 12) {
            RecipeMetricTile(value: "\(recipe.ingredients.count)", label: "Ingredients", icon: "carrot.fill")
            RecipeMetricTile(value: "\(recipe.steps.count)", label: "Steps", icon: "list.number")
        }
    }

    private var sourceLabel: String? {
        if let sourceName = recipe.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceName.isEmpty {
            return sourceName
        }
        if let sourceDomain = recipe.sourceDomain?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceDomain.isEmpty {
            return sourceDomain
        }
        return URL(string: recipe.sourceUrl ?? "")?.host
    }
}

private struct RecipeMetricTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(RecipesTokens.orange)
                .frame(width: 34, height: 34)
                .background(RecipesTokens.orangeSoft, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(RecipesTokens.ink)

                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(RecipesTokens.muted)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RecipesTokens.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(RecipesTokens.fieldBorder, lineWidth: 1)
        }
    }
}

private struct RecipeReadOnlyLineSection: View {
    let title: String
    let icon: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(RecipesTokens.orange)

                Text(title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(RecipesTokens.ink)

                Spacer(minLength: 0)

                Text("\(lines.count)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(RecipesTokens.orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(RecipesTokens.orangeSoft, in: Capsule())
            }

            VStack(spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    RecipeReadOnlyLineRow(index: index + 1, text: line)
                }
            }
        }
        .padding(14)
        .background(RecipesTokens.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(RecipesTokens.fieldBorder, lineWidth: 1)
        }
    }
}

private struct RecipeReadOnlyLineRow: View {
    let index: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(RecipesTokens.orange)
                .frame(width: 24, height: 24)
                .background(RecipesTokens.orangeSoft, in: Circle())

            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RecipesTokens.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RecipesTokens.fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RecipesTokens.fieldBorder, lineWidth: 1)
        }
    }
}

private struct RecipeCountPill: View {
    let value: Int
    let label: String

    var body: some View {
        Text("\(value) \(label)")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(RecipesTokens.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RecipesTokens.cardTint, in: Capsule())
    }
}

struct RecipeReviewSheet: View {
    @EnvironmentObject private var appStore: AppStore

    @State private var draft: RecipeImportDraft
    @State private var ingredientsText: String
    @State private var stepsText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    let onSaved: (SavedRecipe) -> Void
    let onCancel: () -> Void

    init(
        draft: RecipeImportDraft,
        onSaved: @escaping (SavedRecipe) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        _ingredientsText = State(initialValue: draft.ingredients.joined(separator: "\n"))
        _stepsText = State(initialValue: draft.steps.joined(separator: "\n"))
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    editableFields

                    if !draft.warnings.isEmpty {
                        warningsCard
                    }

                    if let errorMessage {
                        RecipesStatusCard(
                            icon: "exclamationmark.triangle.fill",
                            title: "Couldn’t save recipe",
                            message: errorMessage,
                            tint: .red
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .background(RecipesTokens.screenBackground.ignoresSafeArea())
            .navigationTitle("Review recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        AppHaptics.lightImpact()
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") {
                        AppHaptics.lightImpact()
                        Task { await saveRecipe() }
                    }
                    .disabled(isSaving || !canSave)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Check the scrape")
                .font(OnboardingTypography.instrumentSerif(style: .regular, size: 38))
                .foregroundStyle(RecipesTokens.ink)

            if let sourceLabel {
                Label(sourceLabel, systemImage: "link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RecipesTokens.muted)
            }
        }
    }

    private var editableFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            RecipeReviewField(title: "Title") {
                TextField("Recipe title", text: $draft.title)
                    .font(.system(size: 16, weight: .semibold))
                    .textInputAutocapitalization(.words)
            }

            if draft.servings != nil {
                RecipeReviewField(title: "Servings") {
                    TextField("Servings", text: Binding(
                        get: { draft.servings ?? "" },
                        set: { draft.servings = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                    ))
                    .font(.system(size: 16, weight: .semibold))
                }
            }

            RecipeReviewField(title: "Ingredients") {
                TextEditor(text: $ingredientsText)
                    .font(.system(size: 15, weight: .medium))
                    .frame(minHeight: 156)
                    .scrollContentBackground(.hidden)
            }

            RecipeReviewField(title: "Steps") {
                TextEditor(text: $stepsText)
                    .font(.system(size: 15, weight: .medium))
                    .frame(minHeight: 190)
                    .scrollContentBackground(.hidden)
            }
        }
    }

    private var warningsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Needs a quick look", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(RecipesTokens.orange)

            ForEach(draft.warnings, id: \.self) { warning in
                Text(warning)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RecipesTokens.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RecipesTokens.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(RecipesTokens.border, lineWidth: 1)
        }
    }

    private var sourceLabel: String? {
        if let sourceName = draft.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceName.isEmpty {
            return sourceName
        }
        if let sourceDomain = draft.sourceDomain?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceDomain.isEmpty {
            return sourceDomain
        }
        return URL(string: draft.sourceUrl)?.host
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !normalizedLines(from: ingredientsText).isEmpty
    }

    private func saveRecipe() async {
        guard canSave else { return }

        isSaving = true
        errorMessage = nil

        var requestDraft = draft
        requestDraft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        requestDraft.ingredients = normalizedLines(from: ingredientsText)
        requestDraft.steps = normalizedLines(from: stepsText)

        do {
            let response = try await appStore.apiClient.createRecipe(CreateRecipeRequest(draft: requestDraft))
            isSaving = false
            onSaved(response.recipe)
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    private func normalizedLines(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct RecipeReviewField<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(RecipesTokens.muted)
                .textCase(.uppercase)
                .tracking(0.8)

            content
                .foregroundStyle(RecipesTokens.ink)
                .padding(12)
                .background(RecipesTokens.fieldBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(RecipesTokens.fieldBorder, lineWidth: 1.15)
                }
        }
        .padding(14)
        .background(RecipesTokens.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(RecipesTokens.border, lineWidth: 1)
        }
    }
}

private struct RecipesStatusCard: View {
    let icon: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(RecipesTokens.ink)

                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(RecipesTokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RecipesTokens.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(RecipesTokens.border, lineWidth: 1)
        }
        .shadow(color: RecipesTokens.shadow, radius: 14, y: 6)
    }
}

private struct RecipesLoadingCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(RecipesTokens.orange)
            Text("Loading recipes")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RecipesTokens.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RecipesTokens.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(RecipesTokens.border, lineWidth: 1)
        }
        .shadow(color: RecipesTokens.shadow, radius: 14, y: 6)
    }
}

// ============================================================================
// MARK: - Recipe experience redesign (2026-05-29)
// Editorial, image-forward recipe Library + magazine-style Detail. Fully
// data-driven (renders from SavedRecipe) so it previews in VisualQA with
// sample data and can be swapped into RecipesScreen once approved. Reuses the
// app design system: AppColor tokens + Instrument Serif display type.
// ============================================================================

private enum RecipeDS {
    // Appetizing duotone gradients used when a recipe has no photo (or while it
    // loads). Deterministic per title so a recipe always gets the same look.
    static let gradients: [[Color]] = [
        [Color(red: 0.96, green: 0.49, blue: 0.22), Color(red: 0.85, green: 0.26, blue: 0.20)], // terracotta
        [Color(red: 0.99, green: 0.74, blue: 0.30), Color(red: 0.90, green: 0.45, blue: 0.13)], // amber
        [Color(red: 0.42, green: 0.72, blue: 0.53), Color(red: 0.16, green: 0.49, blue: 0.41)], // herb
        [Color(red: 0.56, green: 0.55, blue: 0.93), Color(red: 0.36, green: 0.32, blue: 0.78)], // periwinkle
        [Color(red: 0.94, green: 0.43, blue: 0.56), Color(red: 0.77, green: 0.23, blue: 0.45)], // berry
        [Color(red: 0.44, green: 0.69, blue: 0.87), Color(red: 0.19, green: 0.44, blue: 0.73)]  // sky
    ]

    static let glyphs = ["fork.knife", "carrot.fill", "cup.and.saucer.fill", "flame.fill", "leaf.fill", "birthday.cake.fill"]

    private static func stableHash(_ seed: String, _ salt: UInt32) -> UInt32 {
        seed.unicodeScalars.reduce(salt) { ($0 &* 31) &+ $1.value }
    }

    static func gradient(for seed: String) -> LinearGradient {
        let pair = gradients[Int(stableHash(seed, 7) % UInt32(gradients.count))]
        return LinearGradient(colors: pair, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func glyph(for seed: String) -> String {
        glyphs[Int(stableHash(seed, 3) % UInt32(glyphs.count))]
    }
}

/// Recipe artwork: real photo when available, otherwise a deterministic
/// gradient + food glyph so image-less recipes still look intentional.
private struct RecipeArtwork: View {
    let recipe: SavedRecipe
    var glyphSize: CGFloat = 40

    var body: some View {
        ZStack {
            RecipeDS.gradient(for: recipe.title)

            Image(systemName: RecipeDS.glyph(for: recipe.title))
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

            if let raw = recipe.heroImageUrl, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// Small icon + label chip used for recipe metadata.
private struct RecipeMetaChip: View {
    let icon: String
    let text: String
    var tinted: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tinted ? RecipesTokens.orange : RecipesTokens.muted)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            (tinted ? RecipesTokens.orangeSoft : RecipesTokens.pressSurface),
            in: Capsule()
        )
    }
}

private func recipeSourceLabel(_ recipe: SavedRecipe) -> String? {
    if let name = recipe.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
        return name
    }
    if let domain = recipe.sourceDomain?.trimmingCharacters(in: .whitespacesAndNewlines), !domain.isEmpty {
        return domain.replacingOccurrences(of: "www.", with: "")
    }
    if let host = URL(string: recipe.sourceUrl ?? "")?.host {
        return host.replacingOccurrences(of: "www.", with: "")
    }
    return nil
}

// MARK: Library (list) screen

struct RecipeLibraryView: View {
    let recipes: [SavedRecipe]
    var onOpen: (SavedRecipe) -> Void = { _ in }
    var onImport: () -> Void = {}

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                importBar

                if let featured = recipes.first {
                    RecipeFeaturedCard(recipe: featured)
                        .onTapGesture { onOpen(featured) }
                }

                if recipes.count > 1 {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Your library")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(RecipesTokens.ink)
                        Spacer()
                        Text("\(recipes.count)")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(RecipesTokens.orange)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(RecipesTokens.orangeSoft, in: Capsule())
                    }

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(recipes.dropFirst())) { recipe in
                            RecipeLibraryCard(recipe: recipe)
                                .onTapGesture { onOpen(recipe) }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(RecipesTokens.screenBackground.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR KITCHEN")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(RecipesTokens.orange)
                Text("Recipes")
                    .font(OnboardingTypography.instrumentSerif(style: .regular, size: 46))
                    .foregroundStyle(RecipesTokens.ink)
            }
            Spacer()
            Button(action: onImport) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(RecipesTokens.orange, in: Circle())
                    .shadow(color: RecipesTokens.orange.opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a recipe")
            .padding(.top, 18)
        }
    }

    private var importBar: some View {
        Button(action: onImport) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(RecipesTokens.orange)
                Text("Paste a recipe link to import")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RecipesTokens.muted)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(RecipesTokens.muted.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RecipesTokens.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(RecipesTokens.fieldBorder, style: StrokeStyle(lineWidth: 1.4, dash: [6, 5]))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct RecipeFeaturedCard: View {
    let recipe: SavedRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                RecipeArtwork(recipe: recipe, glyphSize: 54)
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.08), .black.opacity(0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("LATEST")
                        .font(.system(size: 10.5, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.22), in: Capsule())
                        .background(.ultraThinMaterial, in: Capsule())

                    Text(recipe.title)
                        .font(OnboardingTypography.instrumentSerif(style: .regular, size: 28))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                }
                .padding(16)
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

            HStack(spacing: 8) {
                if let source = recipeSourceLabel(recipe) {
                    RecipeMetaChip(icon: "link", text: source, tinted: true)
                }
                if let servings = recipe.servings, !servings.isEmpty {
                    RecipeMetaChip(icon: "person.2.fill", text: servings)
                }
                RecipeMetaChip(icon: "carrot.fill", text: "\(recipe.ingredients.count)")
                RecipeMetaChip(icon: "list.number", text: "\(recipe.steps.count) steps")
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .padding(.horizontal, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latest recipe: \(recipe.title)")
    }
}

private struct RecipeLibraryCard: View {
    let recipe: SavedRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeArtwork(recipe: recipe, glyphSize: 34)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(recipe.title)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(RecipesTokens.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Image(systemName: "carrot.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(recipe.ingredients.count) ingr")
                    Text("•")
                    Text("\(recipe.steps.count) steps")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RecipesTokens.muted)
                .lineLimit(1)

                if let source = recipeSourceLabel(recipe) {
                    Text(source)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(RecipesTokens.orange)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)
            .padding(.bottom, 13)
        }
        .background(RecipesTokens.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(RecipesTokens.border, lineWidth: 1)
        }
        .shadow(color: RecipesTokens.shadow, radius: 12, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recipe.title)
    }
}

// MARK: Detail screen

struct RecipeDetailView: View {
    let recipe: SavedRecipe
    var onClose: () -> Void = {}

    @State private var checkedIngredients: Set<Int> = []
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack(alignment: .top) {
            RecipesTokens.screenBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 22) {
                        titleBlock
                        metaRow
                        ingredientsSection
                        stepsSection
                        sourceFooter
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                    .background(
                        RecipesTokens.screenBackground
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    )
                    .offset(y: -26)
                }
            }
            .ignoresSafeArea(edges: .top)

            floatingBar
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RecipeArtwork(recipe: recipe, glyphSize: 64)
                .frame(height: 280)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.10), .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let source = recipeSourceLabel(recipe) {
                    RecipeMetaChip(icon: "link", text: source, tinted: true)
                }
                if let time = RecipeDuration.humanLabel(from: recipe.totalTime ?? recipe.cookTime) {
                    RecipeMetaChip(icon: "clock", text: time)
                }
            }
            Text(recipe.title)
                .font(OnboardingTypography.instrumentSerif(style: .regular, size: 34))
                .foregroundStyle(RecipesTokens.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let description = recipe.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                Text(description)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(RecipesTokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            RecipeStatTile(value: "\(recipe.ingredients.count)", label: "Ingredients", icon: "carrot.fill")
            RecipeStatTile(value: "\(recipe.steps.count)", label: "Steps", icon: "list.number")
            RecipeStatTile(
                value: recipe.servings.flatMap { $0.isEmpty ? nil : $0 } ?? "—",
                label: "Servings",
                icon: "person.2.fill"
            )
        }
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Ingredients",
                icon: "carrot.fill",
                trailing: "\(checkedIngredients.count)/\(recipe.ingredients.count)"
            )

            VStack(spacing: 0) {
                ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, line in
                    if index > 0 {
                        Divider().overlay(RecipesTokens.fieldBorder).padding(.leading, 42)
                    }
                    RecipeIngredientCheckRow(
                        text: line.text,
                        isChecked: checkedIngredients.contains(index)
                    ) {
                        AppHaptics.lightImpact()
                        if checkedIngredients.contains(index) {
                            checkedIngredients.remove(index)
                        } else {
                            checkedIngredients.insert(index)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .background(RecipesTokens.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(RecipesTokens.border, lineWidth: 1)
            }
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Method", icon: "list.number", trailing: "\(recipe.steps.count)")

            VStack(spacing: 10) {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, line in
                    RecipeStepRow(number: index + 1, text: line.text)
                }
            }
        }
    }

    private var sourceFooter: some View {
        Group {
            if let raw = recipe.sourceUrl, let url = URL(string: raw) {
                Button {
                    AppHaptics.lightImpact()
                    openURL(url)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("View original recipe")
                            .font(.system(size: 15, weight: .bold))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundStyle(RecipesTokens.orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .background(RecipesTokens.orangeSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHeader(title: String, icon: String, trailing: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(RecipesTokens.orange)
            Text(title)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(RecipesTokens.ink)
            Spacer()
            Text(trailing)
                .font(.system(size: 12.5, weight: .heavy))
                .foregroundStyle(RecipesTokens.orange)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(RecipesTokens.orangeSoft, in: Capsule())
        }
    }

    private var floatingBar: some View {
        HStack {
            circleButton(icon: "chevron.left", action: onClose)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func circleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.lightImpact()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(RecipesTokens.ink)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

private struct RecipeStatTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(RecipesTokens.orange)
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(RecipesTokens.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(RecipesTokens.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RecipesTokens.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(RecipesTokens.border, lineWidth: 1)
        }
    }
}

private struct RecipeIngredientCheckRow: View {
    let text: String
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isChecked ? RecipesTokens.orange : RecipesTokens.muted.opacity(0.5))

                Text(text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isChecked ? RecipesTokens.muted : RecipesTokens.ink)
                    .strikethrough(isChecked, color: RecipesTokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityValue(isChecked ? "Checked" : "Not checked")
    }
}

private struct RecipeStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(OnboardingTypography.instrumentSerif(style: .regular, size: 22))
                .foregroundStyle(RecipesTokens.orange)
                .frame(width: 38, height: 38)
                .background(RecipesTokens.orangeSoft, in: Circle())

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(RecipesTokens.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RecipesTokens.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(RecipesTokens.border, lineWidth: 1)
        }
    }
}

#if DEBUG
extension SavedRecipe {
    /// Sample-data initializer (DEBUG only) for previews / VisualQA. The
    /// production model is decoder-only.
    init(
        id: String,
        title: String,
        sourceUrl: String?,
        sourceDomain: String?,
        sourceName: String?,
        heroImageUrl: String?,
        description: String? = nil,
        servings: String?,
        prepTime: String? = nil,
        cookTime: String? = nil,
        totalTime: String? = nil,
        categories: [String] = [],
        cuisines: [String] = [],
        keywords: [String] = [],
        ingredients: [String],
        steps: [String],
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceUrl = sourceUrl
        self.sourceDomain = sourceDomain
        self.sourceName = sourceName
        self.heroImageUrl = heroImageUrl
        self.description = description
        self.servings = servings
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.totalTime = totalTime
        self.categories = categories
        self.cuisines = cuisines
        self.keywords = keywords
        self.ingredients = ingredients.map { RecipeTextLine(text: $0) }
        self.steps = steps.map { RecipeTextLine(text: $0) }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum RecipeSampleData {
    static let library: [SavedRecipe] = [
        SavedRecipe(
            id: "1",
            title: "Charred Tomato & Burrata Toast",
            sourceUrl: "https://smittenkitchen.com/burrata-toast",
            sourceDomain: "smittenkitchen.com",
            sourceName: "Smitten Kitchen",
            heroImageUrl: nil,
            servings: "2",
            ingredients: [
                "4 thick slices sourdough",
                "2 cups cherry tomatoes, halved",
                "1 ball fresh burrata",
                "3 tbsp olive oil",
                "2 cloves garlic, smashed",
                "Flaky sea salt & black pepper",
                "Fresh basil leaves"
            ],
            steps: [
                "Heat the olive oil in a skillet over medium-high until shimmering.",
                "Add the cherry tomatoes and a pinch of salt; let them blister undisturbed for 3 minutes, then toss.",
                "Rub the toasted sourdough with the smashed garlic while still warm.",
                "Tear the burrata over the toast, spoon the charred tomatoes on top, and finish with basil, flaky salt, and a drizzle of oil."
            ]
        ),
        SavedRecipe(
            id: "2",
            title: "Weeknight Miso Salmon Bowls",
            sourceUrl: "https://www.bonappetit.com/miso-salmon",
            sourceDomain: "bonappetit.com",
            sourceName: "Bon Appétit",
            heroImageUrl: nil,
            servings: "4",
            ingredients: ["4 salmon fillets", "3 tbsp white miso", "2 cups jasmine rice", "1 cucumber, ribboned", "Sesame seeds"],
            steps: ["Whisk miso glaze.", "Broil the salmon 8 minutes.", "Serve over rice with cucumber."]
        ),
        SavedRecipe(
            id: "3",
            title: "Brown Butter Banana Bread",
            sourceUrl: "https://cooking.nytimes.com/banana-bread",
            sourceDomain: "cooking.nytimes.com",
            sourceName: "NYT Cooking",
            heroImageUrl: nil,
            servings: "1 loaf",
            ingredients: ["3 ripe bananas", "1/2 cup brown butter", "2 eggs", "1 1/2 cups flour"],
            steps: ["Brown the butter.", "Mix wet, then dry.", "Bake 55 minutes at 350°F."]
        ),
        SavedRecipe(
            id: "4",
            title: "Crispy Chili Garlic Noodles",
            sourceUrl: "https://thewoksoflife.com/chili-noodles",
            sourceDomain: "thewoksoflife.com",
            sourceName: "The Woks of Life",
            heroImageUrl: nil,
            servings: "2",
            ingredients: ["8 oz noodles", "3 tbsp chili crisp", "2 tbsp soy sauce", "Scallions"],
            steps: ["Boil noodles.", "Toss with sauce.", "Top with scallions."]
        ),
        SavedRecipe(
            id: "5",
            title: "Lemon Herb Roast Chicken",
            sourceUrl: "https://www.seriouseats.com/roast-chicken",
            sourceDomain: "seriouseats.com",
            sourceName: "Serious Eats",
            heroImageUrl: nil,
            servings: "4",
            ingredients: ["1 whole chicken", "2 lemons", "Fresh thyme", "Butter"],
            steps: ["Dry-brine overnight.", "Roast at 425°F for 50 min."]
        )
    ]

    static var featured: SavedRecipe { library[0] }
}

struct RecipesVisualQARoot: View {
    let stateID: String

    var body: some View {
        if stateID.contains("/detail") {
            RecipeDetailView(recipe: RecipeSampleData.featured)
        } else {
            RecipeLibraryView(recipes: RecipeSampleData.library)
        }
    }
}
#endif
