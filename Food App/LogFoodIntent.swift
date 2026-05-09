import AppIntents
import Foundation

struct LogFoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Food"
    static var description = IntentDescription("Logs a food entry in Food App using your current account.")
    static var openAppWhenRun = false

    @Parameter(title: "Food", description: "The food or drink to log, like avocado toast or black coffee.")
    var foodText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$foodText)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let result = try await SiriFoodLoggingService.live().log(foodText: foodText)
            let caloriesCopy = result.calories == 1 ? "1 calorie" : "\(result.calories) calories"
            return .result(dialog: "Logged \(result.foodText), about \(caloriesCopy).")
        } catch let error as SiriFoodLoggingError {
            let message = error.errorDescription ?? "I couldn't log that right now."
            return .result(dialog: IntentDialog(stringLiteral: message))
        } catch {
            return .result(dialog: "I couldn't log that right now. Try again in Food App.")
        }
    }
}
