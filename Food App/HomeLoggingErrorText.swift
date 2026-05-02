import Foundation

enum HomeLoggingErrorText {
    static func daySummaryError(_ error: Error) -> String {
        guard let apiError = error as? APIClientError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        if apiError.isAuthTokenError(treatForbiddenAsAuthFailure: true, treatSessionExpiredMessageAsAuthFailure: false) {
            return L10n.authSessionExpired
        }

        switch apiError {
        case let .server(_, payload):
            switch payload.code {
            case "PROFILE_NOT_FOUND":
                return L10n.daySummaryProfileNotFound
            case "INVALID_INPUT":
                return L10n.daySummaryInvalidInput
            default:
                return payload.message
            }
        case .networkFailure(_):
            return L10n.daySummaryNetworkFailure
        default:
            return apiError.errorDescription ?? L10n.daySummaryFailure
        }
    }

    static func saveError(_ error: Error) -> String {
        guard let apiError = error as? APIClientError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        if apiError.isAuthTokenError(treatForbiddenAsAuthFailure: true, treatSessionExpiredMessageAsAuthFailure: false) {
            return L10n.authSessionExpired
        }

        switch apiError {
        case let .server(_, payload):
            switch payload.code {
            case "IDEMPOTENCY_CONFLICT":
                return L10n.saveIdempotencyConflict
            case "INVALID_PARSE_REFERENCE":
                return L10n.saveInvalidParseReference
            case "MISSING_IDEMPOTENCY_KEY":
                return L10n.saveMissingIdempotency
            default:
                return payload.message
            }
        case .networkFailure(_):
            return L10n.saveNetworkFailure
        default:
            return apiError.errorDescription ?? L10n.saveFailure
        }
    }

    static func parseError(_ error: Error) -> String {
        guard let apiError = error as? APIClientError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        if apiError.isAuthTokenError(treatForbiddenAsAuthFailure: true, treatSessionExpiredMessageAsAuthFailure: false) {
            return L10n.authSessionExpired
        }

        switch apiError {
        case .networkFailure(_):
            return L10n.parseNetworkFailure
        case let .server(statusCode, _) where statusCode == 429:
            return L10n.parseRateLimited
        default:
            return apiError.errorDescription ?? L10n.parseFailure
        }
    }

    static func escalationError(_ error: Error) -> (message: String, blockCode: String?) {
        guard let apiError = error as? APIClientError else {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return (message, nil)
        }

        if apiError.isAuthTokenError(treatForbiddenAsAuthFailure: true, treatSessionExpiredMessageAsAuthFailure: false) {
            return (L10n.authSessionExpired, nil)
        }

        switch apiError {
        case let .server(_, payload):
            switch payload.code {
            case "ESCALATION_DISABLED":
                return (L10n.escalationDisabledNow, "ESCALATION_DISABLED")
            case "BUDGET_EXCEEDED":
                return (L10n.escalationBudgetExceeded, "BUDGET_EXCEEDED")
            case "ESCALATION_NOT_REQUIRED":
                return (L10n.escalationNoLongerNeeded, nil)
            case "INVALID_PARSE_REFERENCE":
                return (L10n.escalationInvalidParseReference, nil)
            default:
                return (payload.message, nil)
            }
        case .networkFailure(_):
            return (L10n.escalationNetworkFailure, nil)
        default:
            return (apiError.errorDescription ?? L10n.escalationFailure, nil)
        }
    }
}
