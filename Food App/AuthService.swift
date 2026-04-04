import Foundation
import UIKit
import AuthenticationServices
import CryptoKit
import Security

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

#if canImport(Supabase)
import Supabase
#endif

enum AuthServiceError: LocalizedError {
    case missingFallbackToken(AccountProvider)
    case providerNotConfiguredInSupabase(AccountProvider)
    case missingGoogleClientID
    case missingGoogleCallbackScheme(expected: String)
    case missingGoogleIDToken
    case missingAppleIDToken
    case missingSupabaseConfiguration
    case missingSupabaseSDK
    case missingPresentationContext(AccountProvider)
    case googleSignInFailed(String)
    case appleSignInFailed(String)
    case supabaseExchangeFailed(provider: AccountProvider, message: String)
    case failedToPersistSession(String)

    var errorDescription: String? {
        switch self {
        case let .missingFallbackToken(provider):
            return "Sign in with \(provider.rawValue.capitalized) is not configured yet. Set API_AUTH_TOKEN for scaffold mode."
        case let .providerNotConfiguredInSupabase(provider):
            return "\(provider.rawValue.capitalized) sign in is not configured for Supabase mode yet. Use Apple or Google sign in for now."
        case .missingGoogleClientID:
            return "Google sign in is missing configuration. Add GIDClientID in target Info."
        case let .missingGoogleCallbackScheme(expected):
            return "Google sign in callback is not configured. Add URL scheme '\(expected)' in target Info > URL Types."
        case .missingGoogleIDToken:
            return "Google sign in did not return an ID token."
        case .missingAppleIDToken:
            return "Apple sign in did not return an identity token."
        case .missingSupabaseConfiguration:
            return "Supabase config is missing. Add SupabaseURL and SupabaseAnonKey in target Info."
        case .missingSupabaseSDK:
            return "Supabase SDK is not linked to this app target. Add the Supabase Swift package to the target."
        case let .missingPresentationContext(provider):
            return "Unable to present \(provider.rawValue.capitalized) sign in flow right now."
        case let .googleSignInFailed(message):
            return "Google sign in failed: \(message)"
        case let .appleSignInFailed(message):
            return "Apple sign in failed: \(message)"
        case let .supabaseExchangeFailed(provider, message):
            return "\(provider.rawValue.capitalized) sign in succeeded but Supabase token exchange failed: \(message)"
        case let .failedToPersistSession(message):
            return "Signed in, but failed to save session: \(message)"
        }
    }
}

final class AuthService {
    private let sessionStore: AuthSessionStore
    private let fallbackToken: String?
    private let googleClientID: String?
    private let googleServerClientID: String?
    private let supabaseURL: URL?
    private let supabaseAnonKey: String?
    #if canImport(Supabase)
    private let supabaseClient: SupabaseClient?
    #endif
    @MainActor private var appleSignInDelegate: AppleSignInDelegate?

    init(
        sessionStore: AuthSessionStore,
        fallbackToken: String?,
        googleClientID: String?,
        googleServerClientID: String?,
        supabaseURL: URL?,
        supabaseAnonKey: String?
    ) {
        self.sessionStore = sessionStore
        self.fallbackToken = fallbackToken
        self.googleClientID = googleClientID
        self.googleServerClientID = googleServerClientID
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        #if canImport(Supabase)
        let trimmedSupabaseAnonKey = supabaseAnonKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let supabaseURL, let supabaseAnonKey = trimmedSupabaseAnonKey, !supabaseAnonKey.isEmpty {
            self.supabaseClient = SupabaseClient(
                supabaseURL: supabaseURL,
                supabaseKey: supabaseAnonKey,
                options: SupabaseClientOptions(
                    auth: SupabaseClientOptions.AuthOptions(
                        emitLocalSessionAsInitialSession: true
                    )
                )
            )
        } else {
            self.supabaseClient = nil
        }
        #endif
    }

    var currentSession: AuthSession? {
        sessionStore.session
    }

    var currentAccessToken: String? {
        sessionStore.session?.accessToken
    }

    func restoreSessionIfPossible() async {
        guard let storedSession = sessionStore.session else {
            return
        }

        guard let refreshToken = nonEmpty(storedSession.refreshToken) else {
            return
        }

        do {
            _ = try await restoreSupabaseSession(
                accessToken: storedSession.accessToken,
                refreshToken: refreshToken,
                metadata: storedSession
            )
        } catch {
            if isInvalidSessionRecoveryError(error) {
                await clearStoredSession()
            }
        }
    }

    func validAccessToken() async throws -> String? {
        let hasSupabaseConfiguration =
            supabaseURL != nil &&
            nonEmpty(supabaseAnonKey) != nil

        guard let storedSession = sessionStore.session else {
            if hasSupabaseConfiguration {
                return nil
            }
            return normalizedFallbackToken()
        }

        let accessToken = storedSession.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if accessToken.isEmpty {
            if hasSupabaseConfiguration {
                return nil
            }
            return normalizedFallbackToken()
        }

        if hasSupabaseConfiguration && accessToken.lowercased().hasPrefix("dev-") {
            return nil
        }

        guard hasSupabaseConfiguration else {
            return accessToken
        }

        if sessionNeedsRefresh(storedSession) {
            guard let refreshToken = nonEmpty(storedSession.refreshToken) else {
                await clearStoredSession()
                return nil
            }

            do {
                let refreshedSession = try await restoreSupabaseSession(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    metadata: storedSession
                )
                return refreshedSession.accessToken
            } catch {
                if isInvalidSessionRecoveryError(error) {
                    await clearStoredSession()
                    return nil
                }
                throw error
            }
        }

        return accessToken
    }

    func refreshSessionIfNeeded() async throws -> AuthSession? {
        guard let storedSession = sessionStore.session else {
            return nil
        }

        guard sessionNeedsRefresh(storedSession) else {
            return storedSession
        }

        guard let refreshToken = nonEmpty(storedSession.refreshToken) else {
            await clearStoredSession()
            return nil
        }

        do {
            return try await restoreSupabaseSession(
                accessToken: storedSession.accessToken,
                refreshToken: refreshToken,
                metadata: storedSession
            )
        } catch {
            if isInvalidSessionRecoveryError(error) {
                await clearStoredSession()
                return nil
            }
            throw error
        }
    }

    func handleUnauthorizedAndAttemptRecovery() async -> Bool {
        guard let storedSession = sessionStore.session,
              let refreshToken = nonEmpty(storedSession.refreshToken) else {
            await clearStoredSession()
            return false
        }

        do {
            _ = try await refreshSupabaseSession(refreshToken: refreshToken, metadata: storedSession)
            return true
        } catch {
            if isInvalidSessionRecoveryError(error) {
                await clearStoredSession()
            }
            return false
        }
    }

    func signIn(with provider: AccountProvider) async throws -> AuthSession {
        switch provider {
        case .apple:
            return try await signInWithApple()
        case .google:
            return try await signInWithGoogle()
        }
    }

    func signOut() {
        sessionStore.clear()
    }

#if canImport(GoogleSignIn)
    private struct GoogleSignInPayload {
        let idToken: String
        let accessToken: String
        let rawNonce: String?
        let userID: String?
        let email: String?
        let firstName: String?
    }
#endif

    fileprivate struct AppleSignInPayload {
        let idToken: String
        let rawNonce: String
        let userID: String?
        let email: String?
        let firstName: String?
    }

    private func signInWithApple() async throws -> AuthSession {
        if supabaseURL == nil || nonEmpty(supabaseAnonKey) == nil {
            return try signInWithFallback(provider: .apple)
        }

        let payload = try await performAppleSignIn()
        return try await exchangeAppleTokenWithSupabase(
            idToken: payload.idToken,
            rawNonce: payload.rawNonce,
            userID: payload.userID,
            email: payload.email,
            firstName: payload.firstName
        )
    }

    @MainActor
    private func performAppleSignIn() async throws -> AppleSignInPayload {
        guard let presentingViewController = Self.topViewController() else {
            throw AuthServiceError.missingPresentationContext(.apple)
        }

        let rawNonce = Self.randomNonce()
        let hashedNonce = Self.sha256(rawNonce)

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AppleSignInPayload, Error>) in
            let delegate = AppleSignInDelegate(
                anchorProvider: {
                    if let window = presentingViewController.view.window {
                        return window
                    }
                    return UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .flatMap(\.windows)
                        .first(where: \.isKeyWindow)
                },
                continuation: continuation,
                cleanup: { [weak self] in
                    self?.appleSignInDelegate = nil
                },
                rawNonce: rawNonce
            )

            self.appleSignInDelegate = delegate

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            controller.performRequests()
        }
    }

    private func exchangeAppleTokenWithSupabase(
        idToken: String,
        rawNonce: String,
        userID: String?,
        email: String?,
        firstName: String?
    ) async throws -> AuthSession {
        guard supabaseURL != nil, nonEmpty(supabaseAnonKey) != nil else {
            throw AuthServiceError.missingSupabaseConfiguration
        }

#if canImport(Supabase)
        guard let supabaseClient else {
            throw AuthServiceError.missingSupabaseSDK
        }

        do {
            let session = try await supabaseClient.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: rawNonce
                )
            )

            let authSession = makeAuthSession(
                from: session,
                provider: .apple,
                existing: AuthSession(
                    accessToken: session.accessToken,
                    refreshToken: session.refreshToken,
                    expiresAt: Date(timeIntervalSince1970: session.expiresAt),
                    provider: .apple,
                    userID: userID,
                    email: email,
                    firstName: firstName
                )
            )
            return try persistSession(authSession)
        } catch {
            throw AuthServiceError.supabaseExchangeFailed(provider: .apple, message: error.localizedDescription)
        }
#else
        _ = idToken
        _ = rawNonce
        _ = userID
        _ = email
        _ = firstName
        throw AuthServiceError.missingSupabaseSDK
#endif
    }

    private func signInWithGoogle() async throws -> AuthSession {
#if canImport(GoogleSignIn)
        guard let googleClientID = nonEmpty(googleClientID) else {
            throw AuthServiceError.missingGoogleClientID
        }

        let expectedScheme = Self.googleURLScheme(fromClientID: googleClientID)
        guard Self.hasURLScheme(expectedScheme) else {
            throw AuthServiceError.missingGoogleCallbackScheme(expected: expectedScheme)
        }

        let payload = try await performGoogleSignIn(
            clientID: googleClientID,
            serverClientID: nonEmpty(googleServerClientID)
        )

        let supabaseSession = try await exchangeGoogleTokensWithSupabase(
            idToken: payload.idToken,
            accessToken: payload.accessToken,
            rawNonce: payload.rawNonce,
            userID: payload.userID,
            email: payload.email,
            firstName: payload.firstName
        )
        return supabaseSession
#else
        return try signInWithFallback(provider: .google)
#endif
    }

#if canImport(GoogleSignIn)
    @MainActor
    private func performGoogleSignIn(clientID: String, serverClientID: String?) async throws -> GoogleSignInPayload {
        guard let presentingViewController = Self.topViewController() else {
            throw AuthServiceError.missingPresentationContext(.google)
        }

        if let serverClientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(
                clientID: clientID,
                serverClientID: serverClientID
            )
        } else {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        let rawNonce = UUID().uuidString

        do {
            let signInResult: GIDSignInResult = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<GIDSignInResult, Error>) in
                GIDSignIn.sharedInstance.signIn(
                    withPresenting: presentingViewController,
                    hint: nil,
                    additionalScopes: nil,
                    nonce: rawNonce,
                    claims: nil
                ) { signInResult, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let signInResult else {
                        continuation.resume(throwing: AuthServiceError.googleSignInFailed("No sign-in result returned."))
                        return
                    }
                    continuation.resume(returning: signInResult)
                }
            }
            guard let idToken = signInResult.user.idToken?.tokenString else {
                throw AuthServiceError.missingGoogleIDToken
            }

            return GoogleSignInPayload(
                idToken: idToken,
                accessToken: signInResult.user.accessToken.tokenString,
                rawNonce: rawNonce,
                userID: signInResult.user.userID,
                email: signInResult.user.profile?.email,
                firstName: signInResult.user.profile?.givenName
            )
        } catch let error as AuthServiceError {
            throw error
        } catch {
            throw AuthServiceError.googleSignInFailed(error.localizedDescription)
        }
    }
#endif

    private func exchangeGoogleTokensWithSupabase(
        idToken: String,
        accessToken: String,
        rawNonce: String?,
        userID: String?,
        email: String?,
        firstName: String?
    ) async throws -> AuthSession {
        guard supabaseURL != nil, nonEmpty(supabaseAnonKey) != nil else {
            throw AuthServiceError.missingSupabaseConfiguration
        }

#if canImport(Supabase)
        guard let supabaseClient else {
            throw AuthServiceError.missingSupabaseSDK
        }

        do {
            let session: Session
            do {
                session = try await supabaseClient.auth.signInWithIdToken(
                    credentials: googleOIDCCredentials(
                        idToken: idToken,
                        accessToken: accessToken,
                        rawNonce: rawNonce
                    )
                )
            } catch {
                if isNoncePresenceMismatch(error) {
                    // Some Google tokens may omit nonce claim; retry without nonce for compatibility.
                    session = try await supabaseClient.auth.signInWithIdToken(
                        credentials: googleOIDCCredentials(
                            idToken: idToken,
                            accessToken: accessToken,
                            rawNonce: nil
                        )
                    )
                } else {
                    throw error
                }
            }

            let authSession = makeAuthSession(
                from: session,
                provider: .google,
                existing: AuthSession(
                    accessToken: session.accessToken,
                    refreshToken: session.refreshToken,
                    expiresAt: Date(timeIntervalSince1970: session.expiresAt),
                    provider: .google,
                    userID: userID,
                    email: email,
                    firstName: firstName
                )
            )
            return try persistSession(authSession)
        } catch {
            throw AuthServiceError.supabaseExchangeFailed(provider: .google, message: error.localizedDescription)
        }
#else
        _ = idToken
        _ = accessToken
        _ = rawNonce
        _ = userID
        _ = email
        _ = firstName
        throw AuthServiceError.missingSupabaseSDK
#endif
    }

    private func signInWithFallback(provider: AccountProvider, userID: String? = nil, email: String? = nil) throws -> AuthSession {
        if supabaseURL != nil, nonEmpty(supabaseAnonKey) != nil {
            throw AuthServiceError.providerNotConfiguredInSupabase(provider)
        }

        guard let token = fallbackToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            throw AuthServiceError.missingFallbackToken(provider)
        }

        let derivedUserID: String?
        if token.lowercased().hasPrefix("dev-") {
            let suffix = String(token.dropFirst(4))
            derivedUserID = suffix.isEmpty ? nil : suffix
        } else {
            derivedUserID = nil
        }

        let session = AuthSession(
            accessToken: token,
            refreshToken: nil,
            expiresAt: nil,
            provider: provider,
            userID: userID ?? derivedUserID,
            email: email,
            firstName: nil
        )
        return try persistSession(session)
    }

    private func persistSession(_ session: AuthSession) throws -> AuthSession {
        do {
            try sessionStore.store(session)
        } catch {
            throw AuthServiceError.failedToPersistSession(error.localizedDescription)
        }
        return session
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func normalizedFallbackToken() -> String? {
        guard let token = fallbackToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return nil
        }
        return token
    }

    private func sessionNeedsRefresh(_ session: AuthSession) -> Bool {
        if let expiresAt = session.expiresAt {
            return expiresAt.timeIntervalSinceNow <= 30
        }
        return Self.isExpiredJWT(session.accessToken)
    }

    private func isInvalidSessionRecoveryError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("refresh token") ||
            message.contains("invalid grant") ||
            message.contains("session missing") ||
            message.contains("jwt expired") ||
            message.contains("token has expired") ||
            message.contains("already used") ||
            message.contains("revoked")
    }

    private func clearStoredSession() async {
        await MainActor.run {
            sessionStore.clear()
        }
    }

    #if canImport(Supabase)
    private func restoreSupabaseSession(
        accessToken: String,
        refreshToken: String,
        metadata: AuthSession
    ) async throws -> AuthSession {
        guard let supabaseClient else {
            throw AuthServiceError.missingSupabaseSDK
        }

        let session = try await supabaseClient.auth.setSession(
            accessToken: accessToken,
            refreshToken: refreshToken
        )

        let authSession = makeAuthSession(from: session, provider: metadata.provider, existing: metadata)
        return try await persistRecoveredSession(authSession)
    }

    private func refreshSupabaseSession(
        refreshToken: String,
        metadata: AuthSession
    ) async throws -> AuthSession {
        guard let supabaseClient else {
            throw AuthServiceError.missingSupabaseSDK
        }

        let session = try await supabaseClient.auth.refreshSession(refreshToken: refreshToken)
        let authSession = makeAuthSession(from: session, provider: metadata.provider, existing: metadata)
        return try await persistRecoveredSession(authSession)
    }

    private func makeAuthSession(from session: Session, provider: AccountProvider, existing: AuthSession) -> AuthSession {
        AuthSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt),
            provider: provider,
            userID: existing.userID ?? session.user.id.uuidString,
            email: existing.email ?? session.user.email,
            firstName: existing.firstName
        )
    }
    #endif

    #if !canImport(Supabase)
    private func restoreSupabaseSession(
        accessToken _: String,
        refreshToken _: String,
        metadata _: AuthSession
    ) async throws -> AuthSession {
        throw AuthServiceError.missingSupabaseSDK
    }

    private func refreshSupabaseSession(
        refreshToken _: String,
        metadata _: AuthSession
    ) async throws -> AuthSession {
        throw AuthServiceError.missingSupabaseSDK
    }
    #endif

    private func persistRecoveredSession(_ session: AuthSession) async throws -> AuthSession {
        do {
            try await MainActor.run {
                try sessionStore.store(session)
            }
        } catch {
            throw AuthServiceError.failedToPersistSession(error.localizedDescription)
        }
        return session
    }

    @MainActor
    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController

        guard let root else {
            return nil
        }

        if let nav = root as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }

        if let tab = root as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }

        if let presented = root.presentedViewController {
            return topViewController(base: presented)
        }

        return root
    }

    private static func googleURLScheme(fromClientID clientID: String) -> String {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("com.googleusercontent.apps.") {
            // Support legacy/manual entries where the reversed scheme was pasted as client ID.
            return trimmed
        }

        let suffix = ".apps.googleusercontent.com"
        if let range = trimmed.range(of: suffix) {
            // If accidental extra text is appended, use the first valid client-id segment.
            let prefix = String(trimmed[..<range.lowerBound])
            return "com.googleusercontent.apps.\(prefix)"
        }

        return "com.googleusercontent.apps.\(trimmed)"
    }

    private static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)

        var remaining = length
        while remaining > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            if status != errSecSuccess {
                return UUID().uuidString.replacingOccurrences(of: "-", with: "")
            }

            for random in randomBytes where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

#if canImport(Supabase)
    private func googleOIDCCredentials(
        idToken: String,
        accessToken: String,
        rawNonce: String?
    ) -> OpenIDConnectCredentials {
        return OpenIDConnectCredentials(
            provider: .google,
            idToken: idToken,
            accessToken: accessToken,
            nonce: rawNonce
        )
    }
#endif

    private func isNoncePresenceMismatch(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("passed nonce")
            && message.contains("id_token")
            && message.contains("both exist or not")
    }

    private static func decodeJWTClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }

        guard let payloadData = decodeBase64URL(String(parts[1])) else {
            return nil
        }

        guard let object = try? JSONSerialization.jsonObject(with: payloadData),
              let claims = object as? [String: Any] else {
            return nil
        }

        return claims
    }

    private static func isExpiredJWT(_ token: String) -> Bool {
        guard let claims = decodeJWTClaims(token),
              let exp = jwtExpiration(from: claims) else {
            return true
        }

        return Date().timeIntervalSince1970 >= exp - 30
    }

    private static func jwtExpiration(from claims: [String: Any]) -> TimeInterval? {
        guard let rawExp = claims["exp"] else {
            return nil
        }

        if let number = rawExp as? NSNumber {
            return number.doubleValue
        }
        if let double = rawExp as? Double {
            return double
        }
        if let int = rawExp as? Int {
            return TimeInterval(int)
        }
        if let string = rawExp as? String {
            return Double(string)
        }
        return nil
    }

    private static func decodeBase64URL(_ input: String) -> Data? {
        let normalized = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingLength = (4 - normalized.count % 4) % 4
        let padded = normalized + String(repeating: "=", count: paddingLength)
        return Data(base64Encoded: padded)
    }

    private static func hasURLScheme(_ targetScheme: String) -> Bool {
        guard
            let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        else {
            return false
        }

        let normalizedTarget = targetScheme.lowercased()
        for urlType in urlTypes {
            guard let schemes = urlType["CFBundleURLSchemes"] as? [String] else { continue }
            for scheme in schemes where scheme.lowercased() == normalizedTarget {
                return true
            }
        }
        return false
    }
}

@MainActor
private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let anchorProvider: () -> UIWindow?
    private let cleanup: () -> Void
    private let rawNonce: String
    private var continuation: CheckedContinuation<AuthService.AppleSignInPayload, Error>?

    init(
        anchorProvider: @escaping () -> UIWindow?,
        continuation: CheckedContinuation<AuthService.AppleSignInPayload, Error>,
        cleanup: @escaping () -> Void,
        rawNonce: String
    ) {
        self.anchorProvider = anchorProvider
        self.continuation = continuation
        self.cleanup = cleanup
        self.rawNonce = rawNonce
    }

    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        // Prefer a window from the provider, then fall back to the key window in any connected scene
        let window = anchorProvider() ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)

        if let windowScene = window?.windowScene {
            return ASPresentationAnchor(windowScene: windowScene)
        } else {
            // Fallback for cases where we couldn't obtain a window scene
            return ASPresentationAnchor()
        }
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { cleanup() }
        guard let continuation else { return }
        self.continuation = nil

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation.resume(throwing: AuthServiceError.appleSignInFailed("No Apple ID credential returned."))
            return
        }

        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              !idToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            continuation.resume(throwing: AuthServiceError.missingAppleIDToken)
            return
        }

        continuation.resume(
            returning: AuthService.AppleSignInPayload(
                idToken: idToken,
                rawNonce: rawNonce,
                userID: credential.user,
                email: credential.email,
                firstName: credential.fullName?.givenName
            )
        )
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { cleanup() }
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: AuthServiceError.appleSignInFailed(error.localizedDescription))
    }
}
