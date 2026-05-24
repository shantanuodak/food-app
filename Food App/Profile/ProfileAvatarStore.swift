import Foundation
import UIKit

enum ProfileAvatarStore {
    private static let directoryName = "ProfileAvatars"
    private static let fallbackUserID = "local"

    static func loadAvatarData(userID: String?) -> Data? {
        try? Data(contentsOf: avatarURL(userID: userID))
    }

    @discardableResult
    static func saveAvatar(_ image: UIImage, userID: String?) -> Data? {
        let normalized = normalizedImage(image)
        guard let data = normalized.jpegData(compressionQuality: 0.86) else { return nil }

        do {
            let directory = avatarsDirectoryURL()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: avatarURL(userID: userID), options: .atomic)
            return data
        } catch {
            NSLog("[ProfileAvatarStore] Failed to save avatar: %@", String(describing: error))
            return nil
        }
    }

    static func removeAvatar(userID: String?) {
        let url = avatarURL(userID: userID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            NSLog("[ProfileAvatarStore] Failed to remove avatar: %@", String(describing: error))
        }
    }

    private static func avatarURL(userID: String?) -> URL {
        avatarsDirectoryURL().appendingPathComponent("\(safeUserID(userID)).jpg")
    }

    private static func avatarsDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func safeUserID(_ userID: String?) -> String {
        let raw = userID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nonEmpty = raw?.isEmpty == false ? (raw ?? fallbackUserID) : fallbackUserID
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return nonEmpty.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "_" }
            .joined()
    }

    private static func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.size.width > 0, image.size.height > 0 else { return image }

        let targetSize = CGSize(width: 512, height: 512)
        let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawOrigin = CGPoint(
            x: (targetSize.width - drawSize.width) / 2,
            y: (targetSize.height - drawSize.height) / 2
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }
}
