import Foundation

enum HomeLoggingSaveRequestUtils {
    static func fingerprint(_ request: SaveLogRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(request) else {
            return UUID().uuidString
        }
        return data.base64EncodedString()
    }

    nonisolated static func isRecoverablePendingSaveItem(_ item: PendingSaveQueueItem) -> Bool {
        if item.serverLogId != nil {
            return true
        }

        guard UUID(uuidString: item.idempotencyKey) != nil else {
            return false
        }

        let body = item.request.parsedLog
        let rawText = body.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawText.isEmpty {
            return true
        }

        let inputKind = HomeLoggingRowFactory.normalizedInputKind(body.inputKind, fallback: "text")
        let imageRef = body.imageRef?.trimmingCharacters(in: .whitespacesAndNewlines)
        return inputKind == "image" &&
            ((imageRef?.isEmpty == false) || item.imageUploadData != nil || item.imagePreviewData != nil)
    }
}
