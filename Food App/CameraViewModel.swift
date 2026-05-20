import AVFoundation
import UIKit
import Combine

// MARK: - Camera State Types

enum CameraState: Equatable {
    case initializing
    case ready
    case simulatorPreview
    case capturing
    case reviewingPhoto(UIImage)
    case error(String)

    static func == (lhs: CameraState, rhs: CameraState) -> Bool {
        switch (lhs, rhs) {
        case (.initializing, .initializing),
             (.ready, .ready),
             (.simulatorPreview, .simulatorPreview),
             (.capturing, .capturing):
            return true
        case (.reviewingPhoto(let a), .reviewingPhoto(let b)):
            return a === b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

enum CameraFlashMode: String, CaseIterable {
    case auto
    case on
    case off

    var icon: String {
        switch self {
        case .auto: return "bolt.badge.automatic.fill"
        case .on:   return "bolt.fill"
        case .off:  return "bolt.slash.fill"
        }
    }

    var avFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .auto: return .auto
        case .on:   return .on
        case .off:  return .off
        }
    }

    var next: CameraFlashMode {
        switch self {
        case .auto: return .on
        case .on:   return .off
        case .off:  return .auto
        }
    }
}

enum CameraFacing {
    case back
    case front

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .back:  return .back
        case .front: return .front
        }
    }

    var toggled: CameraFacing {
        self == .back ? .front : .back
    }
}

// MARK: - CameraViewModel

@MainActor
final class CameraViewModel: ObservableObject {

    // MARK: Published State

    @Published var cameraState: CameraState = .initializing
    @Published var flashMode: CameraFlashMode = .auto
    @Published var cameraFacing: CameraFacing = .back
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var showPermissionDeniedAlert = false
    @Published private(set) var capturedImage: UIImage?
    /// V3.1 Phase 2: live barcode the camera is currently seeing. Drives the
    /// "Barcode detected — tap to capture" pill in the viewfinder.
    /// Republished from CameraService.onBarcodeStateChanged so SwiftUI views
    /// observing this view model react without subscribing to the service
    /// directly.
    @Published private(set) var detectedBarcode: DetectedBarcode?

    // MARK: Callbacks

    var onImageCaptured: ((UIImage) -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: Service

    let cameraService: CameraService

    // MARK: Private

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)
    private var baseZoomFactor: CGFloat = 1.0

    // MARK: Init

    init(cameraService: CameraService) {
        self.cameraService = cameraService
        // Republish live barcode detection from the service. Callback fires
        // on MainActor (see CameraService.publishBarcodeDetection) so direct
        // @Published mutation is safe.
        cameraService.onBarcodeStateChanged = { [weak self] detection in
            self?.detectedBarcode = detection
        }
    }

    // MARK: - Lifecycle

    func initialize() async {
        cameraState = .initializing

        cameraService.checkPermission()

        switch cameraService.permissionStatus {
        case .notDetermined:
            let status = await cameraService.requestPermission()
            if status != .authorized {
                showPermissionDeniedAlert = true
                cameraState = .error("Camera access is required to take food photos.")
                return
            }
        case .authorized:
            break
        case .denied, .restricted:
            showPermissionDeniedAlert = true
            cameraState = .error("Camera access is required to take food photos.")
            return
        }

        do {
            try cameraService.configureSession(position: cameraFacing.avPosition)
            cameraService.startSession()
            cameraState = .ready
        } catch {
            if case CameraServiceError.cameraUnavailable = error {
                cameraState = .simulatorPreview
            } else {
                cameraState = .error(error.localizedDescription)
            }
        }
    }

    func tearDown() {
        cameraService.stopSession()
    }

    // MARK: - Capture

    func capturePhoto() async {
        guard cameraState == .ready else { return }

        cameraState = .capturing
        hapticFeedback.prepare()
        hapticFeedback.impactOccurred()

        do {
            let image = try await cameraService.capturePhoto()
            capturedImage = image
            cameraState = .reviewingPhoto(image)
        } catch {
            cameraState = .error(error.localizedDescription)
        }
    }

#if targetEnvironment(simulator)
    /// V3.1 hotfix v3 (2026-05-20): simulator-only fake capture so we can
    /// exercise the camera → review → drawer transition without needing a
    /// real device + TestFlight upload. Loads a bundled food photo (which
    /// the backend parses end-to-end like any real capture) and jumps to
    /// the same `.reviewingPhoto(image)` state the real camera lands in.
    /// Triggered from CameraView's capture button when cameraState is
    /// `.simulatorPreview`.
    func captureSimulatedPhoto() {
        guard cameraState == .simulatorPreview else { return }
        // Try the canned food demo asset first, then fall back to the
        // onboarding food photos so the simulator path always finds an
        // image to capture even if assets get renamed.
        let candidates = ["food_photo_demo", "IntroFood1", "IntroFood2"]
        let image = candidates
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
        guard let image else {
            cameraState = .error("Simulator capture failed: no bundled test image found.")
            return
        }
        AppHaptics.mediumImpact()
        capturedImage = image
        cameraState = .reviewingPhoto(image)
    }
#endif

    func acceptPhoto() {
        guard let image = capturedImage else { return }
        AppHaptics.mediumImpact()
        // V3.1 hotfix v3 (2026-05-20): do NOT call onDismiss() here. The
        // host (MainLoggingShellBody) presents the analysis sheet NESTED
        // inside the camera fullScreenCover so it can slide up over the
        // captured-photo review without waiting on a cover dismiss. If we
        // dismiss the cover here, SwiftUI tears the nested sheet down with
        // the cover before iOS can finish animating it up — the user ends
        // up staring at the (slowly-dismissing) camera review for several
        // seconds while the cover + AVCaptureSession teardown plays out,
        // and the drawer only appears after both finish.
        //
        // The host dismisses the cover from the sheet's onDismiss / from
        // handleDrawerLogIt / from onDiscard once the user is done with the
        // analysis drawer. The "X" button on CameraTopBar still calls the
        // Environment dismiss() directly for users who want to back out
        // before tapping Use Photo.
        onImageCaptured?(image)
    }

    func retakePhoto() {
        AppHaptics.lightImpact()
        capturedImage = nil
        cameraState = .ready
        cameraService.startSession()
    }

    // MARK: - Controls

    func toggleFlash() {
        flashMode = flashMode.next
        cameraService.setFlashMode(flashMode.avFlashMode)
        AppHaptics.selection()
    }

    func toggleCamera() {
        cameraFacing = cameraFacing.toggled
        do {
            try cameraService.switchCamera()
            AppHaptics.lightImpact()
        } catch {
            // Switching failed, revert
            cameraFacing = cameraFacing.toggled
            AppHaptics.rigidImpact(intensity: 0.45)
        }
    }

    func handlePinchZoomBegan() {
        baseZoomFactor = currentZoomFactor
    }

    func handlePinchZoomChanged(_ scale: CGFloat) {
        let newFactor = baseZoomFactor * scale
        let clamped = min(max(newFactor, 1.0), 10.0)
        currentZoomFactor = clamped
        cameraService.setZoomFactor(clamped)
    }

    func handleTapToFocus(at point: CGPoint, in bounds: CGSize) {
        cameraService.setFocusPoint(point, in: bounds)
        AppHaptics.lightImpact(intensity: 0.7)
    }
}
