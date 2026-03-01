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
    private let configuration: AppConfiguration
    private let authTokenProvider: () -> String?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        configuration: AppConfiguration,
        session: URLSession = .shared,
        authTokenProvider: (() -> String?)? = nil
    ) {
        self.configuration = configuration
        if let authTokenProvider {
            self.authTokenProvider = authTokenProvider
        } else {
            let fallbackToken = configuration.authToken
            self.authTokenProvider = { fallbackToken }
        }
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

    func parseImageLog(imageData: Data, mimeType: String, loggedAt: String?) async throws -> ParseLogResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ string: String) {
            if let data = string.data(using: .utf8) {
                body.append(data)
            }
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"meal.jpg\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(imageData)
        append("\r\n")

        if let loggedAt, !loggedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"loggedAt\"\r\n\r\n")
            append("\(loggedAt)\r\n")
        }

        append("--\(boundary)--\r\n")

        return try await performRequest(
            path: "/v1/logs/parse/image",
            method: "POST",
            queryItems: [],
            bodyData: body,
            requiresAuth: true,
            extraHeaders: [
                "Content-Type": "multipart/form-data; boundary=\(boundary)"
            ]
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

    func getDaySummary(date: String) async throws -> DaySummaryResponse {
        try await request(path: "/v1/logs/day-summary", method: "GET", queryItems: [URLQueryItem(name: "date", value: date)], requiresAuth: true)
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
        extraHeaders: [String: String] = [:]
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

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        if extraHeaders["Content-Type"] == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if requiresAuth {
            guard let token = authTokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
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
}
