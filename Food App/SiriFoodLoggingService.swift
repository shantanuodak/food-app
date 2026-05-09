import Foundation

struct SiriFoodLoggingResult: Equatable {
    let logId: String
    let foodText: String
    let calories: Int
}

enum SiriFoodLoggingError: LocalizedError {
    case emptyFoodText
    case notSignedIn
    case needsClarification
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyFoodText:
            return "Tell me what food to log."
        case .notSignedIn:
            return "Open Food App and sign in before using Siri logging."
        case .needsClarification:
            return "I need a little more detail before I can save that. Open Food App to finish this log."
        case let .saveFailed(message):
            return message
        }
    }
}

struct SiriFoodLoggingService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    static func live() -> SiriFoodLoggingService {
        let configuration = AppConfiguration.live()
        let sessionStore = AuthSessionStore()
        let authService = AuthService(
            sessionStore: sessionStore,
            fallbackToken: configuration.authToken,
            googleClientID: configuration.googleClientID,
            googleServerClientID: configuration.googleServerClientID,
            supabaseURL: configuration.supabaseURL,
            supabaseAnonKey: configuration.supabaseAnonKey
        )
        let apiClient = APIClient(
            configuration: configuration,
            authTokenProvider: {
                try await authService.validAccessToken()
            },
            authRecoveryHandler: {
                await authService.handleUnauthorizedAndAttemptRecovery()
            }
        )
        return SiriFoodLoggingService(apiClient: apiClient)
    }

    func log(foodText: String, date: Date = Date()) async throws -> SiriFoodLoggingResult {
        let trimmedText = foodText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw SiriFoodLoggingError.emptyFoodText
        }

        let loggedAt = HomeLoggingDateUtils.loggedAtFormatter.string(from: date)

        do {
            let parseResponse = try await apiClient.parseLog(
                ParseLogRequest(text: trimmedText, loggedAt: loggedAt)
            )
            let saveRequest = try FoodLogSaveRequestBuilder.makeSaveRequest(
                rawText: trimmedText,
                loggedAt: loggedAt,
                parseResponse: parseResponse,
                inputKind: "text"
            )
            let saveResponse = try await apiClient.saveLog(saveRequest, idempotencyKey: UUID())
            return SiriFoodLoggingResult(
                logId: saveResponse.logId,
                foodText: trimmedText,
                calories: Int(saveRequest.parsedLog.totals.calories.rounded())
            )
        } catch let builderError as FoodLogSaveRequestBuilderError {
            switch builderError {
            case .needsClarification, .noParsedItems:
                throw SiriFoodLoggingError.needsClarification
            }
        } catch let apiError as APIClientError {
            if apiError.isAuthTokenError(treatForbiddenAsAuthFailure: true) {
                throw SiriFoodLoggingError.notSignedIn
            }
            throw SiriFoodLoggingError.saveFailed(apiError.errorDescription ?? "I couldn't log that right now.")
        } catch let siriError as SiriFoodLoggingError {
            throw siriError
        } catch {
            throw SiriFoodLoggingError.saveFailed("I couldn't log that right now.")
        }
    }
}
