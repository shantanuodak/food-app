//
//  HomeRecipesDrawer.swift
//  Food App
//
//  Created 2026-05-23 (home-recipes-drawer branch).
//  Native-sheet rewrite 2026-05-24 — replaced the hand-rolled drag
//  drawer with `.presentationDetents([.height(60), .large])`. The host
//  (MainLoggingShellBody) presents this content view in a sheet that
//  is always on, so iOS handles the drag physics, dismiss-to-peek,
//  rubber-band, keyboard avoidance, and accessibility for free.
//
//  Layout:
//   • At .height(60), only the iOS drag indicator + the "Your recipes"
//     headline are visible. The home view behind stays interactive
//     (see `.presentationBackgroundInteraction(.enabled(upThrough:))`
//     on the call site).
//   • At .large, the headline sits at the top with the paste-recipe
//     input row, filter chips, and the recipe list filling the rest.
//
//  Data:
//   Loads `appStore.apiClient.getRecipes()` on first appear and again
//   after a successful paste-save. Filter chips operate client-side
//   over the loaded set (filter logic is a follow-up). Tap a recipe
//   to drill into `RecipeDetailView` as a stacked sheet.
//

import SwiftUI
import UIKit

// MARK: - Filter chips

// Data-backed filters — each one is computed from a field SavedRecipe actually
// carries (see `filteredRecipes`). The previous chips (For today / High-protein
// / Saved / Comfort) were decorative because the app has no nutrition or tag
// data to back them.
enum HomeRecipesDrawerFilter: String, CaseIterable, Identifiable {
    case all       = "All"
    case recent    = "Recent"
    case quick     = "Quick"
    case withPhoto = "With photo"

    var id: String { rawValue }
}

// MARK: - Drawer content

struct HomeRecipesDrawerContent: View {
    @EnvironmentObject private var appStore: AppStore

    /// Detent binding owned by the host so we can both react to user
    /// drags AND drive the sheet programmatically (tap heading to
    /// expand).
    @Binding var detent: PresentationDetent

    /// Drives the periodic shimmer sweep across the heading chip — a soft
    /// warm highlight that travels left → right every 30s while the
    /// drawer is collapsed. Acts as a "look at me" attention cue without
    /// the constant motion the previous sway animation had.
    @State private var shimmerProgress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let shimmerIntervalSeconds: UInt64 = 30
    private static let shimmerSweepSeconds: Double = 1.4

    // ── Data state
    @State private var recipes: [SavedRecipe] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var hasLoaded: Bool = false

    // ── Paste state
    @State private var pasteText: String = ""
    @State private var isPasting: Bool = false
    @State private var pasteError: String?
    @FocusState private var isPasteFocused: Bool

    /// True when iOS reports the clipboard contains a URL. Drives the
    /// "Link detected" pill state on the bottom paste bar. Uses
    /// `UIPasteboard.hasURLs` (silent, no privacy banner) — never reads
    /// the string itself until the user actually taps to paste.
    @State private var hasClipboardURL: Bool = false

    /// Rotates 0 → 360 continuously to drive the "moving light" effect
    /// around the Link-detected pill's perimeter.
    @State private var strokeRotation: Double = 0

    /// Sweeps 0 → 1 then resets, on a periodic loop, to shimmer the
    /// pill so it reads as actively inviting a tap.
    @State private var pillShimmerProgress: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase

    /// Surfaces import failures inline above the paste bar. Auto-clears
    /// after a few seconds so it doesn't linger.
    @State private var importErrorMessage: String?

    // ── Selection
    @State private var selectedFilter: HomeRecipesDrawerFilter = .all
    @State private var selectedRecipe: SavedRecipe?

    // ── Import-flow + delete state. The drawer now drives the SAME browser-
    // import and review sheets as RecipesScreen (see RecipeImportFlow.swift), so
    // social/blocked links no longer dead-end here.
    @State private var browserImportSession: RecipeBrowserImportSession?
    @State private var draftForReview: RecipeImportDraft?
    @State private var recipePendingDeletion: SavedRecipe?

    private var isExpanded: Bool { detent == .large }

    /// Client-side filtering over the loaded set, keyed by `selectedFilter`.
    /// Every case is backed by a real field so the chips actually do something.
    private var filteredRecipes: [SavedRecipe] {
        switch selectedFilter {
        case .all:
            return recipes
        case .recent:
            let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
            return recipes.filter { recipe in
                guard let created = RecipeDateParsing.date(from: recipe.createdAt) else { return false }
                return created >= cutoff
            }
        case .quick:
            return recipes.filter { recipe in
                guard let minutes = RecipeDuration.minutes(from: recipe.totalTime ?? recipe.cookTime) else {
                    return false
                }
                return minutes <= 30
            }
        case .withPhoto:
            return recipes.filter { ($0.heroImageUrl?.isEmpty == false) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            heading
            if isExpanded {
                filterStrip
                    .padding(.top, 10)
                recipeListBody
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 2026-05-24: gradient extended past the heading button (160pt
        // tall, fades to 0 opacity) so the warm orange chip blends
        // smoothly into the cream drawer surface instead of stopping at
        // a hard line. At peek, only the top ~88pt of the gradient is
        // visible and the chip stays uniformly warm. When expanded, the
        // gradient continues down past the heading into the filter
        // strip area before fully dissolving.
        .background(alignment: .top) {
            headingBackdrop
                .frame(height: 160)
        }
        // Paste-from-clipboard FAB docked at the bottom of the drawer.
        // Only visible when expanded — at peek the chip is too short to
        // accommodate a bottom action.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isExpanded {
                bottomPasteBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: isExpanded)
        .task {
            await loadRecipesIfNeeded()
        }
        // RecipeDetailView is presented the SAME bare way as on RecipesScreen —
        // it owns its own back control via `onClose`, so wrapping it in a
        // NavigationStack + Done toolbar here produced a dead floating back
        // button and a hero/nav-bar layout clash.
        .sheet(item: $selectedRecipe) { recipe in
            RecipeDetailView(recipe: recipe) {
                selectedRecipe = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
        // Social/blocked links route here — the same in-app browser importer
        // RecipesScreen uses, instead of the old dead-end error.
        .sheet(item: $browserImportSession) { session in
            RecipeBrowserImportSheet(
                url: session.url,
                sourceHint: session.sourceHint,
                sharedText: session.sharedText
            ) { draft in
                browserImportSession = nil
                // Let the browser sheet finish dismissing before the review
                // sheet presents (same hand-off RecipesScreen uses).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    draftForReview = draft
                }
            } onCancel: {
                browserImportSession = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
        .sheet(item: $draftForReview) { draft in
            RecipeReviewSheet(draft: draft) { saved in
                recipes.removeAll { $0.id == saved.id }
                recipes.insert(saved, at: 0)
                draftForReview = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    selectedRecipe = saved
                }
            } onCancel: {
                draftForReview = nil
            }
            .environmentObject(appStore)
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

    // MARK: - Heading
    //
    // Sized to fit cleanly inside the `.height(88)` peek detent. The full
    // row is tappable — taps animate the sheet between peek and large
    // with iOS's native presentation spring. No chevron — the iOS drag
    // indicator already telegraphs "this is draggable," and the
    // typographic treatment ("Your *recipes*") plus the warm gradient
    // background is the visual call-to-action.

    private var heading: some View {
        Button {
            AppHaptics.lightImpact()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                detent = isExpanded ? .height(88) : .large
            }
        } label: {
            (
                Text("Your ")
                    .font(.custom("InstrumentSerif-Regular", size: 30))
                + Text("recipes")
                    .font(.custom("InstrumentSerif-Italic", size: 30))
                    .foregroundStyle(AppColor.brandOrangeDeep)
            )
            .foregroundStyle(AppColor.textPrimary)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            // When collapsed, fill the available peek height so the
            // gradient backdrop (applied to the parent VStack) covers
            // the entire visible chip. When expanded, fall back to
            // intrinsic height so the heading is a compact branded
            // header strip at the top.
            .frame(maxHeight: isExpanded ? nil : .infinity, alignment: .top)
            // Periodic shimmer sweep — fires once every 30s while the
            // drawer is collapsed. Clipped to chip bounds so the sweep
            // doesn't leak onto the surface below.
            .overlay(shimmerOverlay)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(Text(isExpanded ? "Your recipes — tap to collapse" : "Your recipes — tap to expand"))
        .task(id: isExpanded) {
            await runShimmerLoop()
        }
    }

    /// A soft warm-white highlight band that sweeps left → right across
    /// the chip when shimmerProgress animates 0 → 1. Hidden the rest of
    /// the time. `.allowsHitTesting(false)` so taps still hit the
    /// heading button beneath.
    @ViewBuilder
    private var shimmerOverlay: some View {
        if !isExpanded {
            GeometryReader { proxy in
                let chipWidth = proxy.size.width
                let bandWidth: CGFloat = max(140, chipWidth * 0.32)
                let xPosition = -bandWidth + shimmerProgress * (chipWidth + bandWidth)

                LinearGradient(
                    colors: [
                        .white.opacity(0.0),
                        .white.opacity(0.32),
                        .white.opacity(0.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: bandWidth, height: proxy.size.height)
                .offset(x: xPosition)
                .blendMode(.plusLighter)
            }
            .allowsHitTesting(false)
        }
    }

    /// Runs as long as the heading view is on screen at the peek detent.
    /// Sleeps `shimmerIntervalSeconds`, sweeps the highlight across,
    /// resets without animation, and repeats. Cancellation comes from
    /// `.task(id: isExpanded)` — when the user expands the drawer, this
    /// task is cancelled and a new one starts with `isExpanded == true`
    /// (which is a no-op via the guard below).
    private func runShimmerLoop() async {
        guard !isExpanded && !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.shimmerIntervalSeconds * 1_000_000_000)
            guard !Task.isCancelled && !isExpanded else { return }
            withAnimation(.easeInOut(duration: Self.shimmerSweepSeconds)) {
                shimmerProgress = 1.0
            }
            try? await Task.sleep(nanoseconds: UInt64((Self.shimmerSweepSeconds + 0.1) * 1_000_000_000))
            // Reset without animation so the band doesn't visibly track
            // back to the left side.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                shimmerProgress = 0
            }
        }
    }

    /// 2026-05-24 (smooth-transition revision): applied to the parent
    /// VStack with an explicit 160pt height so the warm orange tint
    /// fades smoothly past the heading row into the drawer body —
    /// instead of stopping at a hard line at the heading's bottom edge.
    /// Four stops ramp from 0.26 (top of chip) → 0.0 (bottom of the
    /// 160pt band), so by the time the gradient ends, it's
    /// indistinguishable from the cream drawer surface.
    ///
    /// At peek, only the top ~88pt of this gradient is visible — the
    /// chip stays strongly tinted. When expanded, the lower 70pt of
    /// the gradient tapers into the filter strip area, masking the
    /// transition.
    private var headingBackdrop: some View {
        LinearGradient(
            colors: [
                AppColor.brandOrange.opacity(0.26),
                AppColor.brandOrange.opacity(0.20),
                AppColor.brandOrange.opacity(0.08),
                AppColor.brandOrange.opacity(0.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Bottom paste bar
    //
    // 2026-05-24: replaced the top-mounted paste TextField + Save text
    // button with a single FAB-style icon docked at the bottom of the
    // drawer. The user copies a recipe URL elsewhere, taps the paste
    // glyph, and the app reads the clipboard + submits in one step —
    // no manual typing, no scrolling to the top of the drawer to reach
    // the input. More thumb-accessible.

    private var bottomPasteBar: some View {
        VStack(spacing: 8) {
            // Inline error toast — shown when an import fails. Sits
            // directly above the paste button so the error is tied to
            // the action that produced it. Auto-dismisses after 4s.
            if let importErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(importErrorMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.orange.opacity(0.28), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack {
                Spacer()
                Button {
                    Task { await pasteFromClipboard() }
                } label: {
                    Group {
                        if hasClipboardURL {
                            linkDetectedPillLabel
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            plainPasteFABLabel
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .buttonStyle(.plain)
                // NOTE: not `.disabled(isPasting)` — that dims the pill to
                // ~30% opacity, which read as "the button went transparent
                // while importing." Instead we keep it at full vibrancy and
                // just block re-taps via hit-testing while a paste is in
                // flight.
                .allowsHitTesting(!isPasting)
                .accessibilityLabel(Text(hasClipboardURL
                    ? "Link detected — paste recipe"
                    : "Paste recipe from clipboard"))
                .accessibilityHint(Text("Reads the link or recipe text from your clipboard and saves it."))
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: hasClipboardURL)
                Spacer()
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: importErrorMessage)
        .padding(.bottom, 18)
        .onAppear {
            checkClipboardForURL()
            startStrokeRotationLoop()
        }
        .onChange(of: isExpanded) { _, expanded in
            // Re-check the clipboard each time the drawer opens — users
            // commonly copy a URL elsewhere, then come back to the app.
            if expanded { checkClipboardForURL() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { checkClipboardForURL() }
        }
        .task(id: hasClipboardURL) {
            // Periodic shimmer sweep — only when the link-detected pill
            // is showing. Cancelled when hasClipboardURL flips false.
            guard hasClipboardURL else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled && hasClipboardURL else { return }
                withAnimation(.easeInOut(duration: 1.3)) {
                    pillShimmerProgress = 1
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    pillShimmerProgress = 0
                }
            }
        }
    }

    /// The plain circular FAB — no clipboard URL detected, just an
    /// affordance to paste whatever's on the clipboard (text, link,
    /// etc.).
    private var plainPasteFABLabel: some View {
        ZStack {
            Circle()
                .fill(pasteBrandGradient)

            if isPasting {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 60, height: 60)
        .shadow(color: AppColor.brandOrangeDeep.opacity(0.42), radius: 12, y: 6)
        .overlay {
            Circle()
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
    }

    /// Animated "Link detected" pill — shown when iOS reports the
    /// clipboard contains a URL. Three motion layers:
    ///   1. Continuous angular "comet" stroke that rotates around the
    ///      pill perimeter.
    ///   2. Periodic horizontal shimmer sweep across the pill body.
    ///   3. Subtle spring entrance when the state flips from FAB to pill.
    private var linkDetectedPillLabel: some View {
        HStack(spacing: 10) {
            if isPasting {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
                Text("Importing recipe")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            } else {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text("Link detected")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(Capsule().fill(pasteBrandGradient))
        .overlay {
            // Moving-light stroke — angular gradient with a single
            // bright stop that rotates around the pill perimeter.
            Capsule()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .clear, location: 0.35),
                            .init(color: .white.opacity(0.95), location: 0.50),
                            .init(color: .clear, location: 0.65),
                            .init(color: .clear, location: 1.00)
                        ]),
                        center: .center,
                        startAngle: .degrees(strokeRotation),
                        endAngle: .degrees(strokeRotation + 360)
                    ),
                    lineWidth: 2.5
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .overlay {
            // Horizontal shimmer sweep — periodic light band moving
            // left-to-right across the pill body, masked to the capsule
            // so it never leaks past the rounded edges.
            GeometryReader { proxy in
                let bandWidth: CGFloat = max(80, proxy.size.width * 0.4)
                let xPosition = -bandWidth + pillShimmerProgress * (proxy.size.width + bandWidth)

                LinearGradient(
                    colors: [
                        .white.opacity(0.0),
                        .white.opacity(0.45),
                        .white.opacity(0.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: bandWidth, height: proxy.size.height)
                .offset(x: xPosition)
                .blendMode(.plusLighter)
            }
            .mask(Capsule())
            .allowsHitTesting(false)
        }
        .shadow(color: AppColor.brandOrangeDeep.opacity(0.45), radius: 14, y: 6)
    }

    private var pasteBrandGradient: LinearGradient {
        LinearGradient(
            colors: [AppColor.brandOrange, AppColor.brandOrangeDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Silent clipboard probe — uses `hasURLs` which iOS does NOT count
    /// as a paste access, so no "Pasted from X" privacy banner fires.
    /// We only read the actual string in `pasteFromClipboard()` when
    /// the user explicitly taps the button.
    private func checkClipboardForURL() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            hasClipboardURL = UIPasteboard.general.hasURLs
        }
    }

    /// Kick off the continuous 360° rotation that drives the comet
    /// stroke. Linear, 2.5s per revolution, repeats forever. Safe to
    /// call repeatedly — `withAnimation` simply replaces the prior
    /// animation if one is in flight.
    private func startStrokeRotationLoop() {
        strokeRotation = 0
        withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
            strokeRotation = 360
        }
    }

    /// Read the clipboard and submit it as a recipe import. Trims
    /// whitespace, no-ops if the clipboard is empty. Uses the existing
    /// `submitPaste()` pipeline so the loading state, error handling,
    /// and list refresh stay consistent with the old TextField flow.
    private func pasteFromClipboard() async {
        let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return }
        pasteText = raw
        await submitPaste()
    }

    // MARK: - Filter chips

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HomeRecipesDrawerFilter.allCases) { filter in
                    Button {
                        AppHaptics.lightImpact()
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(filter == selectedFilter ? AppColor.textInverse : AppColor.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(filter == selectedFilter ? AppColor.textPrimary : AppColor.surface)
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(filter == selectedFilter ? Color.clear : AppColor.borderSubtle, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    // MARK: - Recipe list

    @ViewBuilder
    private var recipeListBody: some View {
        if isLoading && recipes.isEmpty {
            loadingState
        } else if let loadError, recipes.isEmpty {
            errorState(loadError)
        } else if recipes.isEmpty {
            emptyState
        } else if filteredRecipes.isEmpty {
            noMatchesState
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filteredRecipes) { recipe in
                        Button {
                            AppHaptics.lightImpact()
                            selectedRecipe = recipe
                        } label: {
                            HomeRecipesDrawerCard(recipe: recipe)
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
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 36)
            }
        }
    }

    private var noMatchesState: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppColor.brandOrange.opacity(0.65))
            Text("No recipes match this filter")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
            Text("Tap “All” to see everything.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading your recipes…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load recipes")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button("Try again") {
                Task { await loadRecipes(force: true) }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColor.brandOrangeDeep)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(AppColor.brandOrange.opacity(0.65))
            Text("Nothing saved yet")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
            Text("Copy a recipe link, then tap the paste button below to save it here.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
    }

    // MARK: - Networking

    private func loadRecipesIfNeeded() async {
        guard !hasLoaded else { return }
        await loadRecipes(force: false)
    }

    private func loadRecipes(force: Bool) async {
        if isLoading && !force { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let response = try await appStore.apiClient.getRecipes()
            recipes = response.recipes
            hasLoaded = true
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? "Network error"
        }
    }

    /// Two-step pipeline:
    ///   1. `importRecipeFromURL` — backend scrapes the URL and returns
    ///      a draft of the recipe (title, ingredients, steps, source).
    ///   2. `createRecipe(CreateRecipeRequest(draft:))` — persists the
    ///      draft as a real recipe and returns the saved record.
    /// The previous version called step 1 only and threw away the draft,
    /// which is why nothing showed up in the user's library.
    /// Unified entry point (shared with RecipesScreen via RecipeImportFlow).
    /// Normalizes the pasted text, routes social/blocked links to the in-app
    /// browser importer, imports clean URLs directly, and — for high-confidence
    /// direct scrapes — saves + opens immediately (the fast path the user
    /// likes). Lower-confidence or fallback drafts go through the shared review
    /// sheet so noisy scrapes can be fixed before saving.
    @MainActor
    private func submitPaste() async {
        let normalized = RecipeImportURL.normalized(pasteText)
        guard !normalized.isEmpty else { return }
        guard RecipeImportURL.isSupported(normalized), let url = URL(string: normalized) else {
            importErrorMessage = "That doesn’t look like a recipe link — copy the full web address first."
            scheduleErrorAutoDismiss()
            return
        }

        // Social/video links don't expose recipe schema to a server scrape —
        // send them straight to the browser importer.
        let sourceHint = RecipeImportSourceHint.infer(url: url)
        if sourceHint.prefersBrowserImport {
            pasteText = ""
            isPasteFocused = false
            browserImportSession = RecipeBrowserImportSession(url: url, sourceHint: sourceHint)
            return
        }

        isPasting = true
        importErrorMessage = nil
        defer { isPasting = false }

        do {
            let importResponse = try await appStore.apiClient.importRecipeFromURL(
                RecipeImportRequest(url: normalized)
            )
            let draft = importResponse.draft
            if (draft.confidence ?? 0) >= 0.9 {
                await saveAndOpen(draft)
            } else {
                pasteText = ""
                isPasteFocused = false
                draftForReview = draft
            }
        } catch {
            if RecipeImportFailure.shouldFallBackToBrowser(error) {
                pasteText = ""
                isPasteFocused = false
                importErrorMessage = "That site blocked direct import — opening it so you can grab the recipe."
                scheduleErrorAutoDismiss()
                browserImportSession = RecipeBrowserImportSession(url: url, sourceHint: sourceHint)
            } else {
                importErrorMessage = RecipeImportFailure.friendlyMessage(error)
                scheduleErrorAutoDismiss()
            }
        }
    }

    /// Persist a draft and open it — the drawer's "imported recipe opens
    /// immediately" behavior, reused by the fast path and the review sheet.
    @MainActor
    private func saveAndOpen(_ draft: RecipeImportDraft) async {
        do {
            let createResponse = try await appStore.apiClient.createRecipe(
                CreateRecipeRequest(draft: draft)
            )
            recipes.removeAll { $0.id == createResponse.recipe.id }
            recipes.insert(createResponse.recipe, at: 0)
            pasteText = ""
            isPasteFocused = false
            selectedRecipe = createResponse.recipe
        } catch {
            importErrorMessage = RecipeImportFailure.friendlyMessage(error)
            scheduleErrorAutoDismiss()
        }
    }

    /// Hard-delete via the backend, then drop it from the local list.
    @MainActor
    private func deleteRecipe(_ recipe: SavedRecipe) async {
        do {
            try await appStore.apiClient.deleteRecipe(id: recipe.id)
            withAnimation(.easeOut(duration: 0.2)) {
                recipes.removeAll { $0.id == recipe.id }
            }
            if selectedRecipe?.id == recipe.id { selectedRecipe = nil }
        } catch {
            importErrorMessage = RecipeImportFailure.friendlyMessage(error)
            scheduleErrorAutoDismiss()
        }
        recipePendingDeletion = nil
    }

    /// Auto-clear the inline error after 4 seconds so it doesn't linger.
    private func scheduleErrorAutoDismiss() {
        let pinned = importErrorMessage
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                if importErrorMessage == pinned {
                    withAnimation { importErrorMessage = nil }
                }
            }
        }
    }
}

// MARK: - Sheet modifier
//
// Wraps the `.sheet(isPresented:)` boilerplate so MainLoggingShellBody's
// view body stays under the SwiftUI type-checker threshold (the modifier
// chain there is already long enough that adding the sheet inline tips
// it over).

struct HomeRecipesDrawerSheetModifier: ViewModifier {
    let isKeyboardVisible: Bool
    let isVoiceOverlayPresented: Bool
    /// True when any OTHER home modal (Saved Meals, Profile, Progress,
    /// Calendar, Streak, Badges, camera, etc.) is presented. The recipes
    /// drawer is an always-on sheet that occupies the home view's single
    /// modal-presentation slot — so it MUST yield that slot whenever
    /// another sheet needs it, otherwise the other sheet can't present
    /// fully (this was the "Saved Meals not opening fully" bug). When the
    /// other modal dismisses, this flips false and the recipes peek
    /// re-presents automatically.
    let isOtherModalPresented: Bool
    let appStore: AppStore

    /// Owned here so the heading tap can drive the sheet. 88pt peek —
    /// the size the user liked (per 2026-05-24 walkthrough).
    @State private var detent: PresentationDetent = .height(88)

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(
                get: { !isKeyboardVisible && !isVoiceOverlayPresented && !isOtherModalPresented },
                set: { _ in }
            )
        ) {
            HomeRecipesDrawerContent(detent: $detent)
                .environmentObject(appStore)
                .presentationDetents([.height(88), .large], selection: $detent)
                .presentationDragIndicator(.visible)
                .presentationBackground(AppDrawerSurface.gradient)
                .presentationBackgroundInteraction(.enabled(upThrough: .height(88)))
                // 2026-05-24: explicit 28pt only affects the top corners
                // — overrides iOS 26's default "Liquid Glass" floating
                // treatment for small detents and forces a traditional
                // edge-to-edge sheet (rounded top, flush bottom against
                // the home indicator).
                .presentationCornerRadius(28)
                .interactiveDismissDisabled(true)
        }
    }
}

// MARK: - Recipe card

private struct HomeRecipesDrawerCard: View {
    let recipe: SavedRecipe

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                if let domain = recipe.sourceDomain ?? recipe.sourceName, !domain.isEmpty {
                    Text(domain.uppercased())
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(AppColor.brandOrangeDeep)
                        .lineLimit(1)
                }
                Text(recipe.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    if let servings = recipe.servings, !servings.isEmpty {
                        Text(servings)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    if !recipe.ingredients.isEmpty {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(AppColor.textSecondary)
                        Text("\(recipe.ingredients.count) ingredients")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColor.textSecondary.opacity(0.60))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppColor.borderSubtle, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let urlString = recipe.heroImageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.90, blue: 0.72),
                    Color(red: 1.00, green: 0.78, blue: 0.52)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "fork.knife")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
        }
    }
}
