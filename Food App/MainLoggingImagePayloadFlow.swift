import UIKit

extension MainLoggingShellView {

    func clearImageContext() {
        pendingImageData = nil
        pendingImagePreviewData = nil
        pendingImageMimeType = nil
        pendingImageStorageRef = nil
        latestParseInputKind = "text"
        selectedCameraSource = nil
        for index in inputRows.indices {
            inputRows[index].imagePreviewData = nil
            inputRows[index].imageRef = nil
        }
    }

    /// Fast JPEG preparation. Pure transformation of `image` → encoded `Data`.
    ///
    /// `nonisolated static` so callers can run it on a background queue
    /// without an actor hop — a 12MP iPhone photo can take 1-2 s of CPU
    /// here, which used to block the main thread (and therefore the
    /// camera result drawer's shimmer presentation) for the full duration
    /// after picking from the photo library.
    ///
    /// Keep this bounded to a few passes. The image model needs enough detail
    /// to read labels and identify small food regions; the older ~180-280 KB
    /// fallback was fast, but caused real-device photos to land as low
    /// confidence. Stay comfortably under the backend 6 MB raw-image limit
    /// while preserving visual detail.
    nonisolated static func prepareImagePayload(from image: UIImage) -> PreparedImagePayload? {
        let maxPreferredBytes = 1_200_000
        let candidates: [(dimension: CGFloat, quality: CGFloat)] = [
            (1_600, 0.78),
            (1_400, 0.74),
            (1_280, 0.70)
        ]

        var largestEncoded: Data?
        for candidate in candidates {
            guard let data = encodeImage(image, maxDimension: candidate.dimension, quality: candidate.quality) else {
                continue
            }
            if largestEncoded == nil || data.count > (largestEncoded?.count ?? 0) {
                largestEncoded = data
            }
            if data.count <= maxPreferredBytes {
                return PreparedImagePayload(uploadData: data, previewData: data, mimeType: "image/jpeg")
            }
        }

        if let data = largestEncoded {
            return PreparedImagePayload(uploadData: data, previewData: data, mimeType: "image/jpeg")
        }
        return nil
    }

    nonisolated static func encodeImage(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        autoreleasepool {
            let resized = resizeImageIfNeeded(image, maxDimension: maxDimension)
            return resized.jpegData(compressionQuality: quality)
        }
    }

    nonisolated static func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else {
            return image
        }

        let scale = maxDimension / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
