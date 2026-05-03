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

    func prepareImagePayload(from image: UIImage) -> PreparedImagePayload? {
        let maxBytes = 600_000
        let dimensionAttempts: [CGFloat] = [1920, 1600, 1280, 1024]
        let qualityAttempts: [CGFloat] = [0.85, 0.78, 0.70, 0.62, 0.55, 0.45, 0.35]
        var smallestData: Data?

        for dimension in dimensionAttempts {
            let resized = resizeImageIfNeeded(image, maxDimension: dimension)
            for quality in qualityAttempts {
                guard let data = resized.jpegData(compressionQuality: quality) else {
                    continue
                }
                if smallestData.map({ data.count < $0.count }) != false {
                    smallestData = data
                }
                if data.count <= maxBytes {
                    return PreparedImagePayload(uploadData: data, previewData: data, mimeType: "image/jpeg")
                }
            }
        }

        if let smallestData {
            return PreparedImagePayload(uploadData: smallestData, previewData: smallestData, mimeType: "image/jpeg")
        }
        return nil
    }

    func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
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
