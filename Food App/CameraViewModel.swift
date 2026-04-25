import AVFoundation
import UIKit
import Combine

// MARK: - Camera State Types

enum CameraState: Equatable {
    case initializing
    case ready
    case capturing
    case reviewingPhoto(UIImage)
    case error(String)

    static func == (lhs: CameraState, rhs: CameraState) -> Bool {
        switch (lhs, rhs) {
        case (.initializing, .initializing),
             (.ready, .ready),
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
            cameraState = .error(error.localizedDescription)
        }
    }

    func tearDown() {
        cameraService.stopSession()
    }

    // MARK: - Capture

    func capturePhoto() async {
        guard cameraState == .ready else { return }

        cameraState = .capturing
        hapticFeedback.impactOccurred()

        do {
            let image = try await cameraService.capturePhoto()
            capturedImage = image
            cameraState = .reviewingPhoto(image)
        } catch {
            cameraState = .error(error.localizedDescription)
        }
    }

    func acceptPhoto() {
        guard let image = capturedImage else { return }
        onImageCaptured?(image)
        onDismiss?()
    }

    func retakePhoto() {
        capturedImage = nil
        cameraState = .ready
        cameraService.startSession()
    }

    // MARK: - Controls

    func toggleFlash() {
        flashMode = flashMode.next
        cameraService.setFlashMode(flashMode.avFlashMode)
    }

    func toggleCamera() {
        cameraFacing = cameraFacing.toggled
        do {
            try cameraService.switchCamera()
        } catch {
            // Switching failed, revert
            cameraFacing = cameraFacing.toggled
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
    }
}
