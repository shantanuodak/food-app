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
        static let parseBarcode: TimeInterval = 2
        static let parseLabel: TimeInterval = 6
        static let recipeImport: TimeInterval = 45
        static let recipeAudioImport: TimeInterval = 90
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

    func warmHealth() async {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            return
        }
        components.path = "/health"
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        _ = try? await session.data(for: request)
    }

    func submitOnboarding(_ requestBody: OnboardingRequest) async throws -> OnboardingResponse {
        try await request(path: "/v1/onboarding", method: "POST", body: requestBody, requiresAuth: true)
    }

    func getOnboardingProfile() async throws -> OnboardingProfileResponse {
        try await request(path: "/v1/onboarding", method: "GET", requiresAuth: true)
    }

    /// V3.1 Phase 5: check whether the just-authenticated user has previously
    /// completed onboarding. Called in the sign-up flow right after OAuth so
    /// we can short-circuit to "welcome back" if the user already exists.
    func fetchOnboardingStatus() async throws -> OnboardingStatusResponse {
        try await request(path: "/v1/onboarding/status", method: "GET", requiresAuth: true)
    }

    /// Bug 2 (2026-05-22): set the user's display name. Used by the Account
    /// screen so testers like Tanmay who lost their name after Apple Sign In
    /// re-auth can type a replacement. Server trims + caps at 80 chars and
    /// returns the persisted value (or nil if the user cleared the field).
    @discardableResult
    func updateDisplayName(_ name: String) async throws -> UpdateDisplayNameResponse {
        struct Body: Encodable { let displayName: String }
        return try await request(
            path: "/v1/users/me",
            method: "PATCH",
            body: Body(displayName: name),
            requiresAuth: true
        )
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

        let extraHeaders = ["Accept": "text/event-stream"]
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

    func parseImageLog(
        imageData: Data,
        mimeType: String,
        loggedAt: String?,
        contextNote: String? = nil,
        clientAttemptId: String? = nil
    ) async throws -> ParseLogResponse {
        struct ImageParseBody: Encodable {
            let clientAttemptId: String?
            let imageBase64: String
            let mimeType: String
            let contextNote: String?
            let loggedAt: String?
        }
        let trimmedContextNote = contextNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = ImageParseBody(
            clientAttemptId: clientAttemptId,
            imageBase64: imageData.base64EncodedString(),
            mimeType: mimeType,
            contextNote: trimmedContextNote?.isEmpty == false ? trimmedContextNote : nil,
            loggedAt: loggedAt
        )
        return try await request(
            path: "/v1/logs/parse/image",
            method: "POST",
            body: body,
            requiresAuth: true
        )
    }

    func parseBarcode(
        code: String,
        symbology: String?,
        contextNote: String? = nil,
        clientAttemptId: String? = nil,
        loggedAt: String?
    ) async throws -> ParseLogResponse {
        struct BarcodeParseBody: Encodable {
            let clientAttemptId: String?
            let barcode: String
            let symbology: String?
            let contextNote: String?
            let loggedAt: String?
        }
        let trimmedContextNote = contextNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = BarcodeParseBody(
            clientAttemptId: clientAttemptId,
            barcode: code,
            symbology: symbology,
            contextNote: trimmedContextNote?.isEmpty == false ? trimmedContextNote : nil,
            loggedAt: loggedAt
        )
        return try await request(
            path: "/v1/logs/parse/barcode",
            method: "POST",
            body: body,
            requiresAuth: true
        )
    }

    func parseLabel(
        ocrText: String,
        imageData: Data?,
        mimeType: String?,
        contextNote: String? = nil,
        clientAttemptId: String? = nil,
        loggedAt: String?
    ) async throws -> ParseLogResponse {
        struct LabelParseBody: Encodable {
            let clientAttemptId: String?
            let ocrText: String
            let imageBase64: String?
            let mimeType: String?
            let contextNote: String?
            let loggedAt: String?
        }
        let trimmedContextNote = contextNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = LabelParseBody(
            clientAttemptId: clientAttemptId,
            ocrText: ocrText,
            imageBase64: imageData?.base64EncodedString(),
            mimeType: mimeType,
            contextNote: trimmedContextNote?.isEmpty == false ? trimmedContextNote : nil,
            loggedAt: loggedAt
        )
        return try await request(
            path: "/v1/logs/parse/label",
            method: "POST",
            body: body,
            requiresAuth: true
        )
    }

    @discardableResult
    func recordImageParseAttempt(_ requestBody: ImageParseAttemptTelemetryRequest) async throws -> AcceptedResponse {
        try await request(
            path: "/v1/logs/parse/image-attempts",
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )
    }

    @discardableResult
    func recordAuthDiagnosticEvents(_ requestBody: AuthDiagnosticBatchRequest) async throws -> AcceptedResponse {
        try await request(
            path: "/v1/auth-diagnostics/events",
            method: "POST",
            body: requestBody,
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

    func parseHydration(_ requestBody: HydrationParseRequest) async throws -> HydrationParseResponse {
        try await request(path: "/v1/hydration/parse", method: "POST", body: requestBody, requiresAuth: true)
    }

    func getHydrationGoal() async throws -> HydrationGoalResponse {
        try await request(path: "/v1/hydration/goal", method: "GET", requiresAuth: true)
    }

    @discardableResult
    func updateHydrationGoal(_ requestBody: HydrationGoalRequest) async throws -> HydrationGoalResponse {
        try await request(path: "/v1/hydration/goal", method: "PUT", body: requestBody, requiresAuth: true)
    }

    @discardableResult
    func deleteHydrationGoal() async throws -> DeleteHydrationGoalResponse {
        try await request(path: "/v1/hydration/goal", method: "DELETE", requiresAuth: true)
    }

    @discardableResult
    func saveHydrationLog(_ requestBody: HydrationLogRequest) async throws -> HydrationLogResponse {
        try await request(path: "/v1/hydration/logs", method: "POST", body: requestBody, requiresAuth: true)
    }

    @discardableResult
    func patchHydrationLog(id: String, request requestBody: HydrationLogRequest) async throws -> HydrationLogResponse {
        try await request(
            path: "/v1/hydration/logs/\(id)",
            method: "PATCH",
            body: requestBody,
            requiresAuth: true
        )
    }

    @discardableResult
    func deleteHydrationLog(id: String) async throws -> DeleteHydrationLogResponse {
        try await request(
            path: "/v1/hydration/logs/\(id)",
            method: "DELETE",
            requiresAuth: true
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

    /// Attaches (or clears) the storage object path for a previously-saved
    /// food log. Used by the post-save image upload path so that a failed
    /// or slow image upload never blocks the food_log row from landing.
    /// Pass `imageRef = nil` to clear an abandoned ref.
    @discardableResult
    func updateLogImageRef(id: String, imageRef: String?) async throws -> UpdateLogImageRefResponse {
        struct Body: Encodable { let imageRef: String? }
        return try await request(
            path: "/v1/logs/\(id)/image-ref",
            method: "PATCH",
            body: Body(imageRef: imageRef),
            requiresAuth: true
        )
    }

    /// Submit user feedback from the in-app form. The backend records device
    /// + version metadata alongside the message; the testing dashboard's
    /// Feedback tab surfaces it newest-first for triage.
    @discardableResult
    func submitFeedback(_ requestBody: SubmitFeedbackRequest) async throws -> SubmitFeedbackResponse {
        try await request(
            path: "/v1/feedback",
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )
    }

    func getRoadmap() async throws -> RoadmapResponse {
        try await request(path: "/v1/roadmap", method: "GET", requiresAuth: true)
    }

    @discardableResult
    func registerNotificationDevice(_ requestBody: RegisterNotificationDeviceRequest) async throws -> RegisterNotificationDeviceResponse {
        try await request(path: "/v1/notifications/devices", method: "POST", body: requestBody, requiresAuth: true)
    }

    @discardableResult
    func updateNotificationPreferences(_ requestBody: NotificationPreferencesRequest) async throws -> NotificationPreferencesResponse {
        try await request(path: "/v1/notifications/preferences", method: "PUT", body: requestBody, requiresAuth: true)
    }

    @discardableResult
    func recordNotificationEvent(_ requestBody: NotificationEventRequest) async throws -> AcceptedResponse {
        try await request(path: "/v1/notifications/events", method: "POST", body: requestBody, requiresAuth: true)
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

    func getHydrationDaySummary(date: String, timezone: String = TimeZone.current.identifier) async throws -> HydrationDaySummaryResponse {
        try await request(path: "/v1/hydration/day-summary", method: "GET", queryItems: [
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "tz", value: timezone)
        ], requiresAuth: true)
    }

    func getHydrationDayLogs(date: String, timezone: String = TimeZone.current.identifier) async throws -> HydrationDayLogsResponse {
        try await request(path: "/v1/hydration/day-logs", method: "GET", queryItems: [
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

    func getHydrationProgress(from: String, to: String, timezone: String) async throws -> HydrationProgressResponse {
        try await request(
            path: "/v1/hydration/progress",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "from", value: from),
                URLQueryItem(name: "to", value: to),
                URLQueryItem(name: "tz", value: timezone)
            ],
            requiresAuth: true
        )
    }

    func getStreaks(range: Int, to: String? = nil, timezone: String) async throws -> StreakResponse {
        var queryItems = [
            URLQueryItem(name: "range", value: String(range)),
            URLQueryItem(name: "tz", value: timezone)
        ]
        if let to {
            queryItems.append(URLQueryItem(name: "to", value: to))
        }

        return try await request(
            path: "/v1/logs/streaks",
            method: "GET",
            queryItems: queryItems,
            requiresAuth: true
        )
    }

    func getBadgesSummary(timezone: String) async throws -> BadgesSummaryResponse {
        try await request(
            path: "/v1/rewards/summary",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "tz", value: timezone)
            ],
            requiresAuth: true
        )
    }

    func getSavedMeals() async throws -> SavedMealsResponse {
        try await request(path: "/v1/saved-meals", method: "GET", requiresAuth: true)
    }

    func importRecipeFromURL(_ requestBody: RecipeImportRequest) async throws -> RecipeImportResponse {
        try await request(
            path: "/v1/recipes/import-from-url",
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )
    }

    /// Sends extracted social-caption / page text to the backend so it can be
    /// structured by the same Gemini cleanup pass the URL/audio lanes use.
    /// Used by the in-app browser importer (Instagram/TikTok/Facebook), whose
    /// client-side heuristic draft is otherwise unstructured.
    func structureRecipeText(_ requestBody: RecipeStructureTextRequest) async throws -> RecipeImportResponse {
        try await request(
            path: "/v1/recipes/structure-text",
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )
    }

    func importRecipeFromAudioFile(
        fileData: Data,
        filename: String,
        mimeType: String,
        sourceUrl: String,
        sourceName: String?,
        heroImageUrl: String? = nil,
        language: String? = nil
    ) async throws -> RecipeImportResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        let bodyData = multipartRecipeAudioBody(
            fileData: fileData,
            filename: filename,
            mimeType: mimeType,
            sourceUrl: sourceUrl,
            sourceName: sourceName,
            heroImageUrl: heroImageUrl,
            language: language,
            boundary: boundary
        )

        return try await performRequest(
            path: "/v1/recipes/import-from-audio",
            method: "POST",
            bodyData: bodyData,
            requiresAuth: true,
            extraHeaders: ["Content-Type": "multipart/form-data; boundary=\(boundary)"]
        )
    }

    func getRecipes() async throws -> RecipesResponse {
        try await request(path: "/v1/recipes", method: "GET", requiresAuth: true)
    }

    @discardableResult
    func createRecipe(_ requestBody: CreateRecipeRequest) async throws -> CreateRecipeResponse {
        try await request(
            path: "/v1/recipes",
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )
    }

    @discardableResult
    func deleteRecipe(id: String) async throws -> DeleteRecipeResponse {
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await request(
            path: "/v1/recipes/\(encodedID)",
            method: "DELETE",
            requiresAuth: true
        )
    }

    @discardableResult
    func createSavedMealCollection(_ requestBody: CreateSavedMealCollectionRequest) async throws -> CreateSavedMealCollectionResponse {
        try await request(
            path: "/v1/saved-meals/collections",
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )
    }

    @discardableResult
    func createSavedMeal(_ requestBody: CreateSavedMealRequest) async throws -> CreateSavedMealResponse {
        try await request(
            path: "/v1/saved-meals",
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )
    }

    @discardableResult
    func logSavedMeal(id: String, request requestBody: LogSavedMealRequest) async throws -> SaveLogResponse {
        try await request(
            path: "/v1/saved-meals/\(id)/log",
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )
    }

    @discardableResult
    func deleteSavedMeal(id: String) async throws -> DeleteSavedMealResponse {
        try await request(
            path: "/v1/saved-meals/\(id)",
            method: "DELETE",
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
        if method.uppercased() == "GET" {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
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

    private func multipartRecipeAudioBody(
        fileData: Data,
        filename: String,
        mimeType: String,
        sourceUrl: String,
        sourceName: String?,
        heroImageUrl: String?,
        language: String?,
        boundary: String
    ) -> Data {
        var body = Data()

        func append(_ string: String) {
            body.append(contentsOf: string.utf8)
        }

        func appendField(name: String, value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return
            }

            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(multipartHeaderSafe(name))\"\r\n\r\n")
            append(value)
            append("\r\n")
        }

        appendField(name: "sourceUrl", value: sourceUrl)
        appendField(name: "sourceName", value: sourceName)
        appendField(name: "heroImageUrl", value: heroImageUrl)
        appendField(name: "language", value: language)

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(multipartHeaderSafe(filename))\"\r\n")
        append("Content-Type: \(multipartHeaderSafe(mimeType.isEmpty ? "application/octet-stream" : mimeType))\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")

        return body
    }

    private func multipartHeaderSafe(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
    }

    private func timeoutInterval(for path: String) -> TimeInterval {
        switch path {
        case "/v1/logs/parse":
            return RequestTimeout.parseText
        case "/v1/logs/parse/image":
            return RequestTimeout.parseImage
        case "/v1/logs/parse/barcode":
            return RequestTimeout.parseBarcode
        case "/v1/logs/parse/label":
            return RequestTimeout.parseLabel
        case "/v1/recipes/import-from-url":
            return RequestTimeout.recipeImport
        case "/v1/recipes/import-from-audio":
            return RequestTimeout.recipeAudioImport
        // These endpoints are hit at launch and after onboarding — allow time for cold starts.
        // Rewards/streaks belong here too: they're heavy (streaks reads a full
        // year; summary recomputes every badge) and the trophy case can be the
        // first thing opened against a cold backend. With the 20s default they
        // were timing out and firing "Couldn't load badge progress. Check your
        // connection." when the server was merely waking.
        case "/v1/onboarding",
             "/v1/logs/day-summary",
             "/v1/logs/day-logs",
             "/v1/logs/day-range",
             "/v1/logs/streaks",
             "/v1/rewards/summary",
             "/v1/hydration/goal",
             "/v1/hydration/day-summary",
             "/v1/hydration/day-logs",
             "/v1/hydration/progress":
            return RequestTimeout.coldStart
        default:
            return RequestTimeout.default
        }
    }
}
