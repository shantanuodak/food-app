import SwiftUI

// MARK: - Drawer State

enum CameraDrawerState {
    case idle
    case analyzing(UIImage)
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
    @State private var phaseTimer: Timer?
    @State private var editablePhotoItems: [EditableParsedItem] = []
    @State private var editablePhotoSeedSignature = ""

    private let analyzingPhrases = [
        "Reading the image",
        "Identifying food items",
        "Estimating portions",
        "Calculating nutrition"
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
                case .analyzing(let image):
                    analyzingContent(image: image)
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
        .onDisappear {
            phaseTimer?.invalidate()
            phaseTimer = nil
        }
    }

    // MARK: - Analyzing State

    private func analyzingContent(image: UIImage) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            // Full-width image with shimmer sweep
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
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
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1
                }
                phaseTimer?.invalidate()
                phaseTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: true) { _ in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        analyzePhaseIndex = (analyzePhaseIndex + 1) % analyzingPhrases.count
                    }
                }
            }

            // Cycling status line
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(Color(red: 0.380, green: 0.333, blue: 0.961))
                Text(analyzingPhrases[analyzePhaseIndex])
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .animation(.easeInOut(duration: 0.25), value: analyzePhaseIndex)
                Spacer()
            }
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
                photoContextNoteEditor(
                    title: "Improve this estimate",
                    placeholder: "Optional: 2 slices, homemade, with chutney..."
                )

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

                Button(action: onRetry) {
                    Label(contextNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Recalculate" : "Recalculate with note", systemImage: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.420, green: 0.370, blue: 1.0))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            Color(red: 0.420, green: 0.370, blue: 1.0).opacity(0.10),
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
