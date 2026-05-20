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

    nonisolated private let sessionQueue = DispatchQueue(label: "com.foodapp.camera.session")

    // MARK: Photo Capture

    private var photoContinuation: CheckedContinuation<UIImage, Error>?
    private var flashMode: AVCaptureDevice.FlashMode = .auto

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
        // Prefer multi-camera virtual devices so iOS can auto-switch lenses
        // (especially to the ultra-wide for macro on iPhone 13 Pro+).
        //   builtInTripleCamera   — iPhone Pro models (wide + ultra-wide + tele)
        //   builtInDualWideCamera — non-Pro recent iPhones (wide + ultra-wide)
        //   builtInWideAngleCamera — fallback for older iPhones / front camera
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: position) {
            return triple
        }
        if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: position) {
            return dualWide
        }
        if let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return wide
        }
        return AVCaptureDevice.default(for: .video)
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
