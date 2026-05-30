import Foundation

private enum RecipeLossyDecoding {
    static func string<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> String? {
        if let value = try? container.decode(String.self, forKey: key) {
            return clean(value)
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            return clean(String(value))
        }
        if let value = try? container.decode(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        if let values = try? container.decode([String].self, forKey: key) {
            return clean(values.joined(separator: ", "))
        }
        return nil
    }

    static func string(from decoder: Decoder) -> String? {
        guard let container = try? decoder.singleValueContainer() else {
            return nil
        }
        if let value = try? container.decode(String.self) {
            return clean(value)
        }
        if let value = try? container.decode(Int.self) {
            return String(value)
        }
        if let value = try? container.decode(Double.self) {
            return clean(String(value))
        }
        if let value = try? container.decode(Bool.self) {
            return value ? "true" : "false"
        }
        return nil
    }

    static func double<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = string(from: container, forKey: key) {
            return Double(value)
        }
        return nil
    }

    static func int<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    static func stringArray<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> [String] {
        recipeLines(from: container, forKey: key)
    }

    static func recipeTextLines<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> [RecipeTextLine] {
        recipeLines(from: container, forKey: key).map { RecipeTextLine(text: $0) }
    }

    static func recipeLines<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> [String] {
        if let strings = try? container.decode([String].self, forKey: key) {
            return cleaned(strings)
        }

        guard var values = try? container.nestedUnkeyedContainer(forKey: key) else {
            return []
        }

        var lines: [String] = []
        while !values.isAtEnd {
            if let line = try? values.decode(RecipeTextLine.self),
               !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(line.text)
            } else {
                _ = try? values.decode(RecipeDiscardedValue.self)
            }
        }

        return cleaned(lines)
    }

    static func httpURLString(_ value: String?) -> String? {
        guard let value = clean(value) else {
            return nil
        }
        let candidate: String
        if let tailRange = value.range(of: ")](") {
            candidate = String(value[..<tailRange.lowerBound])
        } else {
            candidate = value
        }

        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url.absoluteString
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cleaned(_ values: [String]) -> [String] {
        values
            .compactMap { clean($0) }
            .filter { !$0.isEmpty }
    }
}

private struct RecipeDiscardedValue: Decodable {
    init(from decoder: Decoder) throws {}
}

struct RecipeImportRequest: Encodable {
    let url: String
}

struct RecipeAudioURLImportRequest: Encodable {
    let sourceUrl: String
    let sourceName: String?
    let heroImageUrl: String?
    let audioUrl: String
    let language: String?
}

struct RecipeStructureTextRequest: Encodable {
    let text: String
    let sourceUrl: String
    let sourceName: String?
    let heroImageUrl: String?
}

struct RecipeImportResponse: Decodable {
    let draft: RecipeImportDraft

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let importId = RecipeLossyDecoding.string(from: container, forKey: .importId)
        if let draft = try? container.decodeIfPresent(RecipeImportDraft.self, forKey: .draft) {
            var mergedDraft = draft
            if mergedDraft.importId == nil {
                mergedDraft.importId = importId
            }
            self.draft = mergedDraft
        } else {
            self.draft = try RecipeImportDraft(from: decoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case importId
        case draft
    }
}

struct RecipeImportDraft: Codable, Identifiable, Hashable {
    var importId: String?
    var title: String
    var sourceUrl: String
    var sourceDomain: String?
    var sourceName: String?
    var heroImageUrl: String?
    var description: String?
    var servings: String?
    var prepTime: String?
    var cookTime: String?
    var totalTime: String?
    var categories: [String]
    var cuisines: [String]
    var keywords: [String]
    var ingredients: [String]
    var steps: [String]
    var confidence: Double?
    var warnings: [String]

    var id: String { importId ?? sourceUrl }

    init(
        importId: String? = nil,
        title: String,
        sourceUrl: String,
        sourceDomain: String? = nil,
        sourceName: String? = nil,
        heroImageUrl: String? = nil,
        description: String? = nil,
        servings: String? = nil,
        prepTime: String? = nil,
        cookTime: String? = nil,
        totalTime: String? = nil,
        categories: [String] = [],
        cuisines: [String] = [],
        keywords: [String] = [],
        ingredients: [String],
        steps: [String],
        confidence: Double? = nil,
        warnings: [String] = []
    ) {
        self.importId = importId
        self.title = title
        self.sourceUrl = sourceUrl
        self.sourceDomain = sourceDomain
        self.sourceName = sourceName
        self.heroImageUrl = heroImageUrl
        self.description = description
        self.servings = servings
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.totalTime = totalTime
        self.categories = categories
        self.cuisines = cuisines
        self.keywords = keywords
        self.ingredients = ingredients
        self.steps = steps
        self.confidence = confidence
        self.warnings = warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        importId = RecipeLossyDecoding.string(from: container, forKey: .importId)
        title = RecipeLossyDecoding.string(from: container, forKey: .title) ?? "Imported Recipe"
        sourceUrl = RecipeLossyDecoding.string(from: container, forKey: .sourceUrl)
            ?? RecipeLossyDecoding.string(from: container, forKey: .sourceURL)
            ?? RecipeLossyDecoding.string(from: container, forKey: .url)
            ?? ""
        sourceDomain = RecipeLossyDecoding.string(from: container, forKey: .sourceDomain)
        sourceName = RecipeLossyDecoding.string(from: container, forKey: .sourceName)
        heroImageUrl = RecipeLossyDecoding.httpURLString(
            RecipeLossyDecoding.string(from: container, forKey: .heroImageUrl)
                ?? RecipeLossyDecoding.string(from: container, forKey: .image)
        )
        description = RecipeLossyDecoding.string(from: container, forKey: .description)
        servings = RecipeLossyDecoding.string(from: container, forKey: .servings)
            ?? RecipeLossyDecoding.string(from: container, forKey: .recipeYield)
        prepTime = RecipeLossyDecoding.string(from: container, forKey: .prepTime)
        cookTime = RecipeLossyDecoding.string(from: container, forKey: .cookTime)
        totalTime = RecipeLossyDecoding.string(from: container, forKey: .totalTime)
        categories = RecipeLossyDecoding.stringArray(from: container, forKey: .categories)
        cuisines = RecipeLossyDecoding.stringArray(from: container, forKey: .cuisines)
        keywords = RecipeLossyDecoding.stringArray(from: container, forKey: .keywords)
        ingredients = RecipeLossyDecoding.recipeLines(from: container, forKey: .ingredients)
        steps = RecipeLossyDecoding.recipeLines(from: container, forKey: .steps)
        confidence = RecipeLossyDecoding.double(from: container, forKey: .confidence)
        warnings = RecipeLossyDecoding.stringArray(from: container, forKey: .warnings)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(importId, forKey: .importId)
        try container.encode(title, forKey: .title)
        try container.encode(sourceUrl, forKey: .sourceUrl)
        try container.encodeIfPresent(sourceDomain, forKey: .sourceDomain)
        try container.encodeIfPresent(sourceName, forKey: .sourceName)
        try container.encodeIfPresent(heroImageUrl, forKey: .heroImageUrl)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(servings, forKey: .servings)
        try container.encodeIfPresent(prepTime, forKey: .prepTime)
        try container.encodeIfPresent(cookTime, forKey: .cookTime)
        try container.encodeIfPresent(totalTime, forKey: .totalTime)
        try container.encode(categories, forKey: .categories)
        try container.encode(cuisines, forKey: .cuisines)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(ingredients, forKey: .ingredients)
        try container.encode(steps, forKey: .steps)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encode(warnings, forKey: .warnings)
    }

    private enum CodingKeys: String, CodingKey {
        case importId
        case title
        case sourceUrl
        case sourceURL
        case url
        case sourceDomain
        case sourceName
        case heroImageUrl
        case image
        case description
        case servings
        case recipeYield
        case prepTime
        case cookTime
        case totalTime
        case categories
        case cuisines
        case keywords
        case ingredients
        case steps
        case confidence
        case warnings
    }
}

struct RecipesResponse: Decodable {
    let recipes: [SavedRecipe]
}

struct DeleteRecipeResponse: Decodable {
    let id: String
    let status: String
}

struct CreateRecipeRequest: Encodable {
    let importId: String?
    let title: String
    let sourceUrl: String
    let sourceDomain: String?
    let sourceName: String?
    let heroImageUrl: String?
    let description: String?
    let servings: String?
    let prepTime: String?
    let cookTime: String?
    let totalTime: String?
    let categories: [String]
    let cuisines: [String]
    let keywords: [String]
    let ingredients: [RecipeIngredientPayload]
    let steps: [RecipeStepPayload]

    init(draft: RecipeImportDraft) {
        importId = draft.importId
        title = draft.title
        sourceUrl = draft.sourceUrl
        sourceDomain = draft.sourceDomain
        sourceName = draft.sourceName
        heroImageUrl = draft.heroImageUrl
        description = draft.description
        servings = draft.servings
        prepTime = draft.prepTime
        cookTime = draft.cookTime
        totalTime = draft.totalTime
        // Cap counts to the server's zod limits (categories/cuisines ≤ 20,
        // keywords ≤ 30) so a pathological page with too many tags can't make
        // the whole save fail validation. Item length is bounded server-side.
        categories = Array(draft.categories.prefix(20))
        cuisines = Array(draft.cuisines.prefix(20))
        keywords = Array(draft.keywords.prefix(30))
        ingredients = draft.ingredients.map { RecipeIngredientPayload(rawText: $0) }
        steps = draft.steps.map { RecipeStepPayload(text: $0) }
    }
}

struct RecipeIngredientPayload: Encodable {
    let rawText: String
}

struct RecipeStepPayload: Encodable {
    let text: String
}

struct CreateRecipeResponse: Decodable {
    let recipe: SavedRecipe

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let recipe = try container.decodeIfPresent(SavedRecipe.self, forKey: .recipe) {
            self.recipe = recipe
        } else {
            self.recipe = try SavedRecipe(from: decoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case recipe
    }
}

struct SavedRecipe: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let sourceUrl: String?
    let sourceDomain: String?
    let sourceName: String?
    let heroImageUrl: String?
    let description: String?
    let servings: String?
    let prepTime: String?
    let cookTime: String?
    let totalTime: String?
    let categories: [String]
    let cuisines: [String]
    let keywords: [String]
    let ingredients: [RecipeTextLine]
    let steps: [RecipeTextLine]
    let createdAt: String?
    let updatedAt: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = RecipeLossyDecoding.string(from: container, forKey: .id) ?? UUID().uuidString
        title = RecipeLossyDecoding.string(from: container, forKey: .title) ?? "Imported Recipe"
        sourceUrl = RecipeLossyDecoding.string(from: container, forKey: .sourceUrl)
        sourceDomain = RecipeLossyDecoding.string(from: container, forKey: .sourceDomain)
        sourceName = RecipeLossyDecoding.string(from: container, forKey: .sourceName)
        heroImageUrl = RecipeLossyDecoding.httpURLString(
            RecipeLossyDecoding.string(from: container, forKey: .heroImageUrl)
        )
        description = RecipeLossyDecoding.string(from: container, forKey: .description)
        servings = RecipeLossyDecoding.string(from: container, forKey: .servings)
        prepTime = RecipeLossyDecoding.string(from: container, forKey: .prepTime)
        cookTime = RecipeLossyDecoding.string(from: container, forKey: .cookTime)
        totalTime = RecipeLossyDecoding.string(from: container, forKey: .totalTime)
        categories = RecipeLossyDecoding.stringArray(from: container, forKey: .categories)
        cuisines = RecipeLossyDecoding.stringArray(from: container, forKey: .cuisines)
        keywords = RecipeLossyDecoding.stringArray(from: container, forKey: .keywords)
        ingredients = RecipeLossyDecoding.recipeTextLines(from: container, forKey: .ingredients)
        steps = RecipeLossyDecoding.recipeTextLines(from: container, forKey: .steps)
        createdAt = RecipeLossyDecoding.string(from: container, forKey: .createdAt)
        updatedAt = RecipeLossyDecoding.string(from: container, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case sourceUrl
        case sourceDomain
        case sourceName
        case heroImageUrl
        case description
        case servings
        case prepTime
        case cookTime
        case totalTime
        case categories
        case cuisines
        case keywords
        case ingredients
        case steps
        case createdAt
        case updatedAt
    }
}

struct RecipeTextLine: Decodable, Identifiable, Hashable {
    let id: String
    let text: String
    let position: Int?

    init(id: String = UUID().uuidString, text: String, position: Int? = nil) {
        self.id = id
        self.text = text
        self.position = position
    }

    init(from decoder: Decoder) throws {
        if let value = RecipeLossyDecoding.string(from: decoder) {
            id = UUID().uuidString
            text = value
            position = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = RecipeLossyDecoding.string(from: container, forKey: .id) ?? UUID().uuidString
        text = RecipeLossyDecoding.string(from: container, forKey: .text)
            ?? RecipeLossyDecoding.string(from: container, forKey: .rawText)
            ?? RecipeLossyDecoding.string(from: container, forKey: .name)
            ?? RecipeLossyDecoding.string(from: container, forKey: .value)
            ?? ""
        position = RecipeLossyDecoding.int(from: container, forKey: .position)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case rawText
        case name
        case value
        case position
    }
}

// Shared duration helper. Imported recipe times arrive either as ISO8601
// durations ("PT1H30M", "PT45M") from JSON-LD or as freeform strings
// ("1 hr 30 min", "45 minutes") from the reader/markdown fallback. `minutes`
// powers the drawer's "Quick" filter; `humanLabel` powers display (humanizing
// ISO8601, passing already-human strings through unchanged).
enum RecipeDuration {
    static func minutes(from raw: String?) -> Int? {
        guard let lowered = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !lowered.isEmpty else {
            return nil
        }
        if lowered.hasPrefix("pt"), let iso = isoMinutes(lowered) {
            return iso
        }

        var total = 0
        var matched = false
        if let hours = firstCaptureNumber(in: lowered, pattern: #"(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h)\b"#) {
            total += Int((hours * 60).rounded())
            matched = true
        }
        if let mins = firstCaptureNumber(in: lowered, pattern: #"(\d+(?:\.\d+)?)\s*(?:minutes?|mins?|m)\b"#) {
            total += Int(mins.rounded())
            matched = true
        }
        if !matched, let bare = firstCaptureNumber(in: lowered, pattern: #"(\d+(?:\.\d+)?)"#) {
            total = Int(bare.rounded())
            matched = true
        }
        guard matched, total > 0 else { return nil }
        return total
    }

    static func humanLabel(from raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        // Already-human strings pass through; only ISO8601 needs reformatting.
        guard trimmed.lowercased().hasPrefix("pt"), let mins = minutes(from: trimmed), mins > 0 else {
            return trimmed
        }
        let hours = mins / 60
        let remainder = mins % 60
        if hours > 0 && remainder > 0 { return "\(hours) hr \(remainder) min" }
        if hours > 0 { return "\(hours) hr" }
        return "\(remainder) min"
    }

    private static func isoMinutes(_ lowered: String) -> Int? {
        guard lowered.hasPrefix("pt") else { return nil }
        let body = lowered.dropFirst(2)
        var total = 0
        var number = ""
        var matched = false
        for character in body {
            if character.isNumber || character == "." {
                number.append(character)
                continue
            }
            let value = Double(number)
            number = ""
            guard let value else { continue }
            switch character {
            case "h": total += Int((value * 60).rounded()); matched = true
            case "m": total += Int(value.rounded()); matched = true
            case "s": matched = true // seconds ignored for whole-minute display
            default: break
            }
        }
        return matched ? total : nil
    }

    private static func firstCaptureNumber(in string: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return Double(string[groupRange])
    }
}

// Parses the ISO8601 timestamps SavedRecipe carries (`createdAt`/`updatedAt`,
// produced by the backend's `Date.toISOString()`), with and without fractional
// seconds. Powers the drawer's "Recent" filter.
enum RecipeDateParsing {
    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return withFractional.date(from: string) ?? plain.date(from: string)
    }
}
