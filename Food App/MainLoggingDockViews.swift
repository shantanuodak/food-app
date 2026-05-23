import SwiftUI
import UIKit

struct MainLoggingBottomDock: View {
    let shouldShowSyncExceptionPill: Bool
    let syncStatusTitle: String
    let syncStatusExplanation: String
    let currentFoodLogStreak: Int?
    let isLoadingFoodLogStreak: Bool
    let isKeyboardVisible: Bool
    @Binding var isSyncInfoPresented: Bool
    @Binding var isProgressChartsPresented: Bool
    @Binding var isSavedMealsPresented: Bool

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
                        color: Color(red: 0.380, green: 0.333, blue: 0.961),
                        accessibilityLabel: "Open camera"
                    ) {
                        NotificationCenter.default.post(name: .openCameraFromTabBar, object: nil)
                    }

                    bottomDockButton(
                        systemImage: "mic.fill",
                        color: Color(red: 0.796, green: 0.188, blue: 0.878),
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
                        color: Color(red: 0.902, green: 0.361, blue: 0.102),
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
                        color: Color(red: 0.95, green: 0.47, blue: 0.11),
                        accessibilityLabel: "Open progress charts"
                    ) {
                        isProgressChartsPresented = true
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
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
            ZStack(alignment: .bottomTrailing) {
                trophyStreakIcon

                if isLoadingFoodLogStreak && currentFoodLogStreak == nil {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(8)
                        .allowsHitTesting(false)
                } else {
                    Text("\(currentFoodLogStreak ?? 0)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(.regularMaterial, in: Circle())
                        .padding(8)
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
            badgeSize: 48,
            iconSize: 18
        )
    }

    private func dockIconBadge(
        systemImage: String,
        gradientColors: [Color],
        glowColor: Color,
        badgeSize: CGFloat = 48,
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
                .shadow(color: glowColor.opacity(0.35), radius: 10, y: 4)

            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(red: 1.0, green: 0.96, blue: 0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: glowColor.opacity(0.28), radius: 2, y: 1)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.28),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .allowsHitTesting(false)
        }
        .frame(width: badgeSize, height: badgeSize)
        .frame(width: 60, height: 60)
    }

    private func bottomDockButton(
        systemImage: String,
        color: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            AppHaptics.lightImpact()
            action()
        }) {
            ZStack {
                dockIconLens(color: color)

                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.18), radius: 2, y: 1)
            }
                .frame(width: 48, height: 48)
                .frame(width: 60, height: 60)
                .background(dockButtonShell)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var dockButtonShell: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .shadow(color: Color.black.opacity(0.06), radius: 12, y: 5)
    }

    @ViewBuilder
    private func dockIconLens(color: Color) -> some View {
        Circle()
            .fill(Color.white.opacity(0.04))
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.34),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 22)
                    .offset(x: 7, y: 7)
            }
            .modifier(DockIconLiquidGlassTint(color: color))
            .allowsHitTesting(false)
    }
}

private struct DockIconLiquidGlassTint: ViewModifier {
    let color: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .background(color.opacity(0.08), in: Circle())
            .background(.ultraThinMaterial, in: Circle())
    }
}

struct MainLoggingTopHeaderStrip: View {
    let firstName: String?
    let dateTitle: String
    let colorScheme: ColorScheme
    @Binding var isProfilePresented: Bool
    @Binding var isCalendarPresented: Bool

    @State private var isTutorialPresented: Bool = false
    @State private var helpIconRotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            // Tutorial entry point. Bare icon (no chip/background), slow
            // continuous rotation to read as "interactive". Opens a half-sheet
            // placeholder until the actual tutorial videos are wired up.
            Button {
                AppHaptics.lightImpact()
                isTutorialPresented = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.72) : Color.primary.opacity(0.55))
                    .rotationEffect(.degrees(helpIconRotation))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Open tutorial"))

            Button {
                AppHaptics.selection()
                isCalendarPresented = true
            } label: {
                Text(dateTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.96) : Color.primary.opacity(0.80))
            }
            .buttonStyle(LiquidGlassCapsuleButtonStyle())
            .accessibilityLabel(Text("Select date"))
        }
        .padding(.horizontal, 10)
        .sheet(isPresented: $isTutorialPresented) {
            TutorialPlaceholderSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            startHelpIconRotationIfAllowed()
        }
        .onChange(of: reduceMotion) { _, newValue in
            if newValue {
                withAnimation(.none) { helpIconRotation = 0 }
            } else {
                startHelpIconRotationIfAllowed()
            }
        }
    }

    private func startHelpIconRotationIfAllowed() {
        guard !reduceMotion else { return }
        // Reset to 0 first so the animation always starts from a known state
        // (avoids cumulative drift on re-appear).
        helpIconRotation = 0
        withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
            helpIconRotation = 360
        }
    }
}

private struct TutorialPlaceholderSheet: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer().frame(height: 20)

            ZStack {
                Circle()
                    .fill(Color(red: 1.00, green: 0.78, blue: 0.33).opacity(0.18))
                    .frame(width: 88, height: 88)
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.20))
            }

            VStack(spacing: 8) {
                Text("Tutorial coming soon")
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Quick walkthroughs of how to log meals, scan barcodes, and track your goals — coming in a future build.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
