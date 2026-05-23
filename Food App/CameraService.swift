import AVFoundation
import UIKit
import Combine

// MARK: - Error & Permission Types

enum CameraServiceError: LocalizedError {
    case cameraUnavailable
    case permissionDenied
    case permissionRestricted
    case configurationFailed(String)
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "Camera is unavailable on this device."
        case .permissionDenied:
            return "Camera access was denied. Please enable it in Settings."
        case .permissionRestricted:
            return "Camera access is restricted on this device."
        case .configurationFailed(let reason):
            return "Camera setup failed: \(reason)"
        case .captureFailed(let reason):
            return "Photo capture failed: \(reason)"
        }
    }
}

enum CameraPermissionStatus {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// A barcode the camera is currently seeing in the viewfinder, surfaced for
/// the live "Barcode detected" UI hint. Distinct from a captured-photo
/// barcode (which is handled post-capture by ImageVisionPipeline).
struct DetectedBarcode: Equatable {
    let payload: String
    let symbology: String
}

// MARK: - CameraService

@MainActor
final class CameraService: NSObject, ObservableObject {

    // MARK: Published State

    @Published private(set) var isSessionRunning = false
    @Published private(set) var permissionStatus: CameraPermissionStatus = .notDetermined
    @Published private(set) var currentCameraPosition: AVCaptureDevice.Position = .back

    // MARK: AVFoundation Objects

    /// `nonisolated` because the AVFoundation objects are thread-safe by
    /// design and need to be accessed from `sessionQueue` (a background
    /// queue) for performance — Apple's own AVFoundation samples follow
    /// this pattern. Without `nonisolated`, the `@MainActor` class
    /// inheritance forces these properties onto the main actor and
    /// touching them from `sessionQueue.async { [weak self] in ... }`
    /// produces a Swift 6 "Sendable closure" warning that becomes an
    /// error under strict concurrency.
    nonisolated private let captureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    nonisolated private let photoOutput = AVCapturePhotoOutput()
    nonisolated private let metadataOutput = AVCaptureMetadataOutput()

    nonisolated private let sessionQueue = DispatchQueue(label: "com.foodapp.camera.session")
    nonisolated private let metadataQueue = DispatchQueue(label: "com.foodapp.camera.metadata")

    // MARK: Photo Capture

    private var photoContinuation: CheckedContinuation<UIImage, Error>?
    private var flashMode: AVCaptureDevice.FlashMode = .auto

    // MARK: Live Barcode Detection

    /// Set by CameraViewModel during init. Fires on MainActor when the live
    /// viewfinder starts/stops seeing a barcode. Used to drive the
    /// "Barcode detected — tap to capture" hint pill.
    var onBarcodeStateChanged: ((DetectedBarcode?) -> Void)?
    private var lastDetectedBarcode: DetectedBarcode?
    private var clearBarcodeTask: Task<Void, Never>?

    // MARK: - Public API

    nonisolated var session: AVCaptureSession { captureSession }

    func checkPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined: permissionStatus = .notDetermined
        case .authorized:    permissionStatus = .authorized
        case .denied:        permissionStatus = .denied
        case .restricted:    permissionStatus = .restricted
        @unknown default:    permissionStatus = .denied
        }
    }

    func requestPermission() async -> CameraPermissionStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        permissionStatus = granted ? .authorized : .denied
        return permissionStatus
    }

    func configureSession(position: AVCaptureDevice.Position = .back) throws {
        #if targetEnvironment(simulator)
        throw CameraServiceError.cameraUnavailable
        #else
        sessionQueue.sync {
            captureSession.beginConfiguration()
            defer { captureSession.commitConfiguration() }

            captureSession.sessionPreset = .photo

            // Remove existing input
            if let existingInput = videoDeviceInput {
                captureSession.removeInput(existingInput)
            }

            // Add video input
            guard let device = bestDevice(for: position) else {
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard captureSession.canAddInput(input) else { return }
                captureSession.addInput(input)
                videoDeviceInput = input
                currentCameraPosition = position
            } catch {
                return
            }

            // Add photo output (if not already added)
            if !captureSession.outputs.contains(photoOutput) {
                guard captureSession.canAddOutput(photoOutput) else { return }
                captureSession.addOutput(photoOutput)
            }

            photoOutput.maxPhotoQualityPrioritization = .quality

            // V3.1 Phase 2: live barcode detection via metadata output so the
            // viewfinder can show "Barcode detected — tap to capture" before
            // the user actually shoots. This is near-zero cost (system-level
            // detection running on the GPU; no per-frame work for us).
            if !captureSession.outputs.contains(metadataOutput) {
                if captureSession.canAddOutput(metadataOutput) {
                    captureSession.addOutput(metadataOutput)
                    metadataOutput.metadataObjectTypes = [.ean13, .ean8, .upce, .code128]
                    metadataOutput.setMetadataObjectsDelegate(self, queue: metadataQueue)
                }
            }

            // V3.1 Phase 1: continuous AF/AE so the camera is always trying to be
            // sharp before the user taps shutter, and enable macro auto-engage on
            // iPhone 13 Pro+ (triple camera) / 11/12 Pro (dual wide) so close-up
            // food + barcode shots focus correctly without the user fiddling.
            // setFocusPoint() still overrides this temporarily on tap.
            try? configureContinuousFocusAndMacro(on: device)
        }
        #endif
    }

    /// Set continuous AF/AE on the active device and enable subject-area-change
    /// monitoring so the camera refocuses when the user moves the framing.
    /// Best-effort; failures are non-fatal.
    ///
    /// Macro auto-engage works without explicit code here because:
    ///   1. We select `.builtInTripleCamera` (or `.builtInDualWideCamera`)
    ///      in `bestDevice(for:)` when available.
    ///   2. Multi-camera virtual devices default to `.auto` constituent
    ///      switching, which engages the ultra-wide for macro distances
    ///      automatically on iPhone 13 Pro+.
    private func configureContinuousFocusAndMacro(on device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        // Re-engage AF when the framed scene changes substantially. Without
        // this the camera locks focus on the first thing it sees and doesn't
        // refocus when the user moves to a new subject (e.g., away from the
        // table to a barcode on a can).
        device.isSubjectAreaChangeMonitoringEnabled = true
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            Task { @MainActor in
                self.isSessionRunning = true
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            Task { @MainActor in
                self.isSessionRunning = false
            }
        }
    }

    func switchCamera() throws {
        let newPosition: AVCaptureDevice.Position = (currentCameraPosition == .back) ? .front : .back
        try configureSession(position: newPosition)
    }

    func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        flashMode = mode
    }

    func setFocusPoint(_ point: CGPoint, in previewBounds: CGSize) {
        guard let device = videoDeviceInput?.device else { return }

        // Convert from view coordinates to camera coordinates (0...1)
        let focusPoint = CGPoint(
            x: point.y / previewBounds.height,
            y: 1.0 - (point.x / previewBounds.width)
        )

        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = focusPoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            // Focus adjustment failed silently
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }

        let clamped = min(max(factor, 1.0), device.maxAvailableVideoZoomFactor)

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            // Zoom adjustment failed silently
        }
    }

    func capturePhoto() async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            guard photoContinuation == nil else {
                continuation.resume(throwing: CameraServiceError.captureFailed("A capture is already in progress."))
                return
            }
            photoContinuation = continuation

            let settings = AVCapturePhotoSettings()
            if photoOutput.supportedFlashModes.contains(flashMode) {
                settings.flashMode = flashMode
            }
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Private Helpers

    private func bestDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Use the primary 1x wide-angle lens directly. Per user feedback on
        // 2026-05-22, the multi-camera virtual devices' auto-switch to the
        // ultra-wide constituent for close subjects looked like "the camera
        // is using the wide angle" even though it was technically the macro
        // lane on iPhone Pro models. Locking to .builtInWideAngleCamera
        // gives a predictable 1x field of view across all devices.
        //
        // Tradeoff: loses iOS auto-macro engage on iPhone 13 Pro+. Close-up
        // barcodes / labels may need the user to step back ~12-15cm. If
        // barcode parse rates drop noticeably we can revisit by exposing a
        // manual Macro toggle in the camera UI.
        if let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return wide
        }
        return AVCaptureDevice.default(for: .video)
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate (live barcode detection)

extension CameraService: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        // Take the first machine-readable code with a non-empty payload. If
        // multiple are in frame, we just pick one; the lane router will run
        // again on the captured photo and re-decide.
        guard
            let object = metadataObjects.first(where: { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue?.isEmpty == false }) as? AVMetadataMachineReadableCodeObject,
            let payload = object.stringValue,
            !payload.isEmpty
        else { return }

        let symbology = Self.symbologyName(object.type)
        let detection = DetectedBarcode(payload: payload, symbology: symbology)
        Task { @MainActor [weak self] in
            self?.publishBarcodeDetection(detection)
        }
    }

    /// Called on MainActor when a barcode lands in the viewfinder. Schedules
    /// a 1.2s auto-clear so the pill fades out when the user looks away.
    @MainActor
    private func publishBarcodeDetection(_ detection: DetectedBarcode) {
        if lastDetectedBarcode != detection {
            lastDetectedBarcode = detection
            onBarcodeStateChanged?(detection)
        }
        clearBarcodeTask?.cancel()
        clearBarcodeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if Task.isCancelled { return }
            self?.lastDetectedBarcode = nil
            self?.onBarcodeStateChanged?(nil)
        }
    }

    private nonisolated static func symbologyName(_ type: AVMetadataObject.ObjectType) -> String {
        switch type {
        case .ean13:   return "EAN-13"
        case .ean8:    return "EAN-8"
        case .upce:    return "UPC-E"
        case .code128: return "Code128"
        default:       return type.rawValue
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            defer { photoContinuation = nil }

            if let error {
                photoContinuation?.resume(throwing: CameraServiceError.captureFailed(error.localizedDescription))
                return
            }

            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                photoContinuation?.resume(throwing: CameraServiceError.captureFailed("Could not process the captured photo."))
                return
            }

            photoContinuation?.resume(returning: image)
        }
    }
}
