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
    let onLogIt: () -> Void
    let onDiscard: () -> Void
    let onRetry: () -> Void

    @State private var shimmerPhase: CGFloat = -1
    @State private var analyzePhaseIndex: Int = 0
    @State private var phaseTimer: Timer?

    private let analyzingPhrases = [
        "Reading the image",
        "Identifying food items",
        "Estimating portions",
        "Calculating nutrition"
    ]

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
        VStack(alignment: .leading, spacing: 0) {
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

                Button { onDiscard() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .padding(14)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
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
        VStack(alignment: .leading, spacing: 0) {
            // Hero image with re-parse + close icons
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 224)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 8) {
                    Button { onRetry() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.42), in: Circle())
                    }
                    Button { onDiscard() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.42), in: Circle())
                    }
                }
                .padding(13)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            LoggingResultDrawerBody(
                foodName: foodDisplayName(items: items),
                totals: totals,
                items: items,
                thoughtProcess: cameraThoughtProcess(items: items),
                onItemQuantityChange: nil,
                onRecalculate: onRetry
            )

            // CTA
            VStack(spacing: 4) {
                Button(action: onLogIt) {
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

                Button(action: onDiscard) {
                    Text("Discard")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    private func cameraThoughtProcess(items: [ParsedFoodItem]) -> String {
        if items.count > 1 {
            let names = items.prefix(3).map(\.name)
            let preview = names.count <= 2
                ? names.joined(separator: " & ")
                : "\(names[0]), \(names[1]) & more"
            let total = Int(items.reduce(0) { $0 + $1.calories }.rounded())
            return "Detected \(items.count) items from the photo: \(preview). Estimated \(total) kcal using standard nutrition data."
        }
        if let item = items.first {
            if let explanation = item.explanation,
               !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return explanation
            }
            let qty = HomeLoggingDisplayText.formatOneDecimal(item.quantity)
            return "Identified \"\(item.name)\" from the photo — \(Int(item.calories.rounded())) kcal using a \(qty) \(item.unit) standard portion."
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
        let names = items.prefix(3).map(\.name)
        if names.count == 2 { return names.joined(separator: " & ") }
        return names.dropLast().joined(separator: ", ") + " & " + names.last!
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
