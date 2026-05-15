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

    /// High-quality JPEG preparation for vision parsing.
    ///
    /// `nonisolated static` so callers can run it on a background queue
    /// without an actor hop — a 12MP iPhone photo can take 1-2 s of CPU
    /// here, which used to block the main thread (and therefore the
    /// camera result drawer's shimmer presentation) for the full duration
    /// after picking from the photo library.
    ///
    /// Do not aggressively shrink these images. Package/can labels need
    /// enough pixels for OCR-like vision behavior, and forcing everything
    /// near 600 KB caused obvious branded items to become unreadable.
    ///
    /// The backend accepts ~6 MB raw images, and Express accepts a 10 MB
    /// JSON body, so we now target ~5.8 MB. This is intentionally slower:
    /// the image parser is a core MVP feature and accuracy matters more than
    /// shaving a second off photo preparation.
    /// The loop still runs off the main thread and each encode is scoped by
    /// `autoreleasepool` to avoid retaining large intermediate buffers.
    nonisolated static func prepareImagePayload(from image: UIImage) -> PreparedImagePayload? {
        let maxBytes = 5_800_000
        let dimensionAttempts: [CGFloat] = [4032, 3600, 3024, 2560, 2048, 1920]
        let qualityAttempts: [CGFloat] = [0.98, 0.95, 0.92, 0.88, 0.84, 0.80]
        var smallestData: Data?

        for dimension in dimensionAttempts {
            let resized = resizeImageIfNeeded(image, maxDimension: dimension)
            for quality in qualityAttempts {
                let result: PreparedImagePayload? = autoreleasepool {
                    guard let data = resized.jpegData(compressionQuality: quality) else {
                        return nil
                    }
                    if smallestData.map({ data.count < $0.count }) != false {
                        smallestData = data
                    }
                    if data.count <= maxBytes {
                        return PreparedImagePayload(uploadData: data, previewData: data, mimeType: "image/jpeg")
                    }
                    return nil
                }
                if let result {
                    return result
                }
            }
        }

        if let smallestData {
            return PreparedImagePayload(uploadData: smallestData, previewData: smallestData, mimeType: "image/jpeg")
        }
        return nil
    }

    nonisolated static func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else {
            return image
        }

        let scale = maxDimension / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
