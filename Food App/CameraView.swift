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
    /// V3.1 Phase 3: one-time tip shown on first camera open. Initialized
    /// from UserDefaults so subsequent opens don't reshow it.
    @State private var showFirstLaunchTip = CameraFirstLaunchTip.shouldShow

    // Callbacks
    /// P0 fix (2026-05-20): second arg is the live-viewfinder barcode
    /// snapshotted at the exact moment of capture, or nil if the
    /// viewfinder didn't see one. Host uses it to route to the barcode
    /// lane directly instead of paying the VNDetectBarcodesRequest tax
    /// on the full-res capture (which was timing out in production and
    /// silently falling back to the vision lane).
    private let onImageCaptured: (UIImage, DetectedBarcode?) -> Void
    private let onOpenPhotoLibrary: (() -> Void)?

    init(
        onImageCaptured: @escaping (UIImage, DetectedBarcode?) -> Void,
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
                    CameraTopBar(onClose: {
                        AppHaptics.lightImpact()
                        dismiss()
                    })
                        .padding(.top, safeInsets.top + 6)

                    // V3.1 Phase 2: live detection pill — only renders when a
                    // barcode is currently in the viewfinder. Drives intuition
                    // that the upcoming capture will go through the fast
                    // barcode lane.
                    BarcodeDetectionPill(detection: viewModel.detectedBarcode)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    // V3.1 Phase 3: informational icon row that communicates
                    // "we auto-detect three kinds of input" without using
                    // intrusive text.
                    // 2026-05-23: dropped the bottom padding + flex spacer
                    // so the chip sits right above the stage rectangle.
                    // Was reading as visually orphaned between the top
                    // bar and the stage.
                    CameraModeIconRow()
                        .padding(.bottom, 8)

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
                        // V3.1 hotfix v3 (2026-05-20): enable the capture
                        // button in simulator mode too so the camera-to-
                        // drawer transition is testable without a real
                        // device + TestFlight round-trip. The simulator
                        // path uses a bundled food photo (handled in
                        // CameraViewModel.captureSimulatedPhoto) so the
                        // backend parse still runs end-to-end.
                        captureEnabled: true,
                        onCapture: {
                            showCaptureFlash = true
                            if viewModel.cameraState == .simulatorPreview {
#if targetEnvironment(simulator)
                                viewModel.captureSimulatedPhoto()
#endif
                            } else {
                                Task { await viewModel.capturePhoto() }
                            }
                        },
                        onOpenLibrary: {
                            AppHaptics.lightImpact()
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

                // V3.1 Phase 3: first-launch tip overlay. Z-stacked above
                // everything else so it's the user's first interaction.
                if showFirstLaunchTip {
                    CameraFirstLaunchTip(isPresented: $showFirstLaunchTip)
                        .zIndex(100)
                }
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
                AppHaptics.lightImpact()
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

            Button {
                AppHaptics.lightImpact()
                dismiss()
            } label: {
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
