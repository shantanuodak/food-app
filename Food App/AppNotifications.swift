import Foundation

extension Notification.Name {
    static let nutritionProgressDidChange = Notification.Name("nutritionProgressDidChange")
    static let savedMealDidLog = Notification.Name("savedMealDidLog")
    static let openTextLoggerFromNotification = Notification.Name("openTextLoggerFromNotification")
    static let openStreaksFromNotification = Notification.Name("openStreaksFromNotification")
    static let openBadgesFromStreakDrawer = Notification.Name("openBadgesFromStreakDrawer")
    static let openRemindersFromNotification = Notification.Name("openRemindersFromNotification")
    static let apnsDeviceTokenDidChange = Notification.Name("apnsDeviceTokenDidChange")
    static let recipeImportPendingURLDidChange = Notification.Name("recipeImportPendingURLDidChange")
}
