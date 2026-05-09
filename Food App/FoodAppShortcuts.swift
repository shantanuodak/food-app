import AppIntents

struct FoodAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFoodIntent(),
            phrases: [
                "Log food in \(.applicationName)",
                "Track food in \(.applicationName)",
                "Add food to \(.applicationName)",
                "Log with \(.applicationName)",
                "Record food with \(.applicationName)",
                "Tell \(.applicationName) I ate",
                "Add a meal in \(.applicationName)"
            ],
            shortTitle: "Log Food",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: OpenFoodCameraIntent(),
            phrases: [
                "Open food camera in \(.applicationName)",
                "Start food camera in \(.applicationName)",
                "Take a food photo in \(.applicationName)",
                "\(.applicationName) camera",
                "Food camera with \(.applicationName)",
                "Log a photo with \(.applicationName)"
            ],
            shortTitle: "Food Camera",
            systemImageName: "fork.knife"
        )
    }
}
