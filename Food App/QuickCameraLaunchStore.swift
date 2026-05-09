import Foundation

enum QuickCameraLaunchStore {
    private static let launchRequestedKey = "quickCamera.launchRequested.v1"

    static func requestLaunch() {
        UserDefaults.standard.set(true, forKey: launchRequestedKey)
        NotificationCenter.default.post(name: .openQuickCameraFromSystem, object: nil)
    }

    static func consumeLaunchRequest() -> Bool {
        let requested = UserDefaults.standard.bool(forKey: launchRequestedKey)
        if requested {
            UserDefaults.standard.set(false, forKey: launchRequestedKey)
        }
        return requested
    }

    static func handle(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "foodapp" else {
            return false
        }

        let pathComponents = url.pathComponents.map { $0.lowercased() }
        let host = url.host?.lowercased()
        let isQuickCameraURL =
            host == "camera" ||
            pathComponents.contains("camera") ||
            pathComponents.contains("quick-camera")

        guard isQuickCameraURL else {
            return false
        }

        requestLaunch()
        return true
    }
}
