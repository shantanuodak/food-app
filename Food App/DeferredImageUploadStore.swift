//
//  DeferredImageUploadStore.swift
//  Food App
//
//  Persistent backup for the in-memory `deferredImageUploads` dict in
//  `MainLoggingShellView`. The save flow is decoupled from image upload
//  (see commit 0443246, "Decouple image upload from food_log save"): the
//  food_log row lands first with `image_ref = NULL`, then the photo is
//  uploaded in a detached background task. If the user force-quits the
//  app between save and that upload, the in-memory bytes vanish and the
//  meal stays photo-less forever. This store fixes that gap by writing
//  the bytes to disk as soon as we know the saved `logId`, then draining
//  at next launch (or whenever auth becomes available again).
//
//  Each entry is a sidecar JSON metadata file plus a `.jpg` payload file,
//  both keyed by `logId`. Drains are destructive — once you read an entry,
//  it's deleted from disk; the caller is responsible for retrying it.
//  This is intentional: better to lose a photo than burn forever on a
//  bucket that's permanently unhappy.
//
//  Caveats:
//  - 14-day TTL — entries older than that are pruned on drain.
//  - 50-entry cap — `enqueue` is a no-op past the cap to bound disk use
//    if storage is permanently broken.
//  - Not thread-safe outside the actor — all mutations go through the
//    actor's serial executor.
//

import Foundation

actor DeferredImageUploadStore {
    struct Entry {
        let logId: String
        let imageData: Data
        let createdAt: Date
    }

    private struct Sidecar: Codable {
        let logId: String
        let createdAt: Date
    }

    /// Cap on stored entries. If a user is genuinely producing this many
    /// stuck uploads, something else is wrong and we shouldn't fill their
    /// disk waiting on it. The save itself already succeeded for each one;
    /// these are photo-only retries.
    private let maxEntries = 50

    /// How long a stuck upload is worth retrying. After this, drop it.
    /// Two weeks is generous: gives time for the user to roam between
    /// networks, for backend infra fixes to ship, etc.
    private let entryTTL: TimeInterval = 14 * 24 * 60 * 60

    private let directory: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("DeferredImageUploads", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
    }

    /// Persist `imageData` for later upload, keyed by the saved `logId`.
    /// No-op if the entry already exists (idempotent on retry attempts).
    /// No-op if the store is at capacity — prevents runaway disk use.
    func enqueue(logId: String, imageData: Data) async {
        let normalized = Self.sanitize(logId)
        guard !normalized.isEmpty else { return }

        let count = (try? listLogIds().count) ?? 0
        if count >= maxEntries {
            NSLog("[DeferredImageUploadStore] At capacity (\(maxEntries)); dropping enqueue for \(logId)")
            return
        }

        let dataURL = self.dataURL(for: normalized)
        if fileManager.fileExists(atPath: dataURL.path) { return }
        let sidecarURL = self.sidecarURL(for: normalized)

        do {
            try imageData.write(to: dataURL, options: .atomic)
            let sidecar = Sidecar(logId: logId, createdAt: Date())
            let encoded = try JSONEncoder().encode(sidecar)
            try encoded.write(to: sidecarURL, options: .atomic)
        } catch {
            // Best-effort: tear down a half-written entry so a later drain
            // doesn't trip over it.
            try? fileManager.removeItem(at: dataURL)
            try? fileManager.removeItem(at: sidecarURL)
            NSLog("[DeferredImageUploadStore] enqueue failed for \(logId): \(error)")
        }
    }

    /// Returns and removes every persisted entry, dropping ones older
    /// than `entryTTL`. The caller is responsible for retrying each
    /// returned entry — this method is destructive by design.
    func drain() async -> [Entry] {
        let now = Date()
        var results: [Entry] = []
        let logIds: [String]
        do {
            logIds = try listLogIds()
        } catch {
            NSLog("[DeferredImageUploadStore] drain enumeration failed: \(error)")
            return []
        }

        for logId in logIds {
            let sidecarURL = self.sidecarURL(for: logId)
            let dataURL = self.dataURL(for: logId)

            // Read sidecar; if it's missing or unreadable, the entry is
            // half-baked — clean it up and move on.
            guard
                let sidecarData = try? Data(contentsOf: sidecarURL),
                let sidecar = try? JSONDecoder().decode(Sidecar.self, from: sidecarData)
            else {
                try? fileManager.removeItem(at: sidecarURL)
                try? fileManager.removeItem(at: dataURL)
                continue
            }

            let isExpired = now.timeIntervalSince(sidecar.createdAt) > entryTTL
            if isExpired {
                NSLog("[DeferredImageUploadStore] Dropping expired entry for \(sidecar.logId) (age \(Int(now.timeIntervalSince(sidecar.createdAt)))s)")
                try? fileManager.removeItem(at: sidecarURL)
                try? fileManager.removeItem(at: dataURL)
                continue
            }

            guard let imageData = try? Data(contentsOf: dataURL), !imageData.isEmpty else {
                // Sidecar without payload — clean up.
                try? fileManager.removeItem(at: sidecarURL)
                try? fileManager.removeItem(at: dataURL)
                continue
            }

            results.append(Entry(logId: sidecar.logId, imageData: imageData, createdAt: sidecar.createdAt))
            // Drain is destructive — caller owns the retry now.
            try? fileManager.removeItem(at: sidecarURL)
            try? fileManager.removeItem(at: dataURL)
        }

        return results
    }

    /// Idempotent removal — used after an in-session retry succeeds so a
    /// future `drain()` doesn't try the same upload again.
    func remove(logId: String) async {
        let normalized = Self.sanitize(logId)
        guard !normalized.isEmpty else { return }
        try? fileManager.removeItem(at: sidecarURL(for: normalized))
        try? fileManager.removeItem(at: dataURL(for: normalized))
    }

    /// For debugging / health checks. Returns the count of entries
    /// currently on disk.
    func pendingCount() async -> Int {
        return (try? listLogIds().count) ?? 0
    }

    // MARK: - Private

    private func listLogIds() throws -> [String] {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        // Each entry is a `<logId>.json` sidecar. Pair entries are
        // `<logId>.jpg`; we'll resolve the data file from the sidecar's
        // logId to avoid double-listing.
        return urls
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    private func sidecarURL(for logId: String) -> URL {
        directory.appendingPathComponent("\(logId).json")
    }

    private func dataURL(for logId: String) -> URL {
        directory.appendingPathComponent("\(logId).jpg")
    }

    /// `logId` should always be a UUID, but sanitize defensively in case
    /// it isn't — never trust a value that's about to become a filesystem
    /// path. Strip everything that isn't a UUID character.
    private static func sanitize(_ raw: String) -> String {
        let allowed = Set("0123456789abcdefABCDEF-")
        return String(raw.filter { allowed.contains($0) })
    }
}
