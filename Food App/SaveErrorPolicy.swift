import Foundation

enum SaveErrorPolicy {
    static func isNonRetryable(_ error: Error) -> Bool {
        guard let apiError = error as? APIClientError else {
            return false
        }

        switch apiError {
        case let .server(statusCode, payload):
            if [400, 404, 409, 422].contains(statusCode) {
                return true
            }
            let code = payload.code.uppercased()
            return code.contains("INVALID") ||
                code.contains("CONFLICT") ||
                code.contains("NOT_FOUND")
        case let .unexpectedStatus(statusCode):
            return [400, 404, 409, 422].contains(statusCode)
        default:
            return false
        }
    }
}
