import SwiftUI
import TipKit
import UIKit

struct MainLoggingBottomDock: View {
    let shouldShowSyncExceptionPill: Bool
    let syncStatusTitle: String
    let syncStatusExplanation: String
    let currentFoodLogStreak: Int?
    let isLoadingFoodLogStreak: Bool
    let isKeyboardVisible: Bool
    @Binding var isSyncInfoPresented: Bool
    @Binding var isStreakDrawerPresented: Bool

    /// Tutorial tips for the photo + mic buttons. Initialised here so each
    /// dock instance shares the same Tip identity (TipKit dedupes by id
    /// internally, but keeping a single instance avoids any ambiguity).
    private let logWithPhotoTip = LogWithPhotoTip()
    private let logWithVoiceTip = LogWithVoiceTip()

    var body: some View {
        VStack(spacing: 10) {
            if shouldShowSyncExceptionPill {
                syncStatusPill
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            ZStack {
                HStack(spacing: 0) {
                    HStack(spacing: 12) {
                        bottomDockButton(
                            systemImage: "camera.fill",
                            color: Color(red: 0.380, green: 0.333, blue: 0.961),
                            accessibilityLabel: "Open camera"
                        ) {
                            // Donate first so TipKit retires the photo tip
                            // on the next render — the popover is anchored
                            // to this same button.
                            Task { await TutorialEvents.photoButtonTapped.donate() }
                            NotificationCenter.default.post(name: .openCameraFromTabBar, object: nil)
                        }
                        .popoverTip(logWithPhotoTip, arrowEdge: .bottom)

                        bottomDockButton(
                            systemImage: "mic.fill",
                            color: Color(red: 0.796, green: 0.188, blue: 0.878),
                            accessibilityLabel: "Voice input"
                        ) {
                            Task { await TutorialEvents.micButtonTapped.donate() }
                            NotificationCenter.default.post(name: .openVoiceFromTabBar, object: nil)
                        }
                        .popoverTip(logWithVoiceTip, arrowEdge: .bottom)
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 12) {
                        streakDockIndicator

                        bottomDockButton(
                            systemImage: "flame.fill",
                            color: .orange,
                            accessibilityLabel: "Open nutrition summary"
                        ) {
                            NotificationCenter.default.post(name: .openNutritionSummaryFromTabBar, object: nil)
                        }
                    }
                }

                if isKeyboardVisible {
                    bottomDockButton(
                        systemImage: "keyboard.chevron.compact.down",
                        color: .secondary,
                        accessibilityLabel: "Dismiss keyboard"
                    ) {
                        NotificationCenter.default.post(name: .dismissKeyboardFromTabBar, object: nil)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var syncStatusPill: some View {
        Button {
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
            isStreakDrawerPresented = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 60, height: 60)

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
            // Glass background lives INSIDE the label so the Button stays
            // the outermost interactive layer. Previously the glassyBackground
            // was applied AFTER buttonStyle(.plain), which on iOS 26 meant
            // glassEffect(.interactive()) wrapped the button and absorbed
            // the first tap for its own press feedback before the button
            // could see it — hence the 2-3 tap repro.
            .glassyBackground(in: .circle)
            // Without contentShape the badge's regularMaterial Circle could
            // intercept hits on the bottom-right corner of the button area.
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Open \(currentFoodLogStreak ?? 0)-day food streak"))
    }

    private func bottomDockButton(
        systemImage: String,
        color: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 60, height: 60)
        }
        .glassyBackground(in: .circle)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

struct MainLoggingTopHeaderStrip: View {
    let firstName: String?
    let dateTitle: String
    let colorScheme: ColorScheme
    @Binding var isProfilePresented: Bool
    @Binding var isCalendarPresented: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                isProfilePresented = true
            } label: {
                HomeGreetingChip(firstName: firstName)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Open profile"))

            Spacer(minLength: 0)

            Button {
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
    }
}
