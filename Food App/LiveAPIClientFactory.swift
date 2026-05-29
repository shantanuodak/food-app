import Foundation

enum LiveAPIClientFactory {
    static func make() -> APIClient {
        let configuration = AppConfiguration.live()
        // Use the process-wide shared AuthService so Siri, notification, and
        // QuickCamera API clients refresh through the SAME SupabaseClient (and
        // the SAME in-memory session) as the main app. Previously each call
        // built a fresh AuthService + AuthSessionStore + SupabaseClient, so
        // several instances refreshed the same rotating Supabase token
        // independently: the first rotated it, the rest hit "Refresh Token
        // Already Used", and the session was cleared. That was the overnight
        // logout. One shared client => the SDK's own single-flight covers all.
        let authService = AuthService.shared
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
