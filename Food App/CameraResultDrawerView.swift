import SwiftUI

// MARK: - Drawer State

/// V3.1 Phase 4: which parse lane the iOS Vision pipeline picked for this
/// capture. Used to drive lane-specific status text in the analyzing
/// drawer ("Scanning barcode…" vs "Reading nutrition label…" vs
/// "Analyzing your meal…"). nil means lane hasn't been decided yet —
/// renders the generic "Analyzing your meal" copy.
enum AnalysisLaneHint: Equatable {
    case barcode
    case label
    case vision

    /// Top-line header shown in the analyzing card.
    var headerText: String {
        switch self {
        case .barcode: return "Scanning barcode"
        case .label:   return "Reading nutrition label"
        case .vision:  return "Analyzing your meal"
        }
    }

    /// Whether to show the multi-phase progress phrases. Barcode + label
    /// finish in ~1-3s — too fast to be worth churning through "Reading
    /// the photo…" / "Finding every visible food item…" copy. Vision-lane
    /// is slower (5-8s) so the progression helps the user feel progress.
    var showsMultiPhaseProgression: Bool {
        self == .vision
    }
}

enum CameraDrawerState {
    case idle
    /// V3.1 hotfix v4 (2026-05-20): image is now optional. The host (camera
    /// capture path) hands `nil` initially so the drawer can pop up the
    /// instant the user taps "Use Photo" — no waiting for SwiftUI to
    /// decode + downsample a 12-48MP HEIC on the main thread, which is
    /// what was making the drawer appear "a couple of seconds" late on
    /// real iPhones. The host then asynchronously prepares a small
    /// display-sized thumbnail and re-sets the state with the populated
    /// image. The photo-library + parsed/error paths still pass a real
    /// UIImage because those images are already small or already decoded.
    case analyzing(UIImage?, AnalysisLaneHint?)
    case parsed(UIImage, [ParsedFoodItem], NutritionTotals)
    case error(String, UIImage?)

    var isVisible: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }
}

// MARK: - Camera Result Drawer

struct CameraResultDrawerView: View {
    let state: CameraDrawerState
    let parseResult: ParseLogResponse?
    @Binding var contextNote: String
    let onLogIt: ([ParsedFoodItem], NutritionTotals) -> Void
    let onDiscard: () -> Void
    let onRetry: () -> Void

    @State private var shimmerPhase: CGFloat = -1
    @State private var analyzePhaseIndex: Int = 0
    @State private var analyzeTickCount: Int = 0
    @State private var phaseTimer: Timer?
    @State private var editablePhotoItems: [EditableParsedItem] = []
    @State private var editablePhotoSeedSignature = ""
    /// Drives focus-on-tap behavior for the context note text field — lets
    /// the user tap anywhere on the "Add a note to refine" card to start
    /// typing, instead of having to hit the tiny text field area.
    @FocusState private var isContextNoteFocused: Bool

    private let analyzingPhrases = [
        "Reading the photo...",
        "Finding every visible food item...",
        "Estimating portions...",
        "Adding up calories...",
        "Taking one more careful look..."
    ]

    init(
        state: CameraDrawerState,
        parseResult: ParseLogResponse? = nil,
        contextNote: Binding<String>,
        onLogIt: @escaping ([ParsedFoodItem], NutritionTotals) -> Void,
        onDiscard: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.state = state
        self.parseResult = parseResult
        self._contextNote = contextNote
        self.onLogIt = onLogIt
        self.onDiscard = onDiscard
        self.onRetry = onRetry
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch state {
                case .idle:
                    EmptyView()
                case .analyzing(let image, let laneHint):
                    analyzingContent(image: image, laneHint: laneHint)
                case .parsed(let image, let items, let totals):
                    parsedContent(image: image, items: items, totals: totals)
                        .onAppear {
                            // Always reseed after a fresh analyze -> parsed transition.
                            // Otherwise a retry that returns the same detected item
                            // signature can keep stale local edits from the prior pass.
                            seedEditablePhotoItemsIfNeeded(items, force: true)
                        }
                        .onChange(of: itemSignature(items)) { _, _ in
                            seedEditablePhotoItemsIfNeeded(items, force: true)
                        }
                case .error(let message, let image):
                    errorContent(message: message, image: image)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AppDrawerSurface.gradient)
        .presentationBackground(AppDrawerSurface.gradient)
        .onDisappear {
            phaseTimer?.invalidate()
            phaseTimer = nil
        }
    }

    // MARK: - Analyzing State

    private func analyzingContent(image: UIImage?, laneHint: AnalysisLaneHint?) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            // Full-width image (or placeholder) with shimmer sweep.
            // V3.1 hotfix v4 (2026-05-20): when image is nil, we render a
            // neutral gray placeholder of the same dimensions so the drawer
            // layout doesn't jump when the host hands us the decoded
            // thumbnail a moment later. This is the codepath used by the
            // camera-capture path on first appear — `Image(uiImage:)` with
            // a 12-48MP HEIC blocks the main thread for hundreds of ms
            // while SwiftUI decodes and downsamples it, which is why the
            // drawer was appearing seconds late on real iPhones.
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color(white: 0.18))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    shimmerOverlay()
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                )

                AppCloseButton(action: onDiscard, variant: .onImage, visualSize: 30, hitSize: 44)
                .padding(14)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .onAppear {
                analyzePhaseIndex = 0
                analyzeTickCount = 0
                shimmerPhase = -1
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1
                }
                phaseTimer?.invalidate()
                phaseTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { _ in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        analyzeTickCount += 1
                        analyzePhaseIndex = min(analyzePhaseIndex + 1, analyzingPhrases.count - 1)
                    }
                }
            }

            analyzingStatusCard(laneHint: laneHint)
                .padding(.horizontal, 20)
            .padding(.top, 18)

            // Skeleton nutrition cards
            skeletonNutritionCards()
                .padding(.top, 20)

            // Skeleton food item rows
            VStack(spacing: 0) {
                Divider()
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Detected items")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 12)

                    ForEach(0..<3, id: \.self) { i in
                        HStack {
                            SkeletonBar(width: CGFloat([130, 100, 115][i]), height: 13, cornerRadius: 6)
                            Spacer()
                            SkeletonBar(width: 44, height: 13, cornerRadius: 6)
                        }
                        .padding(.bottom, i < 2 ? 14 : 0)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            Spacer().frame(height: 40)
        }
    }

    /// V3.1 Phase 4: lane-specific copy. Vision lane keeps the existing
    /// multi-phase progression (5-8s parse — user benefits from progress
    /// feedback). Barcode + label finish in 1-3s — suppress the churn so
    /// the copy doesn't change underneath the user.
    private struct AnalyzingCopy {
        let header: String
        let primaryLine: String
        let secondaryLine: String
        let showsProgression: Bool
    }

    private func analyzingCopy(for hint: AnalysisLaneHint?) -> AnalyzingCopy {
        let header = hint?.headerText ?? "Analyzing your meal"
        let showsProgression = hint?.showsMultiPhaseProgression ?? true
        switch hint {
        case .barcode:
            return AnalyzingCopy(
                header: header,
                primaryLine: "Looking up product",
                secondaryLine: "Fast packaged-item lookup.",
                showsProgression: showsProgression
            )
        case .label:
            return AnalyzingCopy(
                header: header,
                primaryLine: "Reading the label",
                secondaryLine: "Pulling calories and macros straight off the panel.",
                showsProgression: showsProgression
            )
        case .vision, .none:
            return AnalyzingCopy(
                header: header,
                primaryLine: analyzingPhrases[analyzePhaseIndex],
                secondaryLine: analyzeTickCount >= 7
                    ? "Still working - this photo has a few details to check."
                    : "Checking visible foods, portions, and calories.",
                showsProgression: showsProgression
            )
        }
    }

    @ViewBuilder
    private func analyzingStatusCard(laneHint: AnalysisLaneHint?) -> some View {
        let copy = analyzingCopy(for: laneHint)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.82)
                    .tint(Color(red: 0.380, green: 0.333, blue: 0.961))

                VStack(alignment: .leading, spacing: 3) {
                    Text(copy.header)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(copy.primaryLine)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: analyzePhaseIndex)
                }

                Spacer()
            }

            if copy.showsProgression {
                HStack(spacing: 7) {
                    ForEach(analyzingPhrases.indices, id: \.self) { index in
                        Capsule()
                            .fill(index <= analyzePhaseIndex ? Color(red: 0.380, green: 0.333, blue: 0.961) : Color(.systemGray4))
                            .frame(width: index == analyzePhaseIndex ? 24 : 7, height: 7)
                            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: analyzePhaseIndex)
                    }
                }
            }

            Text(copy.secondaryLine)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .animation(.easeInOut(duration: 0.25), value: analyzeTickCount >= 7)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.380, green: 0.333, blue: 0.961).opacity(0.12),
                            Color(.systemBackground).opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(.separator).opacity(0.35), lineWidth: 0.8)
                )
        )
    }

    @ViewBuilder
    private func shimmerOverlay() -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let sweepWidth = w * 0.75
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.28), location: 0.4),
                    .init(color: .white.opacity(0.42), location: 0.5),
                    .init(color: .white.opacity(0.28), location: 0.6),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: sweepWidth)
            .offset(x: shimmerPhase * (w + sweepWidth) - sweepWidth)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func skeletonNutritionCards() -> some View {
        HStack(spacing: 12) {
            ForEach(
                [("flame.fill", "Calories", Color.orange),
                 ("bolt.fill", "Protein", Color(red: 0.380, green: 0.333, blue: 0.961)),
                 ("leaf.fill", "Carbs", Color.green),
                 ("drop.fill", "Fat", Color.blue)],
                id: \.1
            ) { icon, label, color in
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color.opacity(0.7))

                    SkeletonBar(width: 38, height: 18, cornerRadius: 6)

                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.systemGray6))
                )
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Parsed State

    private func parsedContent(image: UIImage, items: [ParsedFoodItem], totals: NutritionTotals) -> some View {
        let displayItems = displayedPhotoItems(fallback: items)
        let displayTotals = editablePhotoItems.isEmpty ? totals : totalsForItems(displayItems)
        let needsReview = reviewRecommended(items: displayItems, parseResult: parseResult)

        return VStack(alignment: .leading, spacing: 0) {
            // Hero image with re-parse + close icons
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 232)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack {
                    Spacer()
                    HStack {
                        Label(needsReview ? "Review recommended" : "Detected from photo", systemImage: needsReview ? "exclamationmark.triangle.fill" : "camera.viewfinder")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.46), in: Capsule())
                        Spacer()
                    }
                    .padding(12)
                }

                HStack(spacing: 8) {
                    Button { onRetry() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.42), in: Circle())
                    }
                    AppCloseButton(action: onDiscard, variant: .onImage, visualSize: 30, hitSize: 44)
                }
                .padding(13)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)

            if needsReview {
                reviewRecommendedCard(items: displayItems, parseResult: parseResult)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            LoggingResultDrawerBody(
                foodName: foodDisplayName(items: displayItems),
                totals: displayTotals,
                items: displayItems,
                thoughtProcess: cameraThoughtProcess(items: displayItems, parseResult: parseResult),
                mode: .photoReview,
                onItemQuantityChange: { itemOffset, quantity in
                    updatePhotoItemQuantity(itemOffset: itemOffset, quantity: quantity, fallbackItems: items)
                },
                onRecalculate: nil
            )

            // CTA
            VStack(spacing: 10) {
                improveEstimateCard

                Button {
                    onLogIt(displayItems, displayTotals)
                } label: {
                    Text("Log it")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.420, green: 0.370, blue: 1.0),
                                         Color(red: 0.340, green: 0.295, blue: 0.900)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: onDiscard) {
                    Text("Discard")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    /// 2026-05-23: replaces the earlier loose "Improve this estimate" label
    /// + bare TextField + standalone Recalculate button. The new card
    /// visually groups the three so users see one cohesive affordance:
    /// header → field → action. Tapping anywhere on the header focuses the
    /// field so it doesn't require pixel-perfect aim on the text input.
    private var improveEstimateCard: some View {
        let hasNote = !contextNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            Button(action: { isContextNoteFocused = true }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a note to refine")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.141, green: 0.098, blue: 0.078))
                    Text("Tell us anything the camera missed — portion size, cooking method, brand.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.467, green: 0.416, blue: 0.380))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TextField(
                "e.g. 2 slices, homemade, with chutney",
                text: $contextNote,
                axis: .vertical
            )
            .font(.system(size: 15, weight: .medium))
            .lineLimit(1...3)
            .textInputAutocapitalization(.sentences)
            .disableAutocorrection(false)
            .focused($isContextNoteFocused)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isContextNoteFocused
                            ? Color(red: 0.902, green: 0.361, blue: 0.102).opacity(0.55)
                            : Color.black.opacity(0.08),
                        lineWidth: isContextNoteFocused ? 1.5 : 1
                    )
            )

            Button {
                isContextNoteFocused = false
                onRetry()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                    Text(hasNote ? "Recalculate with note" : "Recalculate")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    if hasNote {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .black))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: hasNote
                                    ? [Color(red: 1.00, green: 0.62, blue: 0.20),
                                       Color(red: 0.902, green: 0.361, blue: 0.102)]
                                    : [Color(red: 0.420, green: 0.370, blue: 1.0).opacity(0.78),
                                       Color(red: 0.340, green: 0.295, blue: 0.900).opacity(0.78)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(hasNote ? "Recalculate with note" : "Recalculate"))
            .accessibilityHint(Text("Re-runs the photo parse and applies any note you added."))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.278, green: 0.176, blue: 0.098).opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
    }

    private func seedEditablePhotoItemsIfNeeded(_ items: [ParsedFoodItem], force: Bool) {
        let signature = itemSignature(items)
        guard force || signature != editablePhotoSeedSignature else { return }
        editablePhotoSeedSignature = signature
        editablePhotoItems = items.map(EditableParsedItem.init(apiItem:))
    }

    private func itemSignature(_ items: [ParsedFoodItem]) -> String {
        items.map { item in
            [
                item.name,
                String(item.quantity),
                item.unit,
                String(item.amount ?? item.quantity),
                String(item.calories),
                String(item.protein),
                String(item.carbs),
                String(item.fat)
            ].joined(separator: "|")
        }
        .joined(separator: "||")
    }

    private func displayedPhotoItems(fallback items: [ParsedFoodItem]) -> [ParsedFoodItem] {
        if editablePhotoItems.isEmpty {
            return items
        }
        return editablePhotoItems.map { $0.asParsedFoodItem() }
    }

    private func totalsForItems(_ items: [ParsedFoodItem]) -> NutritionTotals {
        NutritionTotals(
            calories: roundOneDecimal(items.reduce(0) { $0 + $1.calories }),
            protein: roundOneDecimal(items.reduce(0) { $0 + $1.protein }),
            carbs: roundOneDecimal(items.reduce(0) { $0 + $1.carbs }),
            fat: roundOneDecimal(items.reduce(0) { $0 + $1.fat })
        )
    }

    private func roundOneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private func updatePhotoItemQuantity(itemOffset: Int, quantity: Double, fallbackItems: [ParsedFoodItem]) {
        if editablePhotoItems.isEmpty {
            editablePhotoItems = fallbackItems.map(EditableParsedItem.init(apiItem:))
        }
        guard editablePhotoItems.indices.contains(itemOffset) else { return }
        editablePhotoItems[itemOffset].updateQuantity(quantity)
    }

    private func reviewRecommended(items: [ParsedFoodItem], parseResult: ParseLogResponse?) -> Bool {
        if parseResult?.needsClarification == true {
            return true
        }
        if parseResult?.imageMeta?.coverage?.partial == true {
            return true
        }
        return items.contains { item in
            item.needsClarification == true || item.matchConfidence < 0.7
        }
    }

    private func reviewRecommendedCard(items: [ParsedFoodItem], parseResult: ParseLogResponse?) -> some View {
        let backendPrompt = parseResult?.clarificationQuestions.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let coverage = parseResult?.imageMeta?.coverage
        let coveragePrompt: String? = {
            guard let coverage, coverage.partial else { return nil }
            return "I found \(coverage.parsedItemCount) of about \(coverage.visibleComponentCount) visible foods. Give it a quick look before logging."
        }()
        let fallbackPrompt = items.count > 1
            ? "I found the visible foods, but a quick portion check will make this sharper."
            : "I found \(items.first?.name ?? "this food"), but the portion may need a quick check before logging."
        let question = backendPrompt?.isEmpty == false ? backendPrompt! : (coveragePrompt ?? fallbackPrompt)

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Review recommended")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(question)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.orange.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private func photoContextNoteEditor(title: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $contextNote, axis: .vertical)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1...3)
                .textInputAutocapitalization(.sentences)
                .disableAutocorrection(false)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        }
    }

    private func cameraThoughtProcess(items: [ParsedFoodItem], parseResult: ParseLogResponse?) -> String {
        if let coverage = parseResult?.imageMeta?.coverage, coverage.partial {
            let names = items.prefix(3).map(\.name)
            let preview = names.isEmpty
                ? "the foods it could identify"
                : names.joined(separator: ", ")
            let warning = coverage.warnings.first.map { " \($0)" } ?? ""
            return "Food App identified \(preview), but this photo may include more visible items than the estimate covers.\(warning) Review the detected foods or add a note if anything is missing."
        }
        if items.count > 1 {
            let names = items.prefix(3).map(\.name)
            let preview = names.count <= 2
                ? names.joined(separator: " & ")
                : "\(names[0]), \(names[1]) & more"
            let total = Int(items.reduce(0) { $0 + $1.calories }.rounded())
            return "Food App identified \(items.count) visible items from the photo: \(preview). It estimated the portions shown in the image, matched each item to standard nutrition data, and summed the item calories and macros. The current estimate is \(total) kcal total; review the detected items before logging if a portion looks off."
        }
        if let item = items.first {
            if let explanation = item.explanation,
               !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return explanation
            }
            let qty = HomeLoggingDisplayText.formatOneDecimal(item.quantity)
            return "Food App identified the visible food as \(item.name). It estimated the photo portion as \(qty) \(item.unit), matched that serving to standard nutrition data, and used the matched calories and macros for this result. Review the serving if the photographed portion was larger or smaller than a typical serving."
        }
        return "Photo analyzed. A calorie estimate is available."
    }

    // MARK: - Error State

    private func errorContent(message: String, image: UIImage?) -> some View {
        VStack(spacing: 20) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.black.opacity(0.35))
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.yellow)

                Text("Couldn't understand photo")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 12) {
                photoContextNoteEditor(
                    title: "Add a hint and try again",
                    placeholder: "Example: pizza, 2 slices"
                )
                .padding(.bottom, 2)
            }
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Button(action: onDiscard) {
                    Text("Dismiss")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button(action: onRetry) {
                    Text("Try Again")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Color(red: 0.380, green: 0.333, blue: 0.961),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Helpers

    private func foodDisplayName(items: [ParsedFoodItem]) -> String {
        if items.isEmpty { return "Food" }
        if items.count == 1 { return items[0].name }
        return "\(items.count) items detected"
    }
}

// MARK: - Skeleton Bar

private struct SkeletonBar: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(width: width, height: height)
            .overlay(
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color.white.opacity(0.5), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.55)
                        .offset(x: shimmerOffset * geo.size.width)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.6
                }
            }
    }
}
