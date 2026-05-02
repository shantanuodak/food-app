import Foundation

extension AuthSession {
    var displayFirstName: String? {
        let emailLocalPart = email?
            .split(separator: "@", maxSplits: 1)
            .first
            .map(String.init)

        if let firstName = Self.normalizedFirstName(from: firstName) {
            // Ignore low-quality values that are identical to an email username like "shantanuodak".
            if let emailLocalPart,
               firstName.caseInsensitiveCompare(emailLocalPart) == .orderedSame,
               !emailLocalPart.contains(where: { !$0.isLetter }) {
                // Fall through to JWT or better sources.
            } else {
                return firstName
            }
        }

        if let firstName = Self.normalizedFirstName(fromJWT: accessToken) {
            return firstName
        }

        return Self.normalizedFirstName(fromEmail: email)
    }

    private static func normalizedFirstName(from rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let firstToken = trimmed.split(whereSeparator: { !$0.isLetter }).first
        guard let firstToken, !firstToken.isEmpty else {
            return nil
        }

        return firstToken.prefix(1).uppercased() + firstToken.dropFirst().lowercased()
    }

    private static func normalizedFirstName(fromEmail email: String?) -> String? {
        guard let email else {
            return nil
        }

        guard let localPart = email.split(separator: "@", maxSplits: 1).first.map(String.init) else {
            return nil
        }

        // Only use email fallback when a clear separator exists (e.g. john.doe, john_doe).
        guard localPart.contains(where: { !$0.isLetter }) else {
            return nil
        }

        return normalizedFirstName(from: localPart)
    }

    private static func normalizedFirstName(fromJWT token: String?) -> String? {
        guard let token else {
            return nil
        }

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
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let claims = jsonObject as? [String: Any] else {
            return nil
        }

        if let firstName = extractFirstName(from: claims) {
            return firstName
        }

        if let metadata = claims["user_metadata"] as? [String: Any] {
            return extractFirstName(from: metadata)
        }

        return nil
    }

    private static func extractFirstName(from source: [String: Any]) -> String? {
        for key in ["name", "full_name"] {
            if let value = source[key] as? String,
               value.contains(where: { !$0.isLetter }),
               let first = normalizedFirstName(from: value) {
                return first
            }
        }

        if let givenName = source["given_name"] as? String {
            let familyNameCandidate = (source["family_name"] as? String) ?? (source["last_name"] as? String)
            if let familyName = familyNameCandidate {
                let normalizedGiven = givenName.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedFamily = familyName.trimmingCharacters(in: .whitespacesAndNewlines)

                if !normalizedGiven.isEmpty,
                   !normalizedFamily.isEmpty,
                   normalizedGiven.count > normalizedFamily.count,
                   normalizedGiven.lowercased().hasSuffix(normalizedFamily.lowercased()) {
                    let firstOnly = String(normalizedGiven.dropLast(normalizedFamily.count))
                    if let first = normalizedFirstName(from: firstOnly) {
                        return first
                    }
                }
            }
        }

        for key in ["given_name", "first_name"] {
            if let value = source[key] as? String,
               let first = normalizedFirstName(from: value) {
                return first
            }
        }

        return nil
    }
}
