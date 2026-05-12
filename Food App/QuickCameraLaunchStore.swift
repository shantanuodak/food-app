import Foundation

enum QuickCameraLaunchStore {
    private static let launchRequestedKey = "quickCamera.launchRequested.v1"
    private static let cameraLaunchRequestedKey = "camera.launchRequested.v1"
    private static let voiceLaunchRequestedKey = "quickVoice.launchRequested.v1"

    static func requestLaunch() {
        UserDefaults.standard.set(true, forKey: launchRequestedKey)
        NotificationCenter.default.post(name: .openQuickCameraFromSystem, object: nil)
    }

    static func requestVoiceLaunch() {
        UserDefaults.standard.set(true, forKey: voiceLaunchRequestedKey)
        NotificationCenter.default.post(name: .openVoiceFromTabBar, object: nil)
    }

    static func requestCameraLaunch() {
        UserDefaults.standard.set(true, forKey: cameraLaunchRequestedKey)
        NotificationCenter.default.post(name: .openCameraFromTabBar, object: nil)
    }

    static func consumeLaunchRequest() -> Bool {
        let requested = UserDefaults.standard.bool(forKey: launchRequestedKey)
        if requested {
            UserDefaults.standard.set(false, forKey: launchRequestedKey)
        }
        return requested
    }

    static func consumeVoiceLaunchRequest() -> Bool {
        let requested = UserDefaults.standard.bool(forKey: voiceLaunchRequestedKey)
        if requested {
            UserDefaults.standard.set(false, forKey: voiceLaunchRequestedKey)
        }
        return requested
    }

    static func consumeCameraLaunchRequest() -> Bool {
        let requested = UserDefaults.standard.bool(forKey: cameraLaunchRequestedKey)
        if requested {
            UserDefaults.standard.set(false, forKey: cameraLaunchRequestedKey)
        }
        return requested
    }

    static func handle(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "foodapp" else {
            return false
        }

        let pathComponents = url.pathComponents.map { $0.lowercased() }
        let host = url.host?.lowercased()
        let isVoiceURL =
            host == "voice" ||
            pathComponents.contains("voice")
        if isVoiceURL {
            requestVoiceLaunch()
            return true
        }

        let isQuickCameraURL =
            host == "quick-camera" ||
            pathComponents.contains("quick-camera")
        if isQuickCameraURL {
            requestLaunch()
            return true
        }

        let isCameraURL =
            host == "camera" ||
            pathComponents.contains("camera")

        guard isCameraURL else {
            return false
        }

        requestCameraLaunch()
        return true
    }
}
