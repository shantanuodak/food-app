import Foundation
import UIKit
import Vision

struct BarcodeHit {
    let payload: String
    let symbology: String
    let confidence: Float
}

struct LabelPanelHit {
    let detectedText: String
    let tokenScore: Int
    let perServingCaloriesGuess: Int?
    let confidence: Float
}

struct ImageVisionResult {
    let barcode: BarcodeHit?
    let labelPanel: LabelPanelHit?
    let ocrText: String
    let elapsedMs: Int
}

enum ImageVisionPipeline {
    /// Max edge size we ask Vision to see. Real iPhone captures are
    /// 12-48MP (~4000x3000+) — VNDetectBarcodesRequest and
    /// VNRecognizeTextRequest take 1-2 seconds on those, which routinely
    /// exceeds our timeout budget on real devices. Downsizing to 1280
    /// reduces detection time by 10-30x with no accuracy loss for
    /// barcodes (barcodes survive aggressive downscaling) or for
    /// nutrition-label OCR (label text remains legible well below 1280
    /// wide).
    private static let visionMaxEdge: CGFloat = 1280

    static func analyze(_ image: UIImage, timeoutMs: Int = 2500) async -> ImageVisionResult {
        let start = Date()
        // V3 hotfix (2026-05-20): pass orientation to Vision via the API parameter
        // instead of redrawing via fixedOrientation(). UIImage.draw(in:) crashes on
        // background threads for certain image backings on iOS 17+.
        guard let originalCG = image.cgImage else {
            return ImageVisionResult(barcode: nil, labelPanel: nil, ocrText: "", elapsedMs: 0)
        }
        // P1 fix (2026-05-20): resize the CGImage to <=1280 on the long
        // edge before handing to Vision. The old code passed the raw
        // 12-48MP cgImage straight in, which is what was making the
        // 800ms timeout consistently expire on real device → no barcode
        // detected → fall through to vision lane → "barcode inaccurate"
        // user reports.
        let cgImage = downscaledForVision(originalCG) ?? originalCG
        let orientation = cgImagePropertyOrientation(from: image.imageOrientation)

        async let barcodeTask = detectBarcode(cgImage, orientation: orientation, timeoutMs: timeoutMs)
        async let ocrTask = recognizeText(cgImage, orientation: orientation, timeoutMs: timeoutMs)

        let (barcode, ocrText) = await (barcodeTask, ocrTask)
        let labelPanel = detectLabelPanel(from: ocrText)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

#if DEBUG
        print("[ImageVisionPipeline] barcode=\(barcode?.payload ?? "nil") labelPanel=\(labelPanel?.confidence ?? 0) elapsedMs=\(elapsed)")
#else
        NSLog("[ImageVisionPipeline] barcode=%@ labelPanel=%.2f elapsedMs=%d", barcode?.payload ?? "nil", labelPanel?.confidence ?? 0, elapsed)
#endif

        return ImageVisionResult(barcode: barcode, labelPanel: labelPanel, ocrText: ocrText, elapsedMs: elapsed)
    }

    private static func detectBarcode(_ cgImage: CGImage, orientation: CGImagePropertyOrientation, timeoutMs: Int) async -> BarcodeHit? {
        await raceTimeout(timeoutMs: timeoutMs) {
            await Task.detached(priority: .userInitiated) {
                let request = VNDetectBarcodesRequest()
                request.symbologies = [.ean13, .ean8, .upce, .code128]
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    return nil
                }

                return request.results?
                    .compactMap { observation -> BarcodeHit? in
                        guard let payload = observation.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !payload.isEmpty else {
                            return nil
                        }
                        let symbology = symbologyName(observation.symbology)
                        return BarcodeHit(payload: payload, symbology: symbology, confidence: observation.confidence)
                    }
                    .sorted { $0.confidence > $1.confidence }
                    .first
            }.value
        }
    }

    private static func recognizeText(_ cgImage: CGImage, orientation: CGImagePropertyOrientation, timeoutMs: Int) async -> String {
        await raceTimeout(timeoutMs: timeoutMs) {
            await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["en-US"]
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    return ""
                }

                return request.results?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
            }.value
        } ?? ""
    }

    private static func detectLabelPanel(from ocrText: String) -> LabelPanelHit? {
        let lower = ocrText.lowercased()
        let hasHeader = lower.contains("nutrition facts") ||
            lower.contains("nutritional information") ||
            lower.contains("supplement facts")
        let hasCalories = lower.contains("calories") || lower.contains("energy")
        let hasMacros = lower.contains("total fat") ||
            lower.contains("carbohydrate") ||
            lower.contains("protein")
        let tokenScore = (hasHeader ? 1 : 0) + (hasCalories ? 1 : 0) + (hasMacros ? 1 : 0)
        guard tokenScore >= 2 else { return nil }

        let confidence: Float = tokenScore >= 3 ? 0.9 : 0.72
        return LabelPanelHit(
            detectedText: ocrText,
            tokenScore: tokenScore,
            perServingCaloriesGuess: calorieGuess(from: ocrText),
            confidence: confidence
        )
    }

    private static func calorieGuess(from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\bcalories\s*[:\-]?\s*(\d{1,4})\b"#) else {
            return nil
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[valueRange])
    }

    /// Returns a CGImage downscaled so its longest edge is at most
    /// `visionMaxEdge` pixels. Returns nil and the caller should fall
    /// back to the original if downscaling fails for any reason.
    ///
    /// Uses `CGContext` (not `UIImage.draw(in:)`) so this is safe on
    /// background threads — UIImage.draw was the source of the iOS 17+
    /// crash we hit in V3 hotfix territory. We also pass `colorSpace`
    /// explicitly so the destination context doesn't pick up the
    /// HEIC's wide-gamut color space (which Vision sometimes chokes
    /// on).
    private static func downscaledForVision(_ source: CGImage) -> CGImage? {
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        let longest = max(width, height)
        // Image is already small enough — no work needed, Vision is
        // fast on small images.
        guard longest > visionMaxEdge else { return source }

        let scale = visionMaxEdge / longest
        let targetWidth = Int((width * scale).rounded())
        let targetHeight = Int((height * scale).rounded())
        guard targetWidth > 0, targetHeight > 0 else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }

    /// Map UIImage.Orientation to CGImagePropertyOrientation so Vision rotates
    /// the image correctly without us redrawing it.
    private static func cgImagePropertyOrientation(from ui: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch ui {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    nonisolated private static func symbologyName(_ symbology: VNBarcodeSymbology) -> String {
        switch symbology {
        case .ean13:
            return "EAN-13"
        case .ean8:
            return "EAN-8"
        case .upce:
            return "UPC-E"
        case .code128:
            return "Code128"
        default:
            return symbology.rawValue
        }
    }

    private static func raceTimeout<T>(timeoutMs: Int, operation: @escaping () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                let delay = UInt64(max(1, timeoutMs)) * 1_000_000
                try? await Task.sleep(nanoseconds: delay)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
