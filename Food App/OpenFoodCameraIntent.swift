import AppIntents

struct OpenFoodCameraIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Food Camera"
    static var description = IntentDescription("Opens Food App directly to the quick camera logger.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCameraLaunchStore.requestLaunch()
        return .result()
    }
}
