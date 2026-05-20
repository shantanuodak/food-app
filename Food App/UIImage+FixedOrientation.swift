import UIKit

extension UIImage {
    /// Bakes imageOrientation into pixels so Vision and JPEG encoding read the image upright.
    nonisolated func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
