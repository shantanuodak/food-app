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
    var servings: String?
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
        servings: String? = nil,
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
        self.servings = servings
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
        servings = RecipeLossyDecoding.string(from: container, forKey: .servings)
            ?? RecipeLossyDecoding.string(from: container, forKey: .recipeYield)
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
        try container.encodeIfPresent(servings, forKey: .servings)
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
        case servings
        case recipeYield
        case ingredients
        case steps
        case confidence
        case warnings
    }
}

struct RecipesResponse: Decodable {
    let recipes: [SavedRecipe]
}

struct CreateRecipeRequest: Encodable {
    let importId: String?
    let title: String
    let sourceUrl: String
    let sourceDomain: String?
    let sourceName: String?
    let heroImageUrl: String?
    let servings: String?
    let ingredients: [RecipeIngredientPayload]
    let steps: [RecipeStepPayload]

    init(draft: RecipeImportDraft) {
        importId = draft.importId
        title = draft.title
        sourceUrl = draft.sourceUrl
        sourceDomain = draft.sourceDomain
        sourceName = draft.sourceName
        heroImageUrl = draft.heroImageUrl
        servings = draft.servings
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
    let servings: String?
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
        servings = RecipeLossyDecoding.string(from: container, forKey: .servings)
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
        case servings
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
