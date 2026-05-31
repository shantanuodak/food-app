import UIKit
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        extractSharedPayload()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Opening Food App..."
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textColor = .label

        let stack = UIStackView(arrangedSubviews: [activityIndicator, statusLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 18

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func extractSharedPayload() {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        loadPayload(from: providers)
    }

    private func loadPayload(from providers: [NSItemProvider]) {
        guard !providers.isEmpty else {
            finishWithoutURL()
            return
        }

        let group = DispatchGroup()
        let resultQueue = DispatchQueue(label: "com.shantanu.foodapp.share-extension.payload")
        var urls: [URL] = []
        var textItems: [String] = []
        var mediaAttachments: [SharedRecipeMediaAttachment] = []
        var providerTypeIdentifiers: [String] = []

        for provider in providers {
            providerTypeIdentifiers.append(contentsOf: provider.registeredTypeIdentifiers)
            if let mediaTypeIdentifier = Self.mediaTypeIdentifier(from: provider) {
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: mediaTypeIdentifier) { fileURL, error in
                    let attachment = fileURL.flatMap {
                        PendingRecipeShareWriter.copyMediaFile(
                            from: $0,
                            typeIdentifier: mediaTypeIdentifier,
                            suggestedName: provider.suggestedName
                        )
                    }
                    resultQueue.async {
                        if let attachment {
                            mediaAttachments.append(attachment)
                        } else if let error {
                            providerTypeIdentifiers.append("media-copy-error:\(error.localizedDescription)")
                        }
                        group.leave()
                    }
                }
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    let extractedURLs = Self.webURLs(from: item)
                    resultQueue.async {
                        urls.append(contentsOf: extractedURLs)
                        group.leave()
                    }
                }
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    let text = Self.string(from: item)
                    let extractedURLs = Self.webURLs(from: item)
                    resultQueue.async {
                        if let text {
                            textItems.append(text)
                        }
                        urls.append(contentsOf: extractedURLs)
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            let result = resultQueue.sync {
                SharedRecipePayload(
                    url: urls.first(where: PendingRecipeShareWriter.isSupportedWebURL),
                    rawText: textItems.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                    mediaAttachment: mediaAttachments.first,
                    providerTypeIdentifiers: Array(Set(providerTypeIdentifiers)).sorted()
                )
            }

            guard let self, result.url != nil || result.mediaAttachment != nil else {
                self?.finishWithoutURL()
                return
            }

            self.finish(with: result)
        }
    }

    private func finish(with payload: SharedRecipePayload) {
        guard PendingRecipeShareWriter.save(payload) else {
            finishWithoutURL()
            return
        }

        statusLabel.text = "Opening \(payload.sourceHint.displayName) in Food App..."
        openContainingApp()
    }

    private func openContainingApp() {
        guard let appURL = URL(string: "foodapp://recipe-import") else {
            completeExtensionRequest()
            return
        }

        extensionContext?.open(appURL) { [weak self] opened in
            DispatchQueue.main.async {
                if opened {
                    self?.completeExtensionRequest()
                } else {
                    self?.activityIndicator.stopAnimating()
                    self?.statusLabel.text = "Recipe link saved. Open Food App to review it."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        self?.completeExtensionRequest()
                    }
                }
            }
        }
    }

    private func finishWithoutURL() {
        activityIndicator.stopAnimating()
        statusLabel.text = "Share a recipe link or recipe post to save it in Food App."
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            let error = NSError(
                domain: "com.shantanu.foodapp.share-extension",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No supported web URL was shared."]
            )
            self?.extensionContext?.cancelRequest(withError: error)
        }
    }

    private func completeExtensionRequest() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private static func webURLs(from item: NSSecureCoding?) -> [URL] {
        if let url = item as? URL, PendingRecipeShareWriter.isSupportedWebURL(url) {
            return [url]
        }

        if let string = string(from: item) {
            return webURLs(in: string)
        }

        return []
    }

    private static func string(from item: NSSecureCoding?) -> String? {
        if let string = item as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let url = item as? URL {
            return url.absoluteString
        }

        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private static func webURLs(in string: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return detector
            .matches(in: string, options: [], range: range)
            .compactMap(\.url)
            .filter(PendingRecipeShareWriter.isSupportedWebURL)
    }

    private static func mediaTypeIdentifier(from provider: NSItemProvider) -> String? {
        let preferredTypes = [
            UTType.movie.identifier,
            UTType.audio.identifier,
            "public.mpeg-4",
            "public.mpeg-4-audio",
            "com.apple.quicktime-movie",
            "public.mp3",
            "com.microsoft.waveform-audio"
        ]

        if let preferred = preferredTypes.first(where: provider.hasItemConformingToTypeIdentifier) {
            return preferred
        }

        return provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .movie) || type.conforms(to: .audio)
        }
    }
}

private struct SharedRecipePayload {
    var url: URL?
    let rawText: String?
    let mediaAttachment: SharedRecipeMediaAttachment?
    let providerTypeIdentifiers: [String]

    var sourceHint: SharedRecipeSourceHint {
        SharedRecipeSourceHint.infer(url: url, text: rawText)
    }
}

private struct SharedRecipeMediaAttachment {
    let fileURL: URL
    let originalFilename: String
    let typeIdentifier: String
    let mimeType: String
    let byteCount: Int
}

private enum SharedRecipeSourceHint: String {
    case genericWeb = "generic-web"
    case tiktok
    case instagram
    case facebook
    case youtube
    case pinterest

    var displayName: String {
        switch self {
        case .genericWeb: return "recipe"
        case .tiktok: return "TikTok"
        case .instagram: return "Instagram"
        case .facebook: return "Facebook"
        case .youtube: return "YouTube"
        case .pinterest: return "Pinterest"
        }
    }

    static func infer(url: URL?, text: String?) -> SharedRecipeSourceHint {
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

private enum PendingRecipeShareWriter {
    private static let appGroupID = "group.com.shantanu.foodapp"
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
    private static let mediaDirectoryName = "RecipeImportMedia"

    static func save(_ payload: SharedRecipePayload) -> Bool {
        if let url = payload.url, !isSupportedWebURL(url) {
            return false
        }

        guard let defaults = UserDefaults(suiteName: appGroupID),
              payload.url != nil || payload.mediaAttachment != nil else {
            return false
        }

        if let url = payload.url {
            defaults.set(url.absoluteString, forKey: pendingURLKey)
        } else {
            defaults.removeObject(forKey: pendingURLKey)
        }
        defaults.set(Date(), forKey: pendingCreatedAtKey)
        defaults.set("share-extension", forKey: pendingSourceKey)
        if let rawText = payload.rawText {
            defaults.set(rawText, forKey: pendingRawTextKey)
        } else {
            defaults.removeObject(forKey: pendingRawTextKey)
        }
        defaults.set(payload.sourceHint.rawValue, forKey: pendingSourceHintKey)
        defaults.set(payload.providerTypeIdentifiers, forKey: pendingProviderTypeIdentifiersKey)
        if let mediaAttachment = payload.mediaAttachment {
            defaults.set(mediaAttachment.fileURL.absoluteString, forKey: pendingMediaFileURLKey)
            defaults.set(mediaAttachment.originalFilename, forKey: pendingMediaOriginalFilenameKey)
            defaults.set(mediaAttachment.typeIdentifier, forKey: pendingMediaTypeIdentifierKey)
            defaults.set(mediaAttachment.mimeType, forKey: pendingMediaMimeTypeKey)
            defaults.set(mediaAttachment.byteCount, forKey: pendingMediaByteCountKey)
        } else {
            defaults.removeObject(forKey: pendingMediaFileURLKey)
            defaults.removeObject(forKey: pendingMediaOriginalFilenameKey)
            defaults.removeObject(forKey: pendingMediaTypeIdentifierKey)
            defaults.removeObject(forKey: pendingMediaMimeTypeKey)
            defaults.removeObject(forKey: pendingMediaByteCountKey)
        }
        defaults.synchronize()
        return true
    }

    static func copyMediaFile(from sourceURL: URL, typeIdentifier: String, suggestedName: String?) -> SharedRecipeMediaAttachment? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }

        let directoryURL = containerURL.appendingPathComponent(mediaDirectoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            pruneOldMediaFiles(in: directoryURL)
            let filename = mediaFilename(sourceURL: sourceURL, typeIdentifier: typeIdentifier, suggestedName: suggestedName)
            let destinationURL = directoryURL.appendingPathComponent(filename, isDirectory: false)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
            return SharedRecipeMediaAttachment(
                fileURL: destinationURL,
                originalFilename: sourceURL.lastPathComponent,
                typeIdentifier: typeIdentifier,
                mimeType: mimeType(for: typeIdentifier, fileURL: destinationURL),
                byteCount: byteCount
            )
        } catch {
            return nil
        }
    }

    nonisolated static func isSupportedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else {
            return false
        }
        return true
    }

    private static func mediaFilename(sourceURL: URL, typeIdentifier: String, suggestedName: String?) -> String {
        let baseName = (suggestedName?.isEmpty == false ? suggestedName : sourceURL.deletingPathExtension().lastPathComponent) ?? "recipe-media"
        let safeBaseName = baseName.replacingOccurrences(of: #"[^a-zA-Z0-9._-]+"#, with: "-", options: .regularExpression)
        let existingExtension = sourceURL.pathExtension
        let fallbackExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "m4a"
        let fileExtension = existingExtension.isEmpty ? fallbackExtension : existingExtension
        return "\(UUID().uuidString)-\(safeBaseName).\(fileExtension)"
    }

    private static func mimeType(for typeIdentifier: String, fileURL: URL) -> String {
        if let mimeType = UTType(typeIdentifier)?.preferredMIMEType {
            return mimeType
        }
        if let type = UTType(filenameExtension: fileURL.pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }
        return "application/octet-stream"
    }

    private static func pruneOldMediaFiles(in directoryURL: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for fileURL in contents {
            let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}
