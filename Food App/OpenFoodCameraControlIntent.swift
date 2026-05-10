import AppIntents

@available(iOS 18.0, *)
enum FoodCameraControlTarget: String, AppEnum {
    case camera

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Food Camera")
    static var caseDisplayRepresentations: [FoodCameraControlTarget: DisplayRepresentation] = [
        .camera: DisplayRepresentation(title: "Food Camera")
    ]
}

@available(iOS 18.0, *)
struct OpenFoodCameraControlIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open Food Camera"
    static var description = IntentDescription("Opens Food App directly to the quick camera logger.")

    @Parameter(title: "Target")
    var target: FoodCameraControlTarget

    init() {
        self.target = .camera
    }

    init(target: FoodCameraControlTarget) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCameraLaunchStore.requestLaunch()
        return .result()
    }
}
