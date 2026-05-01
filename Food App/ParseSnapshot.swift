import Foundation

/// Stable per-row parse capture used by autosave.
/// Keeps the exact `rawText` and backend provenance that must be replayed on save.
struct ParseSnapshot {
    let rowID: UUID
    let parseRequestId: String
    let parseVersion: String
    let rawText: String
    let loggedAt: String
    let response: ParseLogResponse
    let rowItems: [ParsedFoodItem]
    let capturedAt: Date
}
