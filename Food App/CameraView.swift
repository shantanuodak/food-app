import SwiftUI
import AVFoundation

// MARK: - CameraView (Full-Screen Camera)

struct CameraView: View {
    @StateObject private var viewModel: CameraViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var focusPoint: CGPoint?
    @State private var focusRingID = UUID()
    @State private var showCaptureFlash = false
    @State private var showPhotoLibrary = false

    // Callbacks
    private let onImageCaptured: (UIImage) -> Void
    private let onOpenPhotoLibrary: (() -> Void)?

    init(
        onImageCaptured: @escaping (UIImage) -> Void,
        onOpenPhotoLibrary: (() -> Void)? = nil
    ) {
        self.onImageCaptured = onImageCaptured
        self.onOpenPhotoLibrary = onOpenPhotoLibrary
        let service = CameraService()
        let vm = CameraViewModel(cameraService: service)
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.cameraState {
            case .initializing:
                cameraLoadingView

            case .ready, .capturing, .simulatorPreview:
                cameraPreviewBody

            case .reviewingPhoto(let image):
                CameraReviewOverlay(
                    image: image,
                    onRetake: { viewModel.retakePhoto() },
                    onUsePhoto: {
                        viewModel.onImageCaptured = onImageCaptured
                        viewModel.acceptPhoto()
                    }
                )

            case .error:
                if viewModel.showPermissionDeniedAlert {
                    CameraPermissionDeniedView(onDismiss: { dismiss() })
                } else {
                    cameraErrorView
                }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            viewModel.onDismiss = { dismiss() }
            Task { await viewModel.initialize() }
        }
        .onDisappear {
            viewModel.tearDown()
        }
    }

    // MARK: - Camera Preview Body

    private var cameraPreviewBody: some View {
        GeometryReader { proxy in
            let safeInsets = proxy.safeAreaInsets
            let stageWidth = min(proxy.size.width - 36, 350)
            let proposedHeight = proxy.size.height - safeInsets.top - safeInsets.bottom - 214
            let stageHeight = max(420, min(proposedHeight, 590))

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    CameraTopBar(onClose: { dismiss() })
                        .padding(.top, safeInsets.top + 6)

                    Spacer(minLength: 18)

                    ZStack {
                        stagePreviewSurface(width: stageWidth, height: stageHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .gesture(tapToFocusGesture(in: CGSize(width: stageWidth, height: stageHeight)))
                            .gesture(pinchToZoomGesture)

                        CameraPreviewStageOverlay(
                            flashMode: viewModel.flashMode,
                            onFlashToggle: { viewModel.toggleFlash() },
                            onFlipCamera: { viewModel.toggleCamera() }
                        )
                        .frame(width: stageWidth, height: stageHeight)

                        if let point = focusPoint {
                            FocusRingView(position: point)
                                .id(focusRingID)
                        }
                    }
                    .frame(width: stageWidth, height: stageHeight)
                    .shadow(color: Color.black.opacity(0.45), radius: 30, y: 18)

                    Spacer(minLength: 28)

                    CameraBottomBar(
                        isCapturing: viewModel.cameraState == .capturing,
                        captureEnabled: viewModel.cameraState != .simulatorPreview,
                        onCapture: {
                            guard viewModel.cameraState != .simulatorPreview else { return }
                            showCaptureFlash = true
                            Task { await viewModel.capturePhoto() }
                        },
                        onOpenLibrary: {
                            if let handler = onOpenPhotoLibrary {
                                dismiss()
                                handler()
                            }
                        }
                    )
                    .padding(.horizontal, 26)
                    .padding(.bottom, max(safeInsets.bottom, 12) + 18)
                }

                CaptureFlashOverlay(isVisible: $showCaptureFlash)
            }
        }
    }

    @ViewBuilder
    private func stagePreviewSurface(width: CGFloat, height: CGFloat) -> some View {
        if viewModel.cameraState == .simulatorPreview {
            CameraPreviewMockSurface()
                .frame(width: width, height: height)
        } else {
            CameraPreviewView(session: viewModel.cameraService.session)
                .frame(width: width, height: height)
        }
    }

    // MARK: - Loading View

    private var cameraLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
            Text("Starting camera...")
                .font(.system(size: 15))
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Error View

    private var cameraErrorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)

            if case .error(let message) = viewModel.cameraState {
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task { await viewModel.initialize() }
            } label: {
                Text("Retry")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.top, 8)

            Button { dismiss() } label: {
                Text("Close")
                    .font(.system(size: 15))
                    .foregroundStyle(.gray)
            }
        }
    }

    // MARK: - Gestures

    private func tapToFocusGesture(in stageSize: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let point = value.location
                focusPoint = point
                focusRingID = UUID()
                viewModel.handleTapToFocus(
                    at: point,
                    in: stageSize
                )
            }
    }

    private var pinchToZoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if value.magnification == 1.0 {
                    viewModel.handlePinchZoomBegan()
                }
                viewModel.handlePinchZoomChanged(value.magnification)
            }
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Session is set once in makeUIView
    }
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
