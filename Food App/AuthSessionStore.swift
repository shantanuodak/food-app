import Foundation
import Combine
import Security

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let provider: AccountProvider
    let userID: String?
    let email: String?
    let firstName: String?
}

enum AuthSessionStoreError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode auth session."
        case .decodingFailed:
            return "Failed to decode stored auth session."
        case let .keychain(status):
            return "Failed to access secure auth storage (\(status))."
        }
    }
}

final class AuthSessionStore: ObservableObject {
    @Published private(set) var session: AuthSession?

    private let serviceName: String
    private let accountName = "auth.session.v1"

    init(serviceName: String = Bundle.main.bundleIdentifier ?? "FoodApp") {
        self.serviceName = serviceName
        self.session = loadSession()
    }

    func store(_ session: AuthSession) throws {
        guard let data = try? JSONEncoder().encode(session) else {
            throw AuthSessionStoreError.encodingFailed
        }

        let query = keychainQuery()
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthSessionStoreError.keychain(status)
        }

        self.session = session
    }

    func clear() {
        SecItemDelete(keychainQuery() as CFDictionary)
        session = nil
    }

    private func loadSession() -> AuthSession? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        guard let decoded = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            return nil
        }

        return decoded
    }

    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
    }
}
