import UIKit
import UserNotifications
import BackgroundTasks

final class FoodAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let appRefreshIdentifier = FoodBackgroundRefreshService.appRefreshIdentifier

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: appRefreshIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await FoodBackgroundRefreshService.shared.handle(refreshTask)
            }
        }

        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories(
            FoodNotificationCategory.categories()
                .union(QuickCameraNotificationService.categories())
        )
        center.delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(
            name: .apnsDeviceTokenDidChange,
            object: nil,
            userInfo: ["token": token]
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task {
            if !(await FoodNotificationActionHandler.handle(response)) {
                await QuickCameraNotificationActionHandler.handle(response)
            }
            completionHandler()
        }
    }
}

@MainActor
final class FoodBackgroundRefreshService {
    static let shared = FoodBackgroundRefreshService()
    static let appRefreshIdentifier = "com.shantanu.foodapp.refresh"

    weak var appStore: AppStore?

    private init() {}

    func scheduleAppRefresh(earliestBeginDate: Date = Date(timeIntervalSinceNow: 30 * 60)) {
        let request = BGAppRefreshTaskRequest(identifier: Self.appRefreshIdentifier)
        request.earliestBeginDate = earliestBeginDate

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("[background_refresh] schedule_failed %@", error.localizedDescription)
        }
    }

    func handle(_ task: BGAppRefreshTask) async {
        scheduleAppRefresh()

        let refreshTask = Task { [weak self] in
            guard let self, let appStore = self.appStore else { return false }
            return await appStore.performBackgroundHomeRefresh()
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }

        let success = await refreshTask.value
        task.setTaskCompleted(success: success)
    }
}
