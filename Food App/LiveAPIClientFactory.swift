import Foundation

enum LiveAPIClientFactory {
    static func make() -> APIClient {
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
        return APIClient(
            configuration: configuration,
            authTokenProvider: {
                try await authService.validAccessToken()
            },
            authRecoveryHandler: {
                await authService.handleUnauthorizedAndAttemptRecovery()
            }
        )
    }
}
