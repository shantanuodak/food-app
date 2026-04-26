import Foundation

enum APIClientError: Error, LocalizedError {
    case invalidURL
    case missingAuthToken
    case networkFailure(String)
    case server(statusCode: Int, payload: APIErrorPayload)
    case decodingFailure
    case unexpectedStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL."
        case .missingAuthToken:
            return "Sign in is required before calling this endpoint."
        case let .networkFailure(message):
            return "Network error: \(message)"
        case let .server(_, payload):
            return payload.message
        case .decodingFailure:
            return "Response format was not recognized."
        case let .unexpectedStatus(code):
            return "Unexpected server response (\(code))."
        }
    }
}

final class APIClient {
    private enum RequestTimeout {
        static let `default`: TimeInterval = 20
        static let parseText: TimeInterval = 35
        static let parseImage: TimeInterval = 45
        /// Generous timeout for endpoints that hit on cold launch or onboarding.
        /// Render.com free tier can take up to ~60s to wake from inactivity.
        static let coldStart: TimeInterval = 65
    }

    private let configuration: AppConfiguration
    private let authTokenProvider: () async throws -> String?
    private let authRecoveryHandler: (() async -> Bool)?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        configuration: AppConfiguration,
        session: URLSession = .shared,
        authTokenProvider: (() async throws -> String?)? = nil,
        authRecoveryHandler: (() async -> Bool)? = nil
    ) {
        self.configuration = configuration
        if let authTokenProvider {
            self.authTokenProvider = authTokenProvider
        } else {
            let fallbackToken = configuration.authToken
            self.authTokenProvider = { fallbackToken }
        }
        self.authRecoveryHandler = authRecoveryHandler
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func health() async throws -> HealthResponse {
        try await request(path: "/health", method: "GET", requiresAuth: false)
    }

    func submitOnboarding(_ requestBody: OnboardingRequest) async throws -> OnboardingResponse {
        try await request(path: "/v1/onboarding", method: "POST", body: requestBody, requiresAuth: true)
    }

    func parseLog(_ requestBody: ParseLogRequest) async throws -> ParseLogResponse {
        try await request(path: "/v1/logs/parse", method: "POST", body: requestBody, requiresAuth: true)
    }

    /// Streaming parse — returns items one at a time via onItem callback as they arrive from the server.
    /// The final ParseLogResponse is returned when the stream completes.
    func parseLogStreaming(
        _ requestBody: ParseLogRequest,
        onItem: @escaping @Sendable (ParsedFoodItem) -> Void
    ) async throws -> ParseLogResponse {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidURL
        }
        components.path = "/v1/logs/parse"
        guard let url = components.url else {
            throw APIClientError.invalidURL
        }

        var extraHeaders = ["Accept": "text/event-stream"]
        let bodyData = try JSONEncoder().encode(requestBody)
        let request = try await makeRequest(
            url: url,
            method: "POST",
            bodyData: bodyData,
            requiresAuth: true,
            extraHeaders: extraHeaders,
            timeoutInterval: timeoutInterval(for: "/v1/logs/parse")
        )

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIClientError.unexpectedStatus(statusCode)
        }

        var currentEvent = ""
        var currentData = ""

        for try await line in bytes.lines {
            if line.hasPrefix("event: ") {
                currentEvent = String(line.dropFirst(7))
            } else if line.hasPrefix("data: ") {
                currentData = String(line.dropFirst(6))
            } else if line.isEmpty, !currentEvent.isEmpty {
                switch currentEvent {
                case "item":
                    if let data = currentData.data(using: .utf8),
                       let item = try? JSONDecoder().decode(ParsedFoodItem.self, from: data) {
                        onItem(item)
                    }
                case "done":
                    if let data = currentData.data(using: .utf8) {
                        return try JSONDecoder().decode(ParseLogResponse.self, from: data)
                    }
                case "error":
                    throw APIClientError.networkFailure(currentData)
                default:
                    break
                }
                currentEvent = ""
                currentData = ""
            }
        }

        throw APIClientError.networkFailure("Stream ended without done event")
    }

    func parseImageLog(imageData: Data, mimeType: String, loggedAt: String?) async throws -> ParseLogResponse {
        struct ImageParseBody: Encodable {
            let imageBase64: String
            let mimeType: String
            let loggedAt: String?
        }
        let body = ImageParseBody(
            imageBase64: imageData.base64EncodedString(),
            mimeType: mimeType,
            loggedAt: loggedAt
        )
        return try await request(
            path: "/v1/logs/parse/image",
            method: "POST",
            body: body,
            requiresAuth: true
        )
    }

    func escalateParse(_ requestBody: EscalateParseRequest) async throws -> EscalateParseResponse {
        try await request(path: "/v1/logs/parse/escalate", method: "POST", body: requestBody, requiresAuth: true)
    }

    func saveLog(_ requestBody: SaveLogRequest, idempotencyKey: UUID) async throws -> SaveLogResponse {
        try await request(
            path: "/v1/logs",
            method: "POST",
            body: requestBody,
            requiresAuth: true,
            extraHeaders: ["Idempotency-Key": idempotencyKey.uuidString.lowercased()]
        )
    }

    /// Updates an existing food_log in place — used for in-row edits (the
    /// quantity fast path) so we don't create duplicate entries on the
    /// backend. Parse references in the body are optional: required only
    /// when the edit involved a fresh parse.
    func patchLog(id: String, request requestBody: PatchLogRequest) async throws -> SaveLogResponse {
        try await request(
            path: "/v1/logs/\(id)",
            method: "PATCH",
            body: requestBody,
            requiresAuth: true
        )
    }

    func deleteLog(id: String) async throws -> DeleteLogResponse {
        try await request(
            path: "/v1/logs/\(id)",
            method: "DELETE",
            requiresAuth: true
        )
    }

    func getDaySummary(date: String, timezone: String = TimeZone.current.identifier) async throws -> DaySummaryResponse {
        try await request(path: "/v1/logs/day-summary", method: "GET", queryItems: [
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "tz", value: timezone)
        ], requiresAuth: true)
    }

    func getDayLogs(date: String, timezone: String = TimeZone.current.identifier) async throws -> DayLogsResponse {
        try await request(path: "/v1/logs/day-logs", method: "GET", queryItems: [
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "tz", value: timezone)
        ], requiresAuth: true)
    }

    func getDayRange(from: String, to: String) async throws -> DayRangeResponse {
        try await request(path: "/v1/logs/day-range", method: "GET", queryItems: [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to)
        ], requiresAuth: true)
    }

    func postHealthActivity(_ requestBody: HealthActivityRequest) async throws -> HealthActivityResponse {
        try await request(path: "/v1/health/activity", method: "POST", body: requestBody, requiresAuth: true)
    }

    func getProgress(from: String, to: String, timezone: String) async throws -> ProgressResponse {
        try await request(
            path: "/v1/logs/progress",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "from", value: from),
                URLQueryItem(name: "to", value: to),
                URLQueryItem(name: "tz", value: timezone)
            ],
            requiresAuth: true
        )
    }

    func getAdminFeatureFlags() async throws -> AdminFeatureFlagsResponse {
        try await request(path: "/v1/admin/feature-flags", method: "GET", requiresAuth: true)
    }

    func updateAdminFeatureFlags(_ requestBody: AdminFeatureFlagsUpdateRequest) async throws -> AdminFeatureFlagsResponse {
        try await request(path: "/v1/admin/feature-flags", method: "PUT", body: requestBody, requiresAuth: true)
    }

    func getTrackingAccuracy(date: String, timezone: String) async throws -> TrackingAccuracyResponse {
        try await request(
            path: "/v1/profile/tracking-accuracy",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "date", value: date),
                URLQueryItem(name: "tz", value: timezone)
            ],
            requiresAuth: true
        )
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        requiresAuth: Bool,
        extraHeaders: [String: String] = [:]
    ) async throws -> Response {
        try await performRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: nil,
            requiresAuth: requiresAuth,
            extraHeaders: extraHeaders
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        requiresAuth: Bool,
        extraHeaders: [String: String] = [:]
    ) async throws -> Response {
        let encodedBody = try encoder.encode(body)
        return try await performRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: encodedBody,
            requiresAuth: requiresAuth,
            extraHeaders: extraHeaders
        )
    }

    private func performRequest<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        bodyData: Data?,
        requiresAuth: Bool,
        extraHeaders: [String: String] = [:],
        didAttemptAuthRecovery: Bool = false
    ) async throws -> Response {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidURL
        }

        components.path = path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIClientError.invalidURL
        }

        let request = try await makeRequest(
            url: url,
            method: method,
            bodyData: bodyData,
            requiresAuth: requiresAuth,
            extraHeaders: extraHeaders,
            timeoutInterval: timeoutInterval(for: path)
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIClientError.networkFailure(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.networkFailure("No HTTP response.")
        }

        if requiresAuth,
           !didAttemptAuthRecovery,
           (httpResponse.statusCode == 401 || httpResponse.statusCode == 403),
           let authRecoveryHandler,
           await authRecoveryHandler() {
            return try await performRequest(
                path: path,
                method: method,
                queryItems: queryItems,
                bodyData: bodyData,
                requiresAuth: requiresAuth,
                extraHeaders: extraHeaders,
                didAttemptAuthRecovery: true
            )
        }

        if (200 ... 299).contains(httpResponse.statusCode) {
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw APIClientError.decodingFailure
            }
        }

        if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
            throw APIClientError.server(statusCode: httpResponse.statusCode, payload: envelope.error)
        }

        throw APIClientError.unexpectedStatus(httpResponse.statusCode)
    }

    private func makeRequest(
        url: URL,
        method: String,
        bodyData: Data?,
        requiresAuth: Bool,
        extraHeaders: [String: String],
        timeoutInterval: TimeInterval
    ) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeoutInterval
        if extraHeaders["Content-Type"] == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if requiresAuth {
            let tokenValue: String?
            do {
                tokenValue = try await authTokenProvider()
            } catch let apiError as APIClientError {
                throw apiError
            } catch {
                throw APIClientError.networkFailure(error.localizedDescription)
            }

            guard let token = tokenValue?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
                throw APIClientError.missingAuthToken
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let bodyData {
            request.httpBody = bodyData
        }

        return request
    }

    private func timeoutInterval(for path: String) -> TimeInterval {
        switch path {
        case "/v1/logs/parse":
            return RequestTimeout.parseText
        case "/v1/logs/parse/image":
            return RequestTimeout.parseImage
        // These endpoints are hit at launch and after onboarding — allow time for cold starts.
        case "/v1/onboarding", "/v1/logs/day-summary", "/v1/logs/day-logs", "/v1/logs/day-range":
            return RequestTimeout.coldStart
        default:
            return RequestTimeout.default
        }
    }
}
