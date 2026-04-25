import SwiftUI
import AVFoundation

// MARK: - Camera Top Bar

struct CameraTopBar: View {
    let flashMode: CameraFlashMode
    let onClose: () -> Void
    let onFlashToggle: () -> Void

    var body: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            Button(action: onFlashToggle) {
                Image(systemName: flashMode.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(flashMode == .off ? .white : .yellow)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Capture Button

struct CameraCaptureButton: View {
    let isCapturing: Bool
    let onCapture: () -> Void

    @GestureState private var isPressed = false

    var body: some View {
        Button(action: onCapture) {
            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)

                // Inner filled circle
                Circle()
                    .fill(.white)
                    .frame(width: 64, height: 64)
                    .scaleEffect(isPressed ? 0.85 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isPressed)
            }
            .opacity(isCapturing ? 0.5 : 1.0)
        }
        .disabled(isCapturing)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: .infinity)
                .updating($isPressed) { _, state, _ in
                    state = true
                }
        )
    }
}

// MARK: - Camera Bottom Bar

struct CameraBottomBar: View {
    let onFlipCamera: () -> Void
    let isCapturing: Bool
    let onCapture: () -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            // Photo library
            Button(action: onOpenLibrary) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
            }

            Spacer()

            // Capture button
            CameraCaptureButton(isCapturing: isCapturing, onCapture: onCapture)

            Spacer()

            // Flip camera
            Button(action: onFlipCamera) {
                Image(systemName: "camera.rotate.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 20)
    }
}

// MARK: - Review Overlay

struct CameraReviewOverlay: View {
    let image: UIImage
    let onRetake: () -> Void
    let onUsePhoto: () -> Void

    var body: some View {
        ZStack {
            // Captured image
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()

            // Bottom controls
            VStack {
                Spacer()

                HStack(spacing: 40) {
                    Button(action: onRetake) {
                        Text("Retake")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    Button(action: onUsePhoto) {
                        Text("Use Photo")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(.white, in: Capsule())
                    }
                }
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Focus Ring

struct FocusRingView: View {
    let position: CGPoint
    @State private var scale: CGFloat = 1.5
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .strokeBorder(Color.yellow, lineWidth: 1.5)
            .frame(width: 70, height: 70)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(position)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    scale = 1.0
                }
                withAnimation(.easeOut(duration: 0.8).delay(0.8)) {
                    opacity = 0
                }
            }
    }
}

// MARK: - Permission Denied View

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

                Button(action: onDismiss) {
                    Text("Go Back")
                        .font(.system(size: 15))
                        .foregroundStyle(.gray)
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Capture Flash Overlay

struct CaptureFlashOverlay: View {
    @Binding var isVisible: Bool

    var body: some View {
        Color.white
            .ignoresSafeArea()
            .opacity(isVisible ? 0.6 : 0)
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
