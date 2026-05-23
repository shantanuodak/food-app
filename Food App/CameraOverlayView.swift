import SwiftUI
import AVFoundation

private enum CameraOverlayTokens {
    static let stageCornerRadius: CGFloat = 34
    static let stageBorder = Color.white.opacity(0.78)
    static let stageInnerGlow = Color.white.opacity(0.08)
    static let controlSurface = Color.black.opacity(0.42)
    static let controlStroke = Color.white.opacity(0.11)
    static let scanLineCore = Color.white.opacity(0.94)
    static let scanLineGlow = Color(red: 1.0, green: 0.53, blue: 0.16)
    static let helperText = Color.white.opacity(0.72)
}

struct CameraTopBar: View {
    let onClose: () -> Void

    var body: some View {
        HStack {
            AppCloseButton(action: onClose, variant: .onImage, visualSize: 44, hitSize: 44)

            Spacer()

            Text("Food Camera")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.76))

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 18)
    }
}

struct CameraPreviewStageOverlay: View {
    let flashMode: CameraFlashMode
    let onFlashToggle: () -> Void
    let onFlipCamera: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CameraOverlayTokens.stageCornerRadius, style: .continuous)
                .stroke(CameraOverlayTokens.stageBorder, lineWidth: 1.5)
                .background(
                    RoundedRectangle(cornerRadius: CameraOverlayTokens.stageCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    CameraOverlayTokens.stageInnerGlow,
                                    Color.clear,
                                    Color.black.opacity(0.16)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )

            scanSurfaceShade

            // 2026-05-23: scanning line (bobbing capsule) and viewfinder
            // icon on the right of the helper text both removed. The line
            // was purely decorative and the icon was a non-interactive
            // affordance that read as tappable but did nothing.

            VStack {
                topHint

                Spacer()

                HStack(spacing: 14) {
                    CameraStageUtilityButton(
                        systemImage: flashMode.icon,
                        accent: flashMode == .off ? Color.white.opacity(0.78) : Color(red: 1.0, green: 0.77, blue: 0.28),
                        action: onFlashToggle
                    )

                    CameraStageUtilityButton(
                        systemImage: "camera.rotate.fill",
                        accent: Color.white.opacity(0.86),
                        action: onFlipCamera
                    )
                }
                .padding(.bottom, 22)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .clipShape(RoundedRectangle(cornerRadius: CameraOverlayTokens.stageCornerRadius, style: .continuous))
        .allowsHitTesting(true)
    }

    private var scanSurfaceShade: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.08),
                Color.clear,
                Color.black.opacity(0.22)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var topHint: some View {
        // 2026-05-23: dropped the trailing viewfinder icon. The icon was
        // sized like a tappable control (38pt circle with stroke) but had
        // no action attached, which read as "button that doesn't work".
        // Helper text stack now spans the full width.
        VStack(alignment: .leading, spacing: 4) {
            Text("Align your meal in frame")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.96))

            Text("Snap once the food sits inside the scan field.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(CameraOverlayTokens.helperText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CameraStageUtilityButton: View {
    let systemImage: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        // 2026-05-23: visual circle shrunk from 74→52pt. The icon still
        // sits in a contentShape that meets Apple's 44pt minimum, so the
        // tap target is preserved. Smaller circles read as utilities
        // rather than competing with the capture button.
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 52, height: 52)
                .background(CameraOverlayTokens.controlSurface, in: Circle())
                .overlay(Circle().stroke(CameraOverlayTokens.controlStroke, lineWidth: 1))
                .contentShape(Circle().inset(by: -4))
        }
        .buttonStyle(.plain)
    }
}

struct CameraCaptureButton: View {
    let isCapturing: Bool
    let isEnabled: Bool
    let onCapture: () -> Void

    @GestureState private var isPressed = false

    var body: some View {
        Button(action: onCapture) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 92, height: 92)

                Circle()
                    .strokeBorder(Color.white.opacity(0.92), lineWidth: 3)
                    .frame(width: 86, height: 86)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white,
                                Color(red: 0.96, green: 0.96, blue: 0.96)
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 34
                        )
                    )
                    .frame(width: 70, height: 70)
                    .scaleEffect(isPressed ? 0.88 : 1.0)
                    .animation(.easeInOut(duration: 0.10), value: isPressed)
            }
            .opacity((isCapturing || !isEnabled) ? 0.55 : 1.0)
        }
        .disabled(isCapturing || !isEnabled)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: .infinity)
                .updating($isPressed) { _, state, _ in
                    state = true
                }
        )
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Capture photo"))
    }
}

struct CameraBottomBar: View {
    let isCapturing: Bool
    let captureEnabled: Bool
    let onCapture: () -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        // 2026-05-23: library button shrunk 72→52pt to match the new
        // flash / flip sizes inside the stage. Capture button stays at
        // 92pt — it's the primary action and should anchor the bar.
        HStack(alignment: .center) {
            Button(action: onOpenLibrary) {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(width: 52, height: 52)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                    .contentShape(Circle().inset(by: -4))
            }
            .buttonStyle(.plain)

            Spacer()

            CameraCaptureButton(isCapturing: isCapturing, isEnabled: captureEnabled, onCapture: onCapture)

            Spacer()

            // Symmetric spacer keeps the capture button centered.
            Color.clear
                .frame(width: 52, height: 52)
        }
    }
}

struct CameraPreviewMockSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.10, blue: 0.12),
                    Color(red: 0.14, green: 0.15, blue: 0.18),
                    Color(red: 0.10, green: 0.11, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 130, height: 84)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "camera.aperture")
                                .font(.system(size: 26, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.86))
                            Text("Simulator Preview")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.88))
                        }
                    )

                Text("Live camera feed is unavailable in Simulator.\nThis mock surface lets us QA the shell layout.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.60))
                    .padding(.horizontal, 34)
            }

            mockPlateShapes
        }
    }

    private var mockPlateShapes: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 170, height: 170)
                .offset(x: 86, y: -132)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .frame(width: 220, height: 120)
                .rotationEffect(.degrees(-14))
                .offset(x: -94, y: 118)

            Circle()
                .fill(Color(red: 1.0, green: 0.54, blue: 0.16).opacity(0.10))
                .frame(width: 124, height: 124)
                .offset(x: -112, y: -156)
        }
        .blur(radius: 0.2)
    }
}

struct CameraReviewOverlay: View {
    let image: UIImage
    let onRetake: () -> Void
    let onUsePhoto: () -> Void

    var body: some View {
        // V3.1 hotfix (2026-05-20): the previous layout used a bare ZStack with
        // .aspectRatio(.fill) + .ignoresSafeArea() on the image, which on iOS
        // 18 lets the image's intrinsic width propagate to siblings and
        // overflows the HStack (the "Use Photo" capsule was getting clipped
        // off the right edge of the device). Wrapping in GeometryReader and
        // explicitly framing everything to the reader's width keeps the
        // image full-bleed while constraining the button row to the device.
        GeometryReader { proxy in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [Color.black.opacity(0.34), Color.clear, Color.black.opacity(0.60)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack {
                    Spacer()

                    HStack(spacing: 14) {
                        Button(action: {
                            AppHaptics.lightImpact()
                            onRetake()
                        }) {
                            Text("Retake")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.white.opacity(0.14), in: Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)

                        Button(action: {
                            AppHaptics.mediumImpact()
                            onUsePhoto()
                        }) {
                            Text("Use Photo")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.white, in: Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

struct FocusRingView: View {
    let position: CGPoint
    @State private var scale: CGFloat = 1.35
    @State private var opacity: Double = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(0.92), lineWidth: 2)
            .frame(width: 74, height: 74)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(red: 1.0, green: 0.56, blue: 0.18).opacity(0.42), lineWidth: 6)
                    .blur(radius: 10)
            )
            .scaleEffect(scale)
            .opacity(opacity)
            .position(position)
            .onAppear {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
                    scale = 1.0
                }
                withAnimation(.easeOut(duration: 0.65).delay(0.75)) {
                    opacity = 0
                }
            }
    }
}

struct CameraPermissionDeniedView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.gray)

                Text("Camera Access Required")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)

                Text("To take food photos, please allow camera access in your device settings.")
                    .font(.system(size: 15))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    AppHaptics.lightImpact()
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.380, green: 0.333, blue: 0.961), in: Capsule())
                }
                .padding(.top, 8)

                Button(action: {
                    AppHaptics.lightImpact()
                    onDismiss()
                }) {
                    Text("Go Back")
                        .font(.system(size: 15))
                        .foregroundStyle(.gray)
                }
                .padding(.top, 4)
            }
        }
    }
}

struct CaptureFlashOverlay: View {
    @Binding var isVisible: Bool

    var body: some View {
        Color.white
            .ignoresSafeArea()
            .opacity(isVisible ? 0.56 : 0)
            .animation(.easeOut(duration: 0.15), value: isVisible)
            .allowsHitTesting(false)
            .onChange(of: isVisible) { _, newValue in
                if newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isVisible = false
                    }
                }
            }
    }
}
