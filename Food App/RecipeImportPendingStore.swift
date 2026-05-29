import Foundation

struct RecipeImportPendingPayload: Equatable {
    let url: URL?
    let createdAt: Date?
    let source: String?
    let rawText: String?
    let sourceHint: RecipeImportSourceHint
    let providerTypeIdentifiers: [String]
    let mediaAttachment: RecipeImportPendingMediaAttachment?
}

struct RecipeImportPendingMediaAttachment: Equatable {
    let fileURL: URL
    let originalFilename: String?
    let typeIdentifier: String?
    let mimeType: String?
    let byteCount: Int?
}

enum RecipeImportSourceHint: String {
    case genericWeb = "generic-web"
    case tiktok
    case instagram
    case facebook
    case youtube
    case pinterest

    var displayName: String {
        switch self {
        case .genericWeb: return "Web page"
        case .tiktok: return "TikTok"
        case .instagram: return "Instagram"
        case .facebook: return "Facebook"
        case .youtube: return "YouTube"
        case .pinterest: return "Pinterest"
        }
    }

    var prefersBrowserImport: Bool {
        switch self {
        case .genericWeb:
            return false
        case .tiktok, .instagram, .facebook, .youtube, .pinterest:
            return true
        }
    }

    var browserImportTitle: String {
        switch self {
        case .genericWeb:
            return "Recipe page"
        case .tiktok, .instagram, .facebook, .youtube, .pinterest:
            return "\(displayName) recipe"
        }
    }

    var browserImportInstruction: String {
        switch self {
        case .genericWeb:
            return "When the recipe is visible, import it from this page."
        case .tiktok, .instagram, .facebook, .youtube, .pinterest:
            return "Open the post here. If the recipe or caption is visible, import it from this page."
        }
    }

    static func infer(url: URL?, text: String? = nil) -> RecipeImportSourceHint {
        let haystack = [
            url?.host,
            url?.absoluteString,
            text
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if haystack.contains("tiktok.com") {
            return .tiktok
        }

        if haystack.contains("instagram.com") || haystack.contains("threads.net") {
            return .instagram
        }

        if haystack.contains("facebook.com") || haystack.contains("fb.watch") || haystack.contains("fb.com") {
            return .facebook
        }

        if haystack.contains("youtube.com") || haystack.contains("youtu.be") {
            return .youtube
        }

        if haystack.contains("pinterest.com") || haystack.contains("pin.it") {
            return .pinterest
        }

        return .genericWeb
    }
}

enum RecipeImportPendingStore {
    static let appGroupID = "group.com.shantanu.foodapp"
    private static let pendingURLKey = "recipeImport.pendingURL.v1"
    private static let pendingCreatedAtKey = "recipeImport.pendingCreatedAt.v1"
    private static let pendingSourceKey = "recipeImport.pendingSource.v1"
    private static let pendingRawTextKey = "recipeImport.pendingRawText.v1"
    private static let pendingSourceHintKey = "recipeImport.pendingSourceHint.v1"
    private static let pendingProviderTypeIdentifiersKey = "recipeImport.pendingProviderTypeIdentifiers.v1"
    private static let pendingMediaFileURLKey = "recipeImport.pendingMediaFileURL.v1"
    private static let pendingMediaOriginalFilenameKey = "recipeImport.pendingMediaOriginalFilename.v1"
    private static let pendingMediaTypeIdentifierKey = "recipeImport.pendingMediaTypeIdentifier.v1"
    private static let pendingMediaMimeTypeKey = "recipeImport.pendingMediaMimeType.v1"
    private static let pendingMediaByteCountKey = "recipeImport.pendingMediaByteCount.v1"

    @discardableResult
    static func savePendingURL(_ url: URL, source: String) -> Bool {
        savePendingPayload(
            url: url,
            source: source,
            rawText: nil,
            sourceHint: RecipeImportSourceHint.infer(url: url),
            providerTypeIdentifiers: []
        )
    }

    @discardableResult
    static func savePendingPayload(
        url: URL,
        source: String,
        rawText: String?,
        sourceHint: RecipeImportSourceHint? = nil,
        providerTypeIdentifiers: [String] = []
    ) -> Bool {
        guard isSupportedWebURL(url),
              let defaults = UserDefaults(suiteName: appGroupID) else {
            return false
        }

        defaults.set(url.absoluteString, forKey: pendingURLKey)
        defaults.set(Date(), forKey: pendingCreatedAtKey)
        defaults.set(source, forKey: pendingSourceKey)
        defaults.set(clean(rawText), forKey: pendingRawTextKey)
        defaults.set((sourceHint ?? RecipeImportSourceHint.infer(url: url, text: rawText)).rawValue, forKey: pendingSourceHintKey)
        defaults.set(providerTypeIdentifiers, forKey: pendingProviderTypeIdentifiersKey)
        defaults.removeObject(forKey: pendingMediaFileURLKey)
        defaults.removeObject(forKey: pendingMediaOriginalFilenameKey)
        defaults.removeObject(forKey: pendingMediaTypeIdentifierKey)
        defaults.removeObject(forKey: pendingMediaMimeTypeKey)
        defaults.removeObject(forKey: pendingMediaByteCountKey)
        defaults.synchronize()
        return true
    }

    static func pendingPayload() -> RecipeImportPendingPayload? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return nil
        }

        let url = pendingWebURL(from: defaults)
        let rawText = clean(defaults.string(forKey: pendingRawTextKey))
        let mediaAttachment = pendingMediaAttachment(from: defaults)
        guard url != nil || mediaAttachment != nil else {
            return nil
        }

        let storedSourceHint = defaults.string(forKey: pendingSourceHintKey)
            .flatMap(RecipeImportSourceHint.init(rawValue:))

        let payload = RecipeImportPendingPayload(
            url: url,
            createdAt: defaults.object(forKey: pendingCreatedAtKey) as? Date,
            source: defaults.string(forKey: pendingSourceKey),
            rawText: rawText,
            sourceHint: storedSourceHint ?? RecipeImportSourceHint.infer(url: url, text: rawText),
            providerTypeIdentifiers: defaults.stringArray(forKey: pendingProviderTypeIdentifiersKey) ?? [],
            mediaAttachment: mediaAttachment
        )

#if DEBUG
        print(
            [
                "Recipe share payload:",
                "source=\(payload.source ?? "unknown")",
                "hint=\(payload.sourceHint.rawValue)",
                "url=\(payload.url?.absoluteString ?? "none")",
                "rawTextChars=\(payload.rawText?.count ?? 0)",
                "mediaURL=\(payload.mediaAttachment?.fileURL.absoluteString ?? "none")",
                "mediaBytes=\(payload.mediaAttachment?.byteCount ?? 0)",
                "mediaType=\(payload.mediaAttachment?.typeIdentifier ?? "none")",
                "mediaMime=\(payload.mediaAttachment?.mimeType ?? "none")",
                "providerTypes=\(payload.providerTypeIdentifiers.joined(separator: ","))"
            ].joined(separator: " ")
        )
#endif

        return payload
    }

    static func pendingURL() -> URL? {
        pendingPayload()?.url
    }

    static func consumePendingURL() -> URL? {
        let payload = pendingPayload()
        if payload != nil {
            clearPendingURL()
        }
        return payload?.url
    }

    // MARK: - Single-flight processing guard
    //
    // Two RecipesScreen instances can observe .recipeImportPendingURLDidChange
    // at the same time (one pushed from the Profile bento + one freshly
    // presented when a new share arrives). Without this, both read the same
    // pending payload and fire duplicate imports. Keyed by payload identity and
    // released when processing finishes, so a legitimate later re-trigger
    // (e.g. after the user signs in) is still allowed. MainActor-serialized, so
    // the check-and-set needs no lock.
    @MainActor private static var inFlightProcessingKey: String?

    @MainActor
    static func beginProcessing(_ payload: RecipeImportPendingPayload) -> Bool {
        let key = processingKey(for: payload)
        if inFlightProcessingKey == key {
            return false
        }
        inFlightProcessingKey = key
        return true
    }

    @MainActor
    static func endProcessing() {
        inFlightProcessingKey = nil
    }

    private static func processingKey(for payload: RecipeImportPendingPayload) -> String {
        let stamp = payload.createdAt.map { String($0.timeIntervalSince1970) } ?? "0"
        let url = payload.url?.absoluteString ?? ""
        let media = payload.mediaAttachment?.fileURL.absoluteString ?? ""
        return "\(stamp)|\(url)|\(media)"
    }

    static func clearPendingURL() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.removeObject(forKey: pendingURLKey)
        defaults.removeObject(forKey: pendingCreatedAtKey)
        defaults.removeObject(forKey: pendingSourceKey)
        defaults.removeObject(forKey: pendingRawTextKey)
        defaults.removeObject(forKey: pendingSourceHintKey)
        defaults.removeObject(forKey: pendingProviderTypeIdentifiersKey)
        defaults.removeObject(forKey: pendingMediaFileURLKey)
        defaults.removeObject(forKey: pendingMediaOriginalFilenameKey)
        defaults.removeObject(forKey: pendingMediaTypeIdentifierKey)
        defaults.removeObject(forKey: pendingMediaMimeTypeKey)
        defaults.removeObject(forKey: pendingMediaByteCountKey)
        defaults.synchronize()
    }

    static func handle(url: URL) -> Bool {
        guard isRecipeImportDeepLink(url) else { return false }

        if let sharedURL = sharedURLQueryItem(from: url) {
            savePendingPayload(
                url: sharedURL,
                source: "deep-link",
                rawText: nil,
                sourceHint: RecipeImportSourceHint.infer(url: sharedURL)
            )
        }

        notifyPendingURLIfAvailable()
        return true
    }

    static func notifyPendingURLIfAvailable() {
        guard pendingPayload() != nil else { return }
        NotificationCenter.default.post(name: .recipeImportPendingURLDidChange, object: nil)
    }

    private static func isRecipeImportDeepLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "foodapp" else { return false }
        let host = url.host?.lowercased()
        let pathComponents = url.pathComponents.map { $0.lowercased() }
        return host == "recipe-import" || pathComponents.contains("recipe-import")
    }

    private static func sharedURLQueryItem(from url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawValue = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let sharedURL = URL(string: rawValue),
              isSupportedWebURL(sharedURL) else {
            return nil
        }
        return sharedURL
    }

    private static func isSupportedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else {
            return false
        }
        return true
    }

    private static func pendingWebURL(from defaults: UserDefaults) -> URL? {
        guard let rawURL = defaults.string(forKey: pendingURLKey),
              let url = URL(string: rawURL),
              isSupportedWebURL(url) else {
            return nil
        }
        return url
    }

    private static func pendingMediaAttachment(from defaults: UserDefaults) -> RecipeImportPendingMediaAttachment? {
        guard let rawFileURL = defaults.string(forKey: pendingMediaFileURLKey),
              let fileURL = URL(string: rawFileURL) else {
            return nil
        }

        return RecipeImportPendingMediaAttachment(
            fileURL: fileURL,
            originalFilename: defaults.string(forKey: pendingMediaOriginalFilenameKey),
            typeIdentifier: defaults.string(forKey: pendingMediaTypeIdentifierKey),
            mimeType: defaults.string(forKey: pendingMediaMimeTypeKey),
            byteCount: defaults.object(forKey: pendingMediaByteCountKey) as? Int
        )
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
