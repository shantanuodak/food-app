//
//  RecipeImportFlow.swift
//  Food App
//
//  Shared recipe-import logic used by BOTH the home drawer
//  (HomeRecipesDrawerContent) and the full Recipes screen (RecipesScreen).
//
//  Before this, only RecipesScreen knew how to (a) normalize pasted text into a
//  URL, (b) detect social/video links that need the in-app browser importer,
//  and (c) decide when a failed scrape should fall back to the browser. The
//  drawer had a stripped-down paste→import→save path that dead-ended on exactly
//  those cases. Centralizing the logic here keeps the two surfaces in lock-step.
//

import Foundation

// MARK: - URL normalization

enum RecipeImportURL {
    /// Best-effort normalization of free-form pasted text into a URL string.
    /// Mirrors what the user typed/pasted: pulls an embedded link out of a
    /// caption, adds a scheme to a bare domain, etc. Returns "" when there's
    /// nothing usable.
    static func normalized(_ rawInput: String) -> String {
        let raw = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }

        if raw.contains(" "), let embedded = firstSupportedWebURL(in: raw) {
            return embedded.absoluteString
        }
        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            return raw
        }
        if let embedded = firstSupportedWebURL(in: raw) {
            return embedded.absoluteString
        }
        if raw.contains("."), !raw.contains(" ") {
            return "https://\(raw)"
        }
        return raw
    }

    /// True when the string is a usable http(s) URL with a host.
    static func isSupported(_ rawURL: String) -> Bool {
        guard let components = URLComponents(string: rawURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host?.isEmpty == false else {
            return false
        }
        return true
    }

    /// First http(s) link found anywhere inside a block of text (e.g. a pasted
    /// social caption).
    static func firstSupportedWebURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector
            .matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .first { url in
                guard let scheme = url.scheme?.lowercased(),
                      scheme == "https" || scheme == "http",
                      url.host?.isEmpty == false else {
                    return false
                }
                return true
            }
    }
}

// MARK: - Failure classification

/// Classifies import failures using the STRUCTURED backend error code
/// (`APIClientError.server` → `APIErrorPayload.code`) instead of substring-
/// matching the human-readable message. The old string matching was brittle —
/// e.g. the drawer's "timeout" rule never fired because the server says "took
/// too long to respond".
enum RecipeImportFailure {
    /// True when the failure should route the user into the in-app browser
    /// importer (bot-walled / blocked / no structured data / unsupported page).
    static func shouldFallBackToBrowser(_ error: Error) -> Bool {
        switch serverCode(error) {
        case "RECIPE_IMPORT_SITE_BLOCKED",
             "RECIPE_IMPORT_NO_RECIPE_SCHEMA",
             "RECIPE_IMPORT_INCOMPLETE_RECIPE",
             "RECIPE_IMPORT_TOO_MANY_REDIRECTS",
             "RECIPE_IMPORT_UNSUPPORTED_CONTENT":
            return true
        case .some:
            return false
        case nil:
            // No structured code (older server / transport error): fall back to
            // the legacy message heuristic so behavior never regresses.
            let message = error.localizedDescription.lowercased()
            return message.contains("blocked direct import") ||
                message.contains("returned http 403") ||
                message.contains("returned http 402") ||
                message.contains("could not find structured recipe data") ||
                message.contains("response format was not recognized") ||
                message.contains("endpoint not found")
        }
    }

    /// User-facing message for a terminal failure (i.e. one that does NOT route
    /// to the browser importer).
    static func friendlyMessage(_ error: Error) -> String {
        switch serverCode(error) {
        case "RECIPE_IMPORT_SITE_BLOCKED":
            return "This site blocks direct imports. Try opening it in the browser importer, or use a different link."
        case "RECIPE_IMPORT_NO_RECIPE_SCHEMA", "RECIPE_IMPORT_INCOMPLETE_RECIPE":
            return "No recipe found on that page."
        case "RECIPE_IMPORT_INVALID_URL", "RECIPE_IMPORT_UNSAFE_URL":
            return "That doesn't look like a valid recipe link."
        case "RECIPE_IMPORT_TIMEOUT":
            return "That page took too long to respond — check your connection and try again."
        case "RECIPE_IMPORT_FETCH_FAILED", "RECIPE_IMPORT_PAGE_TOO_LARGE":
            return "Couldn't read that page. Try again in a moment."
        case "RECIPE_RATE_LIMITED":
            return "You're importing quickly — give it a few seconds, then try again."
        default:
            return error.localizedDescription
        }
    }

    /// The backend error code carried by an `APIClientError.server`, if any.
    static func serverCode(_ error: Error) -> String? {
        guard let apiError = error as? APIClientError else { return nil }
        if case let .server(_, payload) = apiError {
            return payload.code
        }
        return nil
    }
}
