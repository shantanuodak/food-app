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

    /// Fast JPEG preparation for meal-photo vision parsing.
    ///
    /// `nonisolated static` so callers can run it on a background queue
    /// without an actor hop — a 12MP iPhone photo can take 1-2 s of CPU
    /// here, which used to block the main thread (and therefore the
    /// camera result drawer's shimmer presentation) for the full duration
    /// after picking from the photo library.
    ///
    /// Meal photos should feel close to text logging speed. The backend can
    /// still optimize larger payloads, but sending ~1.2 MB from the phone
    /// avoids the 10s+ client/upload tax we saw with 5-6 MB camera images.
    /// If we later add exact package-label OCR, that should use a separate
    /// high-detail mode rather than slowing down every normal meal photo.
    /// The loop still runs off the main thread and each encode is scoped by
    /// `autoreleasepool` to avoid retaining large intermediate buffers.
    nonisolated static func prepareImagePayload(from image: UIImage) -> PreparedImagePayload? {
        // V3 hotfix (2026-05-20): fixedOrientation() removed from background path.
        // UIImage.draw(in:) + UIGraphicsImageRenderer.image{} crash on background
        // threads in iOS 17+ under strict main-actor checking for certain image
        // backings (HEIC, photo library). jpegData() handles imageOrientation
        // automatically, so we pass the raw image through.
        //
        // If we need to resize, first rehydrate through JPEG so later drawing
        // works on a plain decoded backing instead of the original PhotoKit/HEIC
        // image object that triggered the crash.
        let maxBytes = 1_200_000
        let dimensionAttempts: [CGFloat] = [1440, 1280, 1024]
        let qualityAttempts: [CGFloat] = [0.84, 0.80, 0.76, 0.72]
        var smallestData: Data?
        let resizeSafeImage = backgroundResizeSafeImage(from: image)

        for dimension in dimensionAttempts {
            let result: PreparedImagePayload? = autoreleasepool {
                let resized = resizeImageIfNeeded(resizeSafeImage, maxDimension: dimension)
                for quality in qualityAttempts {
                    let inner: PreparedImagePayload? = autoreleasepool {
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
                    if let inner {
                        return inner
                    }
                }
                return nil
            }
            if let result {
                return result
            }
        }

        if let smallestData {
            return PreparedImagePayload(uploadData: smallestData, previewData: smallestData, mimeType: "image/jpeg")
        }
        return nil
    }

    nonisolated static func backgroundResizeSafeImage(from image: UIImage) -> UIImage {
        guard let data = image.jpegData(compressionQuality: 1.0),
              let decoded = UIImage(data: data, scale: image.scale) else {
            return image
        }
        return decoded
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
