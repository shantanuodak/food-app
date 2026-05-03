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

    /// JPEG compression loop. Pure transformation of `image` → encoded `Data`.
    ///
    /// `nonisolated static` so callers can run it on a background queue
    /// without an actor hop — a 12MP iPhone photo can take 1-2 s of CPU
    /// here, which used to block the main thread (and therefore the
    /// camera result drawer's shimmer presentation) for the full duration
    /// after picking from the photo library.
    ///
    /// The inner loop is wrapped in `autoreleasepool` so each
    /// (dimension, quality) iteration's intermediate `Data` buffers are
    /// released as soon as the next iteration starts. Without this,
    /// holding 5-6 intermediates simultaneously can spike memory beyond
    /// 1 GB during photo processing — see
    /// `docs/PHASE_8_10_FINDINGS.md` Phase 9 #1.
    nonisolated static func prepareImagePayload(from image: UIImage) -> PreparedImagePayload? {
        let maxBytes = 600_000
        let dimensionAttempts: [CGFloat] = [1920, 1600, 1280, 1024]
        let qualityAttempts: [CGFloat] = [0.85, 0.78, 0.70, 0.62, 0.55, 0.45, 0.35]
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
