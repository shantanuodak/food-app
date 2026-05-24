import SwiftUI
import UIKit
import AVFoundation

struct HomeFoodStoryDrawerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let anchorDate: Date
    let currentDayLogs: DayLogsResponse?
    let imageStorageService: ImageStorageService

    @Binding private var cachedDayLogs: [String: DayLogsResponse]

    @State private var selectedID: String?
    @State private var selectedBackgroundsByDay: [String: FoodStoryBackgroundOption] = [:]
    @State private var selectedVideosByDay: [String: FoodStoryVideoOption] = [:]
    @State private var selectedMediaByDay: [String: FoodStoryMediaKind] = [:]

    init(
        anchorDate: Date,
        currentDayLogs: DayLogsResponse?,
        cachedDayLogs: Binding<[String: DayLogsResponse]>,
        imageStorageService: ImageStorageService
    ) {
        self.anchorDate = anchorDate
        self.currentDayLogs = currentDayLogs
        self.imageStorageService = imageStorageService
        _cachedDayLogs = cachedDayLogs

        let initialDays = Array(FoodStoryDayBuilder.makeDays(
            anchorDate: anchorDate,
            currentDayLogs: currentDayLogs,
            cachedDayLogs: cachedDayLogs.wrappedValue
        ).reversed())
        _selectedID = State(initialValue: initialDays.last?.id)
    }

    private var days: [FoodStoryDay] {
        Array(FoodStoryDayBuilder.makeDays(
            anchorDate: anchorDate,
            currentDayLogs: currentDayLogs,
            cachedDayLogs: cachedDayLogs
        ).reversed())
    }

    private var selectedDay: FoodStoryDay {
        days.first { $0.id == selectedID } ?? days.last ?? FoodStoryDayBuilder.placeholderDay
    }

    var body: some View {
        ZStack {
            FoodStoryStaticBackdrop(day: selectedDay)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                storyDeck
                    .padding(.top, 8)

                storySourceSelector
                    .padding(.top, 2)

                Spacer(minLength: 8)

                shareButton
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(Color.black)
        .animation(.smooth(duration: reduceMotion ? 0.0 : 0.28), value: selectedDay.id)
        .onAppear {
            if selectedID == nil {
                selectedID = days.last?.id
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                FoodStoryGlassIconButton(systemName: "xmark") {
                    dismiss()
                }
                .accessibilityLabel(Text("Close food story"))

                Spacer(minLength: 8)

                VStack(spacing: 3) {
                    Text(selectedDay.dateTitle)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(FoodStoryTheme.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)

                    Text(selectedDay.weekdayTitle == "Today" ? "Today" : selectedDay.weekdayTitle)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(FoodStoryTheme.secondaryText)
                        .lineLimit(1)
                }
                .animation(.smooth(duration: reduceMotion ? 0.0 : 0.22), value: selectedDay.id)

                Spacer(minLength: 8)

                FoodStoryGlassIconButton(systemName: "sparkles") {
                    AppHaptics.selection()
                    advanceStory()
                }
                .accessibilityLabel(Text("Show another story"))
            }
            .padding(.horizontal, 18)
        }
        .padding(.top, 28)
    }

    private var storyDeck: some View {
        GeometryReader { proxy in
            let cardWidth = min(328.0, max(286.0, proxy.size.width * 0.82))
            let cardHeight = min(448.0, cardWidth * 1.54)
            let sidePadding = max(20.0, (proxy.size.width - cardWidth) / 2)

            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(days) { day in
                            FoodStoryShareCard(
                                day: day,
                                isActive: day.id == selectedID,
                                mediaKind: mediaKind(for: day),
                                background: background(for: day),
                                video: video(for: day),
                                imageStorageService: imageStorageService
                            )
                            .frame(width: cardWidth, height: cardHeight)
                            .id(day.id)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1.0 : 0.94)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 18)
                }
                .contentMargins(.horizontal, sidePadding, for: .scrollContent)
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedID)
                .onAppear {
                    DispatchQueue.main.async {
                        if let selectedID {
                            reader.scrollTo(selectedID, anchor: .center)
                        }
                    }
                }
                .onChange(of: selectedID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.smooth(duration: reduceMotion ? 0.0 : 0.22)) {
                        reader.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 464)
    }

    private var storySourceSelector: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                sourceSwatches
                    .padding(6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            mediaModeToggle
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.black.opacity(0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var sourceSwatches: some View {
        if mediaKind(for: selectedDay) == .video {
            HStack(spacing: 8) {
                ForEach(FoodStoryVideoOption.allCases) { option in
                    Button {
                        AppHaptics.selection()
                        withAnimation(.smooth(duration: reduceMotion ? 0.0 : 0.22)) {
                            selectedVideosByDay[selectedDay.id] = option
                            selectedMediaByDay[selectedDay.id] = .video
                        }
                    } label: {
                        FoodStoryVideoSwatch(option: option, isSelected: option == video(for: selectedDay))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Use \(option.title) video"))
                }
            }
        } else {
            HStack(spacing: 8) {
                ForEach(FoodStoryBackgroundOption.allCases) { option in
                    Button {
                        AppHaptics.selection()
                        withAnimation(.smooth(duration: reduceMotion ? 0.0 : 0.22)) {
                            selectedBackgroundsByDay[selectedDay.id] = option
                            selectedMediaByDay[selectedDay.id] = .background
                        }
                    } label: {
                        FoodStoryBackgroundSwatch(option: option, isSelected: option == background(for: selectedDay))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Use \(option.title) background"))
                }
            }
        }
    }

    private var mediaModeToggle: some View {
        VStack(spacing: 6) {
            mediaModeButton(kind: .background, systemName: "photo.fill", accessibilityLabel: "Show photo backgrounds")
            mediaModeButton(kind: .video, systemName: "video.fill", accessibilityLabel: "Show video backgrounds")
        }
        .padding(5)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
    }

    private func mediaModeButton(kind: FoodStoryMediaKind, systemName: String, accessibilityLabel: String) -> some View {
        let isSelected = mediaKind(for: selectedDay) == kind
        return Button {
            AppHaptics.selection()
            withAnimation(.smooth(duration: reduceMotion ? 0.0 : 0.22)) {
                selectedMediaByDay[selectedDay.id] = kind
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(isSelected ? FoodStoryTheme.cardText : FoodStoryTheme.cardOnImage)
                .frame(width: 36, height: 36)
                .background(isSelected ? FoodStoryTheme.cardOnImage : Color.white.opacity(0.12), in: Circle())
                .overlay {
                    Circle()
                        .stroke(isSelected ? Color.white.opacity(0.52) : Color.white.opacity(0.16), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var shareButton: some View {
        ShareLink(item: selectedDay.shareText) {
            Label("Share with friends", systemImage: "square.and.arrow.up.fill")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(Color(.displayP3, red: 0.055, green: 0.067, blue: 0.061))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(FoodStoryTheme.cardOnImage, in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.56), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.24), radius: 18, y: 10)
        }
        .simultaneousGesture(TapGesture().onEnded { AppHaptics.selection() })
    }

    private func advanceStory() {
        guard let currentIndex = days.firstIndex(where: { $0.id == selectedID }) else {
            selectedID = days.last?.id
            return
        }
        let nextIndex = currentIndex == days.startIndex
            ? days.index(before: days.endIndex)
            : days.index(before: currentIndex)
        withAnimation(.smooth(duration: reduceMotion ? 0.0 : 0.28)) {
            selectedID = days[nextIndex].id
        }
    }

    private func background(for day: FoodStoryDay) -> FoodStoryBackgroundOption {
        selectedBackgroundsByDay[day.id] ?? .morning
    }

    private func video(for day: FoodStoryDay) -> FoodStoryVideoOption {
        selectedVideosByDay[day.id] ?? .foodLoop
    }

    private func mediaKind(for day: FoodStoryDay) -> FoodStoryMediaKind {
        selectedMediaByDay[day.id] ?? .background
    }
}

private enum FoodStoryTheme {
    static let drawerTop = Color(.displayP3, red: 0.074, green: 0.090, blue: 0.086)
    static let drawerBottom = Color(.displayP3, red: 0.032, green: 0.037, blue: 0.036)
    static let drawerAccent = Color(.displayP3, red: 0.120, green: 0.360, blue: 0.320)
    static let primaryText = Color(.displayP3, red: 0.964, green: 0.970, blue: 0.940)
    static let secondaryText = Color(.displayP3, red: 0.710, green: 0.748, blue: 0.710)
    static let tertiaryText = Color(.displayP3, red: 0.520, green: 0.594, blue: 0.558)
    static let cardSurface = Color(.displayP3, red: 0.962, green: 0.966, blue: 0.935)
    static let cardSurfaceRaised = Color(.displayP3, red: 1.000, green: 0.992, blue: 0.958)
    static let cardText = Color(.displayP3, red: 0.096, green: 0.116, blue: 0.102)
    static let cardMuted = Color(.displayP3, red: 0.402, green: 0.442, blue: 0.404)
    static let cardLine = Color(.displayP3, red: 0.778, green: 0.816, blue: 0.750)
    static let cardScrimTop = Color.black.opacity(0.20)
    static let cardScrimBottom = Color.black.opacity(0.72)
    static let cardOnImage = Color(.displayP3, red: 0.992, green: 0.988, blue: 0.955)
    static let cardOnImageMuted = Color(.displayP3, red: 0.820, green: 0.850, blue: 0.792)
}

private enum FoodStoryBackgroundOption: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }

    var assetName: String {
        switch self {
        case .morning: return "ProfileBgMorning"
        case .afternoon: return "ProfileBgAfternoon"
        case .evening: return "ProfileBgEvening"
        }
    }

}

private enum FoodStoryMediaKind: Equatable {
    case background
    case video
}

private enum FoodStoryVideoOption: String, CaseIterable, Identifiable {
    case foodLoop
    case plateRun
    case dinnerGlow
    case galaxy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .foodLoop: return "Food loop"
        case .plateRun: return "Plate run"
        case .dinnerGlow: return "Dinner glow"
        case .galaxy: return "Galaxy"
        }
    }

    var assetName: String {
        switch self {
        case .foodLoop: return "ProfileBgMorning"
        case .plateRun: return "ProfileBgAfternoon"
        case .dinnerGlow: return "ProfileBgEvening"
        case .galaxy: return "food_photo_demo"
        }
    }

    var resourceName: String {
        switch self {
        case .foodLoop: return "story-video-uhd-food"
        case .plateRun: return "story-video-plate-run"
        case .dinnerGlow: return "story-video-dinner-glow"
        case .galaxy: return "story-video-milky-way"
        }
    }

    var bundleURL: URL? {
        Bundle.main.url(forResource: resourceName, withExtension: "mp4", subdirectory: "StoryVideos")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "mp4")
    }
}

private struct FoodStoryShareCard: View {
    let day: FoodStoryDay
    let isActive: Bool
    let mediaKind: FoodStoryMediaKind
    let background: FoodStoryBackgroundOption
    let video: FoodStoryVideoOption
    let imageStorageService: ImageStorageService

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                mediaBackground
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .overlay(cardScrim)

                cardContent
                    .padding(20)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.26), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            if isActive {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 4)
            }
        }
        .shadow(color: Color.black.opacity(isActive ? 0.32 : 0.20), radius: isActive ? 28 : 18, y: isActive ? 20 : 12)
        .compositingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
    }

    @ViewBuilder
    private var mediaBackground: some View {
        if mediaKind == .video, let url = video.bundleURL {
            FoodStoryLoopingVideoView(url: url)
        } else {
            Image(background.assetName)
                .resizable()
                .scaledToFill()
        }
    }

    private var cardScrim: some View {
        LinearGradient(
            colors: [
                FoodStoryTheme.cardScrimTop,
                Color.black.opacity(0.34),
                FoodStoryTheme.cardScrimBottom
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                FoodStoryAppMark()

                Spacer(minLength: 12)

                FoodStoryCalorieBadge(calories: day.calories)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(day.caption)
                    .font(.custom("InstrumentSerif-Regular", size: 35))
                    .foregroundStyle(FoodStoryTheme.cardOnImage)
                    .lineSpacing(-3)
                    .lineLimit(2)
                    .minimumScaleFactor(0.80)

                Text(day.summary)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(FoodStoryTheme.cardOnImageMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .shadow(color: Color.black.opacity(0.35), radius: 14, y: 5)

            FoodStoryMealCloud(
                meals: day.meals,
                isActive: isActive,
                imageStorageService: imageStorageService
            )

            Spacer(minLength: 0)
        }
    }
}

private struct FoodStoryMealCloud: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let meals: [FoodStoryMeal]
    let isActive: Bool
    let imageStorageService: ImageStorageService

    @State private var floatStickers = false

    var body: some View {
        Group {
            if meals.isEmpty {
                Text("No food logged yet")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(FoodStoryTheme.cardText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(FoodStoryTheme.cardSurfaceRaised, in: Capsule())
                    .overlay {
                        Capsule().stroke(Color.white.opacity(0.42), lineWidth: 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(visibleMeals.enumerated()), id: \.element.id) { index, meal in
                        FoodStoryMealStickerRow(
                            meal: meal,
                            index: index,
                            floatStickers: isActive && floatStickers && !reduceMotion,
                            imageStorageService: imageStorageService
                        )
                    }

                    if hiddenMealCount > 0 {
                        FoodStoryMoreBitesRow(
                            count: hiddenMealCount,
                            index: visibleMeals.count,
                            floatStickers: isActive && floatStickers && !reduceMotion
                        )
                        .padding(.top, 1)
                    }
                }
                .onAppear(perform: startFloating)
                .onChange(of: isActive) { _, _ in
                    startFloating()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var visibleMeals: [FoodStoryMeal] {
        Array(meals.prefix(4))
    }

    private var hiddenMealCount: Int {
        max(0, meals.count - visibleMeals.count)
    }

    private func startFloating() {
        guard isActive, !reduceMotion else {
            withAnimation(.none) {
                floatStickers = false
            }
            return
        }

        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            floatStickers = true
        }
    }
}

private struct FoodStoryLoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> FoodStoryLoopingVideoContainerView {
        let view = FoodStoryLoopingVideoContainerView()
        view.configure(url: url)
        return view
    }

    func updateUIView(_ uiView: FoodStoryLoopingVideoContainerView, context: Context) {
        uiView.configure(url: url)
    }

    static func dismantleUIView(_ uiView: FoodStoryLoopingVideoContainerView, coordinator: ()) {
        uiView.stop()
    }
}

private final class FoodStoryLoopingVideoContainerView: UIView {
    private let queuePlayer = AVQueuePlayer()
    private var playerLooper: AVPlayerLooper?
    private var currentURL: URL?

    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none
        playerLayer.player = queuePlayer
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(url: URL) {
        guard currentURL != url else {
            if queuePlayer.rate == 0 {
                queuePlayer.play()
            }
            return
        }

        currentURL = url
        queuePlayer.removeAllItems()
        let item = AVPlayerItem(url: url)
        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.play()
    }

    func stop() {
        queuePlayer.pause()
        queuePlayer.removeAllItems()
        playerLooper = nil
        currentURL = nil
    }
}

private struct FoodStoryMealStickerRow: View {
    let meal: FoodStoryMeal
    let index: Int
    let floatStickers: Bool
    let imageStorageService: ImageStorageService

    var body: some View {
        HStack(spacing: 0) {
            if isRightAligned {
                Spacer(minLength: 26)
            }

            FoodStoryMealSticker(
                meal: meal,
                index: index,
                imageStorageService: imageStorageService
            )
            .frame(width: stickerWidth, alignment: .leading)

            if !isRightAligned {
                Spacer(minLength: 26)
            }
        }
        .frame(maxWidth: .infinity)
        .offset(y: floatStickers ? floatingOffset : 0)
        .rotationEffect(.degrees(rotation))
    }

    private var isRightAligned: Bool {
        !index.isMultiple(of: 2)
    }

    private var stickerWidth: CGFloat {
        isRightAligned ? 232 : 252
    }

    private var rotation: Double {
        isRightAligned ? 1.2 : -1.0
    }

    private var floatingOffset: CGFloat {
        isRightAligned ? 3 : -3
    }
}

private struct FoodStoryMealSticker: View {
    let meal: FoodStoryMeal
    let index: Int
    let imageStorageService: ImageStorageService

    var body: some View {
        HStack(spacing: 9) {
            if let imageRef = meal.trimmedImageRef {
                FoodStoryMealThumbnail(imageRef: imageRef, imageStorageService: imageStorageService)
            }

            Text(meal.name)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(FoodStoryTheme.cardText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .padding(.leading, meal.trimmedImageRef == nil ? 16 : 8)
        .padding(.trailing, 16)
        .padding(.vertical, meal.trimmedImageRef == nil ? 10 : 6)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background {
            FoodStoryGlassStickerBackground(tint: chipTint, cornerRadius: 23)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 14, y: 8)
    }

    private var chipTint: Color {
        switch index % 4 {
        case 0: return Color(.displayP3, red: 1.000, green: 0.992, blue: 0.930)
        case 1: return Color(.displayP3, red: 0.898, green: 0.982, blue: 0.914)
        case 2: return Color(.displayP3, red: 0.982, green: 0.956, blue: 0.840)
        default: return Color(.displayP3, red: 0.922, green: 0.962, blue: 1.000)
        }
    }
}

private struct FoodStoryMoreBitesRow: View {
    let count: Int
    let index: Int
    let floatStickers: Bool

    var body: some View {
        HStack(spacing: 0) {
            if isRightAligned {
                Spacer(minLength: 26)
            }

            FoodStoryMoreBitesSticker(count: count)
                .frame(width: isRightAligned ? 170 : 184, alignment: .leading)

            if !isRightAligned {
                Spacer(minLength: 26)
            }
        }
        .frame(maxWidth: .infinity)
        .offset(y: floatStickers ? (isRightAligned ? 3 : -3) : 0)
        .rotationEffect(.degrees(isRightAligned ? 0.9 : -0.8))
    }

    private var isRightAligned: Bool {
        !index.isMultiple(of: 2)
    }
}

private struct FoodStoryMoreBitesSticker: View {
    let count: Int

    var body: some View {
        Text("+\(count) more \(count == 1 ? "bite" : "bites")")
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(FoodStoryTheme.cardText)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .center)
            .background {
                FoodStoryGlassStickerBackground(
                    tint: Color(.displayP3, red: 0.965, green: 0.985, blue: 1.000),
                    cornerRadius: 21
                )
            }
            .shadow(color: Color.black.opacity(0.22), radius: 12, y: 6)
    }
}

private struct FoodStoryGlassStickerBackground: View {
    let tint: Color
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            Color.white.opacity(0.001)
                .glassyBackground(
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                    tint: tint.opacity(0.22)
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            tint.opacity(0.20),
                            Color.white.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            Color.white.opacity(0.34),
                            Color.black.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.25
                )

            RoundedRectangle(cornerRadius: max(cornerRadius - 4, 8), style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 0.7)
                .padding(3)
                .blendMode(.screen)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.46),
                    Color.white.opacity(0.05),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct FoodStoryMealThumbnail: View {
    let imageRef: String
    let imageStorageService: ImageStorageService

    var body: some View {
        FoodStoryRemoteMealImage(imageRef: imageRef, imageStorageService: imageStorageService)
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.88), lineWidth: 3)
        }
        .overlay {
            Circle()
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
                .padding(2)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 7, y: 3)
        .accessibilityHidden(true)
    }
}

private struct FoodStoryRemoteMealImage: View {
    let imageRef: String
    let imageStorageService: ImageStorageService

    @State private var loadedImage: UIImage?
    @State private var didAttemptLoad = false

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 80
        return cache
    }()

    var body: some View {
        ZStack {
            Color.white.opacity(0.18)

            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if !didAttemptLoad {
                ProgressView()
                    .scaleEffect(0.62)
                    .tint(FoodStoryTheme.cardOnImage)
            } else {
                Image(systemName: "photo.fill")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(FoodStoryTheme.cardOnImage.opacity(0.88))
            }
        }
        .task(id: imageRef) {
            await load()
        }
    }

    private func load() async {
        loadedImage = nil
        didAttemptLoad = false

        if let cached = Self.cache.object(forKey: imageRef as NSString) {
            loadedImage = cached
            didAttemptLoad = true
            return
        }

        do {
            let data = try await imageStorageService.fetchJPEG(at: imageRef)
            guard let image = UIImage(data: data) else {
                didAttemptLoad = true
                return
            }
            Self.cache.setObject(image, forKey: imageRef as NSString)
            loadedImage = image
        } catch {
            didAttemptLoad = true
        }
    }
}

private struct FoodStoryAppMark: View {
    var body: some View {
        Text("F")
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(FoodStoryTheme.cardOnImage)
            .frame(width: 42, height: 42)
            .background(Color(.displayP3, red: 0.080, green: 0.420, blue: 0.302), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: Color.black.opacity(0.22), radius: 10, y: 6)
            .accessibilityHidden(true)
    }
}

private struct FoodStoryBackgroundSwatch: View {
    let option: FoodStoryBackgroundOption
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(option.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? FoodStoryTheme.cardOnImage : Color.white.opacity(0.20), lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: Color.black.opacity(isSelected ? 0.28 : 0.12), radius: isSelected ? 12 : 6, y: isSelected ? 7 : 3)

            Text(option.title)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(isSelected ? FoodStoryTheme.primaryText : FoodStoryTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(width: 72)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
        }
    }
}

private struct FoodStoryVideoSwatch: View {
    let option: FoodStoryVideoOption
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                swatchMedia
                    .frame(width: 58, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.08),
                                Color.black.opacity(0.46)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                Image(systemName: "play.fill")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(FoodStoryTheme.cardOnImage)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.34), in: Circle())
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.22), lineWidth: 1)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? FoodStoryTheme.cardOnImage : Color.white.opacity(0.20), lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: Color.black.opacity(isSelected ? 0.28 : 0.12), radius: isSelected ? 12 : 6, y: isSelected ? 7 : 3)

            Text(option.title)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(isSelected ? FoodStoryTheme.primaryText : FoodStoryTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
        .frame(width: 72)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var swatchMedia: some View {
        if let url = option.bundleURL {
            FoodStoryLoopingVideoView(url: url)
        } else {
            Image(option.assetName)
                .resizable()
                .scaledToFill()
        }
    }
}

private struct FoodStoryCalorieBadge: View {
    let calories: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(calories.formatted())
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(FoodStoryTheme.cardText)
                .monospacedDigit()

            Text("calories")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(FoodStoryTheme.cardMuted)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(FoodStoryTheme.cardSurfaceRaised, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(FoodStoryTheme.cardLine, lineWidth: 1)
        }
    }
}

private struct FoodStoryGlassIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(FoodStoryTheme.primaryText)
                .frame(width: 46, height: 46)
                .background(Color(.displayP3, red: 0.118, green: 0.135, blue: 0.128), in: Circle())
                .overlay {
                    Circle().stroke(Color(.displayP3, red: 0.250, green: 0.290, blue: 0.265), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct FoodStoryStaticBackdrop: View {
    let day: FoodStoryDay

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    day.palette.ink,
                    day.palette.deep,
                    day.palette.accent.opacity(0.44),
                    FoodStoryTheme.drawerBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    day.palette.glow.opacity(0.28),
                    day.palette.hot.opacity(0.12),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 18,
                endRadius: 380
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.26),
                    Color.black.opacity(0.48)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct FoodStoryDay: Identifiable {
    let id: String
    let date: Date
    let weekdayTitle: String
    let dateTitle: String
    let summary: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let caption: String
    let musicTitle: String
    let heroAssetName: String
    let meals: [FoodStoryMeal]
    let palette: FoodStoryPalette

    var shareText: String {
        "\(weekdayTitle) food story: \(caption) \(calories.formatted()) calories logged in Food App."
    }

    var accessibilityDate: String {
        "\(weekdayTitle), \(dateTitle)"
    }

    var accessibilityLabel: String {
        "\(accessibilityDate). \(summary). \(calories) calories. \(caption)"
    }
}

private struct FoodStoryMeal: Identifiable {
    let id: String
    let name: String
    let calories: Int
    let assetName: String
    let imageRef: String?

    var trimmedImageRef: String? {
        guard let value = imageRef?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct FoodStoryPalette {
    let ink: Color
    let deep: Color
    let glow: Color
    let accent: Color
    let hot: Color

    static let palettes: [FoodStoryPalette] = [
        FoodStoryPalette(
            ink: Color(.displayP3, red: 0.035, green: 0.046, blue: 0.042),
            deep: Color(.displayP3, red: 0.035, green: 0.200, blue: 0.175),
            glow: Color(.displayP3, red: 0.550, green: 0.950, blue: 0.780),
            accent: Color(.displayP3, red: 0.180, green: 0.610, blue: 0.860),
            hot: Color(.displayP3, red: 0.940, green: 0.350, blue: 0.360)
        ),
        FoodStoryPalette(
            ink: Color(.displayP3, red: 0.060, green: 0.045, blue: 0.080),
            deep: Color(.displayP3, red: 0.160, green: 0.075, blue: 0.240),
            glow: Color(.displayP3, red: 0.720, green: 0.560, blue: 1.000),
            accent: Color(.displayP3, red: 0.980, green: 0.650, blue: 0.230),
            hot: Color(.displayP3, red: 0.960, green: 0.250, blue: 0.470)
        ),
        FoodStoryPalette(
            ink: Color(.displayP3, red: 0.048, green: 0.044, blue: 0.036),
            deep: Color(.displayP3, red: 0.260, green: 0.130, blue: 0.045),
            glow: Color(.displayP3, red: 1.000, green: 0.850, blue: 0.330),
            accent: Color(.displayP3, red: 0.920, green: 0.360, blue: 0.100),
            hot: Color(.displayP3, red: 0.390, green: 0.820, blue: 0.510)
        )
    ]
}

private enum FoodStoryDayBuilder {
    static let placeholderDay = FoodStoryDay(
        id: "placeholder",
        date: Date(),
        weekdayTitle: "Today",
        dateTitle: "Today",
        summary: "No meals logged yet",
        calories: 0,
        protein: 0,
        carbs: 0,
        fat: 0,
        caption: "No food logged yet",
        musicTitle: "Default: Kitchen Lights",
        heroAssetName: "ProfileBgMorning",
        meals: [],
        palette: FoodStoryPalette.palettes[0]
    )

    private static let heroAssets = [
        "food_photo_demo",
        "IntroFood1",
        "IntroFood2",
        "ProfileBgMorning",
        "ProfileBgAfternoon",
        "ProfileBgEvening"
    ]

    private static let musicTitles = [
        "Default: Kitchen Lights",
        "Default: Late Dinner",
        "Default: Morning Walk",
        "Default: Gym Cut"
    ]

    static func makeDays(
        anchorDate: Date,
        currentDayLogs: DayLogsResponse?,
        cachedDayLogs: [String: DayLogsResponse]
    ) -> [FoodStoryDay] {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: HomeLoggingDateUtils.clampedSummaryDate(anchorDate))

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: anchor) else {
                return nil
            }
            let key = HomeLoggingDateUtils.summaryRequestFormatter.string(from: date)
            let response = currentDayLogs?.date == key ? currentDayLogs : cachedDayLogs[key]

            if let response {
                return dayFromLogs(response, date: date, offset: offset)
            }
            return emptyDay(date: date, offset: offset)
        }
    }

    private static func dayFromLogs(_ response: DayLogsResponse, date: Date, offset: Int) -> FoodStoryDay {
        let totals = response.logs.reduce(NutritionTotals(calories: 0, protein: 0, carbs: 0, fat: 0)) { partial, log in
            NutritionTotals(
                calories: partial.calories + log.totals.calories,
                protein: partial.protein + log.totals.protein,
                carbs: partial.carbs + log.totals.carbs,
                fat: partial.fat + log.totals.fat
            )
        }

        let items = response.logs
            .flatMap { log in
                log.items.map { item in
                    (item: item, imageRef: log.imageRef)
                }
            }
            .sorted { $0.item.calories > $1.item.calories }
        let topFoodNames = items.prefix(4).map { $0.item.foodName }

        let meals: [FoodStoryMeal]
        if items.isEmpty {
            meals = response.logs.prefix(12).enumerated().map { index, log in
                FoodStoryMeal(
                    id: "\(response.date)-log-\(index)",
                    name: cleanName(log.rawText, fallback: "Logged meal"),
                    calories: Int(log.totals.calories.rounded()),
                    assetName: heroAssets[(offset + index) % heroAssets.count],
                    imageRef: log.imageRef
                )
            }
        } else {
            meals = items.prefix(12).enumerated().map { index, entry in
                FoodStoryMeal(
                    id: entry.item.id,
                    name: cleanName(entry.item.foodName, fallback: "Logged food"),
                    calories: Int(entry.item.calories.rounded()),
                    assetName: heroAssets[(offset + index) % heroAssets.count],
                    imageRef: entry.imageRef
                )
            }
        }

        let itemCount = items.isEmpty ? response.logs.count : items.count
        let protein = Int(totals.protein.rounded())
        return FoodStoryDay(
            id: response.date,
            date: date,
            weekdayTitle: title(for: date),
            dateTitle: dateTitle(for: date),
            summary: "\(itemCount) \(itemCount == 1 ? "item" : "items") logged",
            calories: Int(totals.calories.rounded()),
            protein: protein,
            carbs: Int(totals.carbs.rounded()),
            fat: Int(totals.fat.rounded()),
            caption: headline(
                foodNames: topFoodNames.isEmpty ? response.logs.map(\.rawText) : topFoodNames,
                calories: totals.calories,
                itemCount: itemCount,
                offset: offset
            ),
            musicTitle: musicTitles[offset % musicTitles.count],
            heroAssetName: heroAssets[offset % heroAssets.count],
            meals: meals,
            palette: FoodStoryPalette.palettes[offset % FoodStoryPalette.palettes.count]
        )
    }

    private static func emptyDay(date: Date, offset: Int) -> FoodStoryDay {
        return FoodStoryDay(
            id: HomeLoggingDateUtils.summaryRequestFormatter.string(from: date),
            date: date,
            weekdayTitle: title(for: date),
            dateTitle: dateTitle(for: date),
            summary: "No meals logged yet",
            calories: 0,
            protein: 0,
            carbs: 0,
            fat: 0,
            caption: "No food logged yet",
            musicTitle: musicTitles[offset % musicTitles.count],
            heroAssetName: heroAssets[offset % heroAssets.count],
            meals: [],
            palette: FoodStoryPalette.palettes[offset % FoodStoryPalette.palettes.count]
        )
    }

    private static func title(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private static func dateTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private static func cleanName(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return fallback
        }

        var cleaned = trimmed
        if let parentheticalRange = cleaned.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            let candidate = String(cleaned[..<parentheticalRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                cleaned = candidate
            }
        }

        return cleaned.isEmpty ? fallback : cleaned
    }

    private static func headline(foodNames: [String], calories: Double, itemCount: Int, offset: Int) -> String {
        if itemCount == 0 {
            return "A blank story, ready for the first bite."
        }

        let joinedNames = foodNames.joined(separator: " ").lowercased()
        if containsAny(joinedNames, ["coffee", "yogurt", "oat", "egg", "croissant", "toast", "bagel"]) {
            return pick(["Morning bite run", "Soft start, good fuel", "Breakfast had range"], offset: offset)
        }
        if containsAny(joinedNames, ["sushi", "salmon", "tuna", "rice", "poke"]) {
            return pick(["Clean plate energy", "Sushi mood logged", "Fresh bowl kind of day"], offset: offset)
        }
        if containsAny(joinedNames, ["taco", "burrito", "curry", "spicy", "masala", "chili"]) {
            return pick(["Spice did the talking", "A little heat, nicely done", "Big flavor loop"], offset: offset)
        }
        if containsAny(joinedNames, ["burger", "fries", "pizza", "wings", "sandwich"]) {
            return pick(["Comfort food chapter", "Crispy, saucy, logged", "A real plate day"], offset: offset)
        }
        if containsAny(joinedNames, ["ramen", "noodle", "soup", "pho", "udon"]) {
            return pick(["Warm bowl weather", "Noodle night energy", "Cozy food arc"], offset: offset)
        }
        if containsAny(joinedNames, ["salad", "fruit", "greens", "smoothie", "bowl"]) {
            return pick(["Light and crisp", "Fresh stuff forward", "Green day glow"], offset: offset)
        }
        if calories >= 2200 {
            return pick(["Big appetite day", "Full-stack fuel", "No tiny bites here"], offset: offset)
        }
        if calories <= 1500 {
            return pick(["Small bites, calm finish", "Light plate rhythm", "Easy day, still logged"], offset: offset)
        }
        return fallbackHeadline(for: offset)
    }

    private static func fallbackHeadline(for offset: Int) -> String {
        [
            "Clean plates, big flavor",
            "Weekend plate energy",
            "Light lunch, loud dinner",
            "A little spice, still on track",
            "Simple day, solid finish",
            "Snacky but balanced",
            "Monday reset, actually good"
        ][offset % 7]
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private static func pick(_ values: [String], offset: Int) -> String {
        values[offset % values.count]
    }
}
