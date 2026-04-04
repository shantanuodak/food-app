import Foundation

enum ImageStorageServiceError: LocalizedError {
    case missingSupabaseConfiguration
    case missingAuthToken
    case invalidUploadURL
    case uploadFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingSupabaseConfiguration:
            return "Image storage is not configured."
        case .missingAuthToken:
            return "Please sign in again before uploading images."
        case .invalidUploadURL:
            return "Failed to prepare image upload request."
        case let .uploadFailed(statusCode, message):
            return "Image upload failed (\(statusCode)): \(message)"
        }
    }
}

final class ImageStorageService {
    private let configuration: AppConfiguration
    private let authTokenProvider: () async throws -> String?
    private let session: URLSession

    init(
        configuration: AppConfiguration,
        authTokenProvider: @escaping () async throws -> String?,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.authTokenProvider = authTokenProvider
        self.session = session
    }

    func uploadJPEG(_ data: Data, userIdentifierHint: String? = nil) async throws -> String {
        guard let supabaseURL = configuration.supabaseURL,
              let supabaseAnonKey = configuration.supabaseAnonKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !supabaseAnonKey.isEmpty else {
            throw ImageStorageServiceError.missingSupabaseConfiguration
        }

        guard let accessToken = try await authTokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !accessToken.isEmpty else {
            throw ImageStorageServiceError.missingAuthToken
        }

        let userID = Self.jwtSubject(from: accessToken) ??
            userIdentifierHint?.trimmingCharacters(in: .whitespacesAndNewlines) ??
            "anonymous"

        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let objectPath = "users/\(userID)/food-logs/\(year)/\(String(format: "%02d", month))/\(UUID().uuidString).jpg"
        let bucket = configuration.supabaseStorageBucket

        guard var components = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false) else {
            throw ImageStorageServiceError.invalidUploadURL
        }

        let encodedObjectPath = objectPath
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")

        components.path = "/storage/v1/object/\(bucket)/\(encodedObjectPath)"
        guard let url = components.url else {
            throw ImageStorageServiceError.invalidUploadURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = data
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("false", forHTTPHeaderField: "x-upsert")

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            throw ImageStorageServiceError.uploadFailed(statusCode: -1, message: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImageStorageServiceError.uploadFailed(statusCode: -1, message: "No HTTP response from storage")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ImageStorageServiceError.uploadFailed(statusCode: httpResponse.statusCode, message: message?.isEmpty == false ? message! : "Unknown storage error")
        }

        return objectPath
    }

    private static func jwtSubject(from token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count > 1 else {
            return nil
        }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = payload.count % 4
        if padding > 0 {
            payload += String(repeating: "=", count: 4 - padding)
        }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data),
              let claims = object as? [String: Any],
              let sub = claims["sub"] as? String,
              !sub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return sub
    }
}
