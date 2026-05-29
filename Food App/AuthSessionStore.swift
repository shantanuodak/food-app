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
    let lastName: String?
}

enum AuthSessionStoreError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case keychain(OSStatus)
    case staleSession

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode auth session."
        case .decodingFailed:
            return "Failed to decode stored auth session."
        case let .keychain(status):
            return "Failed to access secure auth storage (\(status))."
        case .staleSession:
            return "Stored auth session changed before the recovered session could be saved."
        }
    }
}

final class AuthSessionStore: ObservableObject {
    @Published private(set) var session: AuthSession?
    private(set) var lastLoadStatus: String = "not_loaded"
    private(set) var lastLoadStatusCode: OSStatus?

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
        let updatedAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updatedAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            self.session = session
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw AuthSessionStoreError.keychain(updateStatus)
        }

        var addAttributes = query
        addAttributes[kSecValueData as String] = data
        addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, updatedAttributes as CFDictionary)
            guard retryStatus == errSecSuccess else {
                throw AuthSessionStoreError.keychain(retryStatus)
            }
            self.session = session
            return
        }

        guard addStatus == errSecSuccess else {
            throw AuthSessionStoreError.keychain(addStatus)
        }

        self.session = session
    }

    func clear() {
        SecItemDelete(keychainQuery() as CFDictionary)
        session = nil
    }

    func replaceInMemory(_ session: AuthSession) {
        self.session = session
    }

    func storeRecovered(_ session: AuthSession, replacing expectedSession: AuthSession) throws {
        guard let currentSession = loadSession(),
              currentSession.accessToken == expectedSession.accessToken,
              currentSession.refreshToken == expectedSession.refreshToken else {
            throw AuthSessionStoreError.staleSession
        }

        try store(session)
    }

    var shouldRetryTransientLoadFailure: Bool {
        guard session == nil, let status = lastLoadStatusCode else { return false }
        return Self.isTransientKeychainStatus(status)
    }

    @discardableResult
    func reloadSessionFromKeychain() -> AuthSession? {
        let loadedSession = loadSession()
        if let loadedSession {
            session = loadedSession
        }
        return loadedSession
    }

    private func loadSession() -> AuthSession? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            lastLoadStatus = "not_found"
            lastLoadStatusCode = status
            return nil
        }

        guard status == errSecSuccess, let data = item as? Data else {
            lastLoadStatus = "keychain_status_\(status)"
            lastLoadStatusCode = status
            return nil
        }

        guard let decoded = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            lastLoadStatus = "decode_failed"
            lastLoadStatusCode = nil
            return nil
        }

        lastLoadStatus = "loaded"
        lastLoadStatusCode = status
        return decoded
    }

    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
    }

    private static func isTransientKeychainStatus(_ status: OSStatus) -> Bool {
        status == errSecInteractionNotAllowed || status == errSecNotAvailable
    }
}
