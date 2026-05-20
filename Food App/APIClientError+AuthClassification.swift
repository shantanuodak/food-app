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
            let code = payload.code.uppercased()
            let message = payload.message.lowercased()

            if statusCode == 401 {
                return true
            }

            if treatForbiddenAsAuthFailure && statusCode == 403 {
                return code == "UNAUTHORIZED" ||
                    code == "INVALID_TOKEN" ||
                    code == "TOKEN_EXPIRED" ||
                    code == "JWT_EXPIRED" ||
                    code == "MISSING_BEARER_TOKEN" ||
                    message.contains("invalid token") ||
                    message.contains("missing bearer token") ||
                    message.contains("token expired") ||
                    message.contains("jwt expired")
            }

            if code == "UNAUTHORIZED" ||
                code == "INVALID_TOKEN" ||
                code == "TOKEN_EXPIRED" ||
                code == "JWT_EXPIRED" ||
                code == "MISSING_BEARER_TOKEN" {
                return true
            }

            if message.contains("invalid token") ||
                message.contains("missing bearer token") ||
                message.contains("token expired") ||
                message.contains("jwt expired") ||
                message.contains("unauthorized") {
                return true
            }
            return treatSessionExpiredMessageAsAuthFailure && message.contains("session expired")
        default:
            return false
        }
    }
}
