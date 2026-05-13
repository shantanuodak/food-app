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
    /// Keep this to one normal pass plus one fallback pass. The previous
    /// dimension/quality search could perform many JPEG encodes before
    /// landing near 500 KB, which showed up as ~2.5 s of client prep in
    /// TestFlight telemetry.
    nonisolated static func prepareImagePayload(from image: UIImage) -> PreparedImagePayload? {
        let primary = encodeImage(image, maxDimension: 1280, quality: 0.68)
        if let primary, primary.count <= 420_000 {
            return PreparedImagePayload(uploadData: primary, previewData: primary, mimeType: "image/jpeg")
        }

        let fallback = encodeImage(image, maxDimension: 1024, quality: 0.60)
        if let data = fallback ?? primary {
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
