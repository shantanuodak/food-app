import AVFoundation
import SwiftUI
import UIKit

struct MainLoggingBottomDock: View {
    @Environment(\.colorScheme) private var colorScheme

    let shouldShowSyncExceptionPill: Bool
    let syncStatusTitle: String
    let syncStatusExplanation: String
    let currentFoodLogStreak: Int?
    let isLoadingFoodLogStreak: Bool
    let isKeyboardVisible: Bool
    @Binding var isSyncInfoPresented: Bool
    @Binding var isProgressChartsPresented: Bool
    @Binding var isSavedMealsPresented: Bool

    private let dockHitSize: CGFloat = 60
    private let dockCircleSize: CGFloat = 44
    private let dockIconSize: CGFloat = 16

    var body: some View {
        VStack(spacing: 10) {
            if shouldShowSyncExceptionPill {
                syncStatusPill
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // 2026-05-23 dock layout: rewards/streak sits dead center of the
            // screen with two equal flex spacers on either side. Left cluster
            // stays Camera + Mic, right cluster stays Saved + Graph.
            HStack(spacing: 0) {
                HStack(spacing: 12) {
                    bottomDockButton(
                        systemImage: "camera.fill",
                        color: Color(red: 0.360, green: 0.322, blue: 0.980),
                        accessibilityLabel: "Open camera"
                    ) {
                        NotificationCenter.default.post(name: .openCameraFromTabBar, object: nil)
                    }

                    bottomDockButton(
                        systemImage: "mic.fill",
                        color: Color(red: 0.760, green: 0.168, blue: 0.860),
                        accessibilityLabel: "Voice input"
                    ) {
                        NotificationCenter.default.post(name: .openVoiceFromTabBar, object: nil)
                    }
                }

                Spacer(minLength: 6)

                streakDockIndicator

                Spacer(minLength: 6)

                HStack(spacing: 12) {
                    bottomDockButton(
                        systemImage: "bookmark.fill",
                        color: Color(red: 0.950, green: 0.340, blue: 0.100),
                        accessibilityLabel: "Open saved meals"
                    ) {
                        // Saved meals lives in MainLoggingShellView; route via
                        // the existing keyboard-dismiss + binding flip.
                        NotificationCenter.default.post(name: .dismissKeyboardFromTabBar, object: nil)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        isSavedMealsPresented = true
                    }

                    bottomDockButton(
                        systemImage: "chart.line.uptrend.xyaxis",
                        color: Color(red: 1.000, green: 0.520, blue: 0.120),
                        accessibilityLabel: "Open progress charts"
                    ) {
                        isProgressChartsPresented = true
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .background(alignment: .bottom) {
            dockBackdrop
        }
    }

    private var dockSurfaceColor: Color {
        colorScheme == .dark ? AppColor.shellBackgroundBottom : Color(uiColor: .systemBackground)
    }

    private var dockBackdrop: some View {
        LinearGradient(
            colors: [
                dockSurfaceColor.opacity(0),
                dockSurfaceColor.opacity(isKeyboardVisible ? 0.94 : 0.72),
                dockSurfaceColor.opacity(isKeyboardVisible ? 1.0 : 0.92)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: shouldShowSyncExceptionPill ? 148 : 112)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    private var syncStatusPill: some View {
        Button {
            AppHaptics.lightImpact()
            isSyncInfoPresented = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)

                Text(syncStatusTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .accessibilityLabel(Text(syncStatusTitle))
        .alert("Pending sync", isPresented: $isSyncInfoPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(syncStatusExplanation)
        }
    }

    private var streakDockIndicator: some View {
        Button {
            AppHaptics.lightImpact()
            NotificationCenter.default.post(name: .openStreaksFromNotification, object: nil)
        } label: {
            ZStack(alignment: .topTrailing) {
                trophyStreakIcon

                if isLoadingFoodLogStreak && currentFoodLogStreak == nil {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(8)
                        .allowsHitTesting(false)
                } else {
                    Text("\(currentFoodLogStreak ?? 0)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 23, minHeight: 23)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.86))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        )
                        .shadow(color: Color.black.opacity(0.34), radius: 4, y: 2)
                        .offset(x: 3, y: 2)
                        .allowsHitTesting(false)
                }
            }
            // Without contentShape the badge's regularMaterial Circle could
            // intercept hits on the bottom-right corner of the button area.
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(streakAccessibilityLabel))
    }

    private var streakAccessibilityLabel: String {
        let days = currentFoodLogStreak ?? 0
        let badgeTitle = StreakBadges.currentBadge(for: days)?.title ?? "First Spark awaits"
        return "Open badges, \(days)-day food streak, \(badgeTitle)"
    }

    private var trophyStreakIcon: some View {
        dockIconBadge(
            systemImage: "trophy.fill",
            gradientColors: [
                Color(red: 1.0, green: 0.92, blue: 0.32),
                Color(red: 1.0, green: 0.68, blue: 0.12)
            ],
            glowColor: Color.yellow,
            iconSize: 17
        )
    }

    private func dockIconBadge(
        systemImage: String,
        gradientColors: [Color],
        glowColor: Color,
        iconSize: CGFloat = 16
    ) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: glowColor.opacity(0.24), radius: 8, y: 3)
                .shadow(color: glowColor.opacity(0.12), radius: 14, y: 3)

            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.45, green: 0.24, blue: 0.02),
                            Color(red: 0.30, green: 0.16, blue: 0.01)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .white.opacity(0.35), radius: 1, y: -0.5)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.22),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .allowsHitTesting(false)
        }
        .frame(width: dockCircleSize, height: dockCircleSize)
        .frame(width: dockHitSize, height: dockHitSize)
    }

    private func bottomDockButton(
        systemImage: String,
        color: Color,
        tintStrength: Double = 1.0,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        let adjustedTintStrength = min(max(tintStrength, 0), 1)

        return Button(action: {
            AppHaptics.lightImpact()
            action()
        }) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                dockSurfaceColor,
                                dockSurfaceColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        color.opacity(0.28 * adjustedTintStrength),
                                        color.opacity(0.16 * adjustedTintStrength)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Circle()
                            .stroke(color.opacity(0.40 * adjustedTintStrength), lineWidth: 1)
                    )
                    .shadow(color: color.opacity(0.12 * adjustedTintStrength), radius: 7, y: 3)
                    .frame(width: dockCircleSize, height: dockCircleSize)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.08 : 0.32),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                    .frame(width: dockCircleSize, height: dockCircleSize)
                    .allowsHitTesting(false)

                Image(systemName: systemImage)
                    .font(.system(size: dockIconSize, weight: .bold))
                    .foregroundStyle(color.opacity(adjustedTintStrength))
                    .shadow(color: color.opacity(0.18 * adjustedTintStrength), radius: 2, y: 1)
            }
            .frame(width: dockHitSize, height: dockHitSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

struct MainLoggingTopHeaderStrip: View {
    let firstName: String?
    let dateTitle: String
    let colorScheme: ColorScheme
    /// 0 at the scroll-top resting state, ramping to 1 as content scrolls up
    /// under the header. Drives the occluding scrim so the header has *no*
    /// background at rest (no visible "panel"), matching native nav-bar
    /// scroll-edge behaviour.
    let scrimOpacity: CGFloat
    @Binding var isFoodStoryPresented: Bool
    @Binding var isProfilePresented: Bool
    @Binding var isCalendarPresented: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                AppHaptics.lightImpact()
                isProfilePresented = true
            } label: {
                HomeGreetingChip(firstName: firstName)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Open profile"))

            Spacer(minLength: 0)

            Button {
                AppHaptics.lightImpact()
                isFoodStoryPresented = true
            } label: {
                FoodStoryHeaderPreviewIcon()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Open food story"))

            Button {
                AppHaptics.selection()
                isCalendarPresented = true
            } label: {
                HStack(spacing: 4) {
                    Text(dateTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(dateTextColor.opacity(0.48))
                }
                .foregroundStyle(dateTextColor)
                .frame(minHeight: 44, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Select date"))
        }
        .padding(.horizontal, 10)
        .background(alignment: .top) {
            headerBackdrop
        }
    }

    private var dateTextColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.94)
            : Color.primary.opacity(0.72)
    }

    private var headerSurfaceColor: Color {
        colorScheme == .dark ? AppColor.shellBackgroundTop : Color(uiColor: .systemBackground)
    }

    /// The shell-gradient colour at the band's opaque-plateau end (the 0.62
    /// stop ≈ 46pt below the screen top) — i.e. what the surface behind the
    /// band has darkened to there.
    ///
    /// `AppColor.shellBackground` runs from `shellBackgroundTop` (white 0.08 in
    /// dark) at y=0 to black at the screen bottom. ~46pt down is ~5.3% of the
    /// full-screen gradient, so the matching colour is `0.08 * (1 - 0.053) ≈
    /// 0.076`. The device-to-device variance of that fraction (812–932pt tall)
    /// is < 0.001 in white value — imperceptible. Light mode resolves to
    /// `systemBackground` (the shell gradient is a no-op there), so this matches
    /// `headerSurfaceColor` and nothing changes.
    private var headerBackdropBottomColor: Color {
        colorScheme == .dark ? Color(white: 0.076) : Color(uiColor: .systemBackground)
    }

    /// Mirror of the bottom dock's `dockBackdrop`, flipped vertically: a scrim
    /// that occludes content scrolling up behind the greeting, icons, and date.
    ///
    /// The opaque region is itself a slice of the shell gradient — top stop
    /// `headerSurfaceColor` (shell at y=0), bottom stop `headerBackdropBottomColor`
    /// (shell ~74pt down). Tracking the shell's darkening this way keeps the band
    /// the *same colour as the surface behind it at every point*, so it stays
    /// invisible at rest and never reads as a lighter rectangle on scroll. The
    /// earlier flat-`headerSurfaceColor` plateau drifted lighter than the
    /// darkening shell underneath and showed as a faint tint when the scrim
    /// ramped in.
    ///
    /// safeAreaInset bleeds this background up into the status bar for free, so
    /// the frame height only needs to span the controls + a short fade. `-6`
    /// horizontal counters the outer `.padding(.horizontal, 6)` at the inset.
    private var headerBackdrop: some View {
        LinearGradient(
            stops: [
                .init(color: headerSurfaceColor, location: 0.0),
                .init(color: headerBackdropBottomColor, location: 0.62),
                .init(color: headerBackdropBottomColor.opacity(0), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 74)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, -6)
        .opacity(Double(scrimOpacity))
        .allowsHitTesting(false)
    }

}

private struct FoodStoryHeaderPreviewIcon: View {
    private let assets = [
        "ProfileBgMorning",
        "ProfileBgAfternoon",
        "ProfileBgEvening"
    ]

    var body: some View {
        iconFrame
        .frame(width: 42, height: 38)
        .contentShape(Rectangle())
    }

    private var iconFrame: some View {
        ZStack {
            storyCard(assetName: assets[0], width: 19, height: 27, cornerRadius: 6)
                .rotationEffect(.degrees(-8))
                .offset(x: -10, y: 2)

            storyCard(assetName: assets[2], width: 19, height: 27, cornerRadius: 6)
                .rotationEffect(.degrees(9))
                .offset(x: 10, y: 2)

            storyCard(assetName: assets[1], width: 22, height: 30, cornerRadius: 7)
                .offset(y: -2)
        }
    }

    private func storyCard(assetName: String, width: CGFloat, height: CGFloat, cornerRadius: CGFloat) -> some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.52), lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.22), radius: 4, y: 2)
    }
}

/// How-to video library. Pushed from the "Tutorials" tile in the profile
/// (mirrors Saved Meals / Recipes) — its own nav title carries the heading,
/// so there's no in-content title.
struct TutorialLibrarySheet: View {
    @State private var activeTutorialID: TutorialVideoItem.ID? = TutorialVideoItem.logMeal.id

    private let tutorials: [TutorialVideoItem] = [
        .logMeal,
        .viewMealDetails,
        .logWater
    ]

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(tutorials) { tutorial in
                        TutorialVideoCard(
                            tutorial: tutorial,
                            isActive: activeTutorialID == tutorial.id
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .coordinateSpace(name: TutorialScrollSpace.name)
            .onPreferenceChange(TutorialCardFramePreferenceKey.self) { frames in
                updateActiveTutorial(from: frames, viewportHeight: proxy.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppDrawerSurface.gradient.ignoresSafeArea())
        .navigationTitle("Tutorials")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            activeTutorialID = nil
        }
    }

    private func updateActiveTutorial(from frames: [TutorialCardFrame], viewportHeight: CGFloat) {
        let visibleFrames = frames.compactMap { card -> (id: TutorialVideoItem.ID, distance: CGFloat)? in
            let visibleHeight = min(card.frame.maxY, viewportHeight) - max(card.frame.minY, 0)
            guard visibleHeight > 80 else { return nil }
            return (card.id, abs(card.frame.midY - viewportHeight * 0.5))
        }

        activeTutorialID = visibleFrames.min { $0.distance < $1.distance }?.id ?? TutorialVideoItem.logMeal.id
    }
}

private struct TutorialVideoCard: View {
    let tutorial: TutorialVideoItem
    let isActive: Bool
    @State private var player: AVPlayer?
    @State private var playbackEndObserver: NSObjectProtocol?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tutorial.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            if let player {
                TutorialPlayerLayerView(player: player)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if tutorial.bundleURL != nil {
                idleVideoView
            } else {
                missingVideoView
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 18, y: 10)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TutorialCardFramePreferenceKey.self,
                    value: [
                        TutorialCardFrame(
                            id: tutorial.id,
                            frame: proxy.frame(in: .named(TutorialScrollSpace.name))
                        )
                    ]
                )
            }
        }
        .onAppear {
            playIfActive()
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                playIfActive()
            } else {
                stopAndReleasePlayer()
            }
        }
        .onDisappear {
            stopAndReleasePlayer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(tutorial.title))
    }

    private var idleVideoView: some View {
        ZStack {
            Color.black

            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 58, height: 58)

            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .offset(x: 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var missingVideoView: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.20))

            Text("Tutorial video unavailable")
                .font(.system(size: 17, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func playIfActive() {
        guard isActive else { return }
        loadPlayerIfNeeded()
        player?.seek(to: .zero)
        player?.play()
    }

    private func stopAndReleasePlayer() {
        player?.pause()
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        player = nil
    }

    private func loadPlayerIfNeeded() {
        guard player == nil, let url = tutorial.bundleURL else { return }

        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        self.player = player
    }
}

private enum TutorialScrollSpace {
    static let name = "TutorialScrollSpace"
}

private struct TutorialCardFrame: Equatable {
    let id: TutorialVideoItem.ID
    let frame: CGRect
}

private struct TutorialCardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [TutorialCardFrame] = []

    static func reduce(value: inout [TutorialCardFrame], nextValue: () -> [TutorialCardFrame]) {
        value.append(contentsOf: nextValue())
    }
}

private struct TutorialPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> TutorialPlayerContainerView {
        let view = TutorialPlayerContainerView()
        view.configure(player: player)
        return view
    }

    func updateUIView(_ uiView: TutorialPlayerContainerView, context: Context) {
        uiView.configure(player: player)
    }

    static func dismantleUIView(_ uiView: TutorialPlayerContainerView, coordinator: ()) {
        uiView.configure(player: nil)
    }
}

private final class TutorialPlayerContainerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(player: AVPlayer?) {
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
    }
}

private struct TutorialVideoItem: Identifiable, Hashable {
    let id: String
    let title: String
    let darkResourceName: String
    let lightResourceName: String?

    static let logMeal = TutorialVideoItem(
        id: "log-meal",
        title: "Log meal",
        darkResourceName: "LogMealDark",
        lightResourceName: nil
    )

    static let viewMealDetails = TutorialVideoItem(
        id: "view-meal-details",
        title: "View meal details",
        darkResourceName: "ViewMealDetailsDark",
        lightResourceName: nil
    )

    static let logWater = TutorialVideoItem(
        id: "log-water",
        title: "Log your water",
        darkResourceName: "LogWaterDark",
        lightResourceName: nil
    )

    var bundleURL: URL? {
        Bundle.main.url(forResource: darkResourceName, withExtension: "mp4", subdirectory: "Tutorials")
            ?? Bundle.main.url(forResource: darkResourceName, withExtension: "mp4")
    }
}
