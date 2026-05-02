import Foundation

extension APIClientError {
    nonisolated func isAuthTokenError(
        treatForbiddenAsAuthFailure: Bool = false,
        treatSessionExpiredMessageAsAuthFailure: Bool = true
    ) -> Bool {
        switch self {
        case .missingAuthToken:
            return true
        case let .server(statusCode, payload):
            if statusCode == 401 || (treatForbiddenAsAuthFailure && statusCode == 403) {
                return true
            }

            let code = payload.code.uppercased()
            if code == "UNAUTHORIZED" || code.contains("TOKEN") || code.contains("AUTH") {
                return true
            }

            let message = payload.message.lowercased()
            if message.contains("invalid token") ||
                message.contains("missing bearer token") ||
                message.contains("jwt") ||
                message.contains("unauthorized") {
                return true
            }
            return treatSessionExpiredMessageAsAuthFailure && message.contains("session expired")
        default:
            return false
        }
    }
}
